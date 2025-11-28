# frozen_string_literal: true

require "json"
require "redis"

module DurableWorkflow
  module Storage
    class Redis < Store
      PREFIX = "durable_workflow"

      def initialize(redis: nil, url: nil, ttl: 86400 * 7)
        @redis = redis || ::Redis.new(url:)
        @ttl = ttl
      end

      def save(execution)
        key = exec_key(execution.id)
        data = serialize_execution(execution)
        @redis.setex(key, @ttl, data)
        index_add(execution)
        execution
      end

      def load(execution_id)
        data = @redis.get(exec_key(execution_id))
        data ? deserialize_execution(data) : nil
      end

      def record(entry)
        key = entries_key(entry.execution_id)
        data = serialize_entry(entry)
        @redis.rpush(key, data)
        @redis.expire(key, @ttl)
        entry
      end

      def entries(execution_id)
        key = entries_key(execution_id)
        @redis.lrange(key, 0, -1).map { deserialize_entry(_1) }
      end

      def find(workflow_id: nil, status: nil, limit: 100)
        ids = if workflow_id
          @redis.smembers(index_key(workflow_id)).first(limit)
        else
          scan_execution_ids(limit)
        end

        results = ids.filter_map { load(_1) }
        results = results.select { _1.status == status } if status
        results.first(limit)
      end

      def delete(execution_id)
        execution = load(execution_id)
        return false unless execution

        @redis.del(exec_key(execution_id))
        @redis.del(entries_key(execution_id))
        index_remove(execution)
        true
      end

      def execution_ids(workflow_id: nil, limit: 1000)
        if workflow_id
          @redis.smembers(index_key(workflow_id)).first(limit)
        else
          scan_execution_ids(limit)
        end
      end

      private

        def exec_key(id)
          "#{PREFIX}:exec:#{id}"
        end

        def entries_key(id)
          "#{PREFIX}:entries:#{id}"
        end

        def index_key(wf_id)
          "#{PREFIX}:idx:#{wf_id}"
        end

        def index_add(execution)
          @redis.sadd(index_key(execution.workflow_id), execution.id)
        end

        def index_remove(execution)
          @redis.srem(index_key(execution.workflow_id), execution.id)
        end

        def scan_execution_ids(limit)
          ids = []
          cursor = "0"
          pattern = "#{PREFIX}:exec:*"

          loop do
            cursor, keys = @redis.scan(cursor, match: pattern, count: 100)
            ids.concat(keys.map { _1.split(":").last })
            break if cursor == "0" || ids.size >= limit
          end

          ids.first(limit)
        end

        def serialize_execution(execution)
          JSON.generate(execution.to_h)
        end

        def deserialize_execution(json)
          Core::Execution.from_h(symbolize(JSON.parse(json)))
        end

        def serialize_entry(entry)
          JSON.generate(entry.to_h)
        end

        def deserialize_entry(json)
          Core::Entry.from_h(symbolize(JSON.parse(json)))
        end

        def symbolize(obj)
          case obj
          when Hash then obj.transform_keys(&:to_sym).transform_values { symbolize(_1) }
          when Array then obj.map { symbolize(_1) }
          else obj
          end
        end
    end
  end
end
