# 01-STORAGE: Durable Storage Adapters

## Goal

Implement durable storage adapters: Redis, ActiveRecord, and Sequel. No Memory adapter - "durable" means persistent.

**Important**: Storage saves/loads `Execution` objects (not `State`). `Execution` has typed fields:
- `status` (Symbol enum: `:pending`, `:running`, `:completed`, `:halted`, `:failed`)
- `halt_data` (Hash, optional)
- `error` (String, optional)
- `recover_to` (String, optional - step to resume from)
- `result` (Any, optional - final output)
- `ctx` (Hash - clean user workflow variables only)

## Dependencies

- Phase 1 complete

## Files to Create

### 1. `lib/durable_workflow/storage/store.rb` (Interface)

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Storage
    class Store
      # Save execution (typed Execution struct)
      def save(execution)
        raise NotImplementedError
      end

      # Load execution by ID, returns Execution or nil
      def load(execution_id)
        raise NotImplementedError
      end

      # Record audit entry
      def record(entry)
        raise NotImplementedError
      end

      # Get entries for execution
      def entries(execution_id)
        raise NotImplementedError
      end

      # Find executions by criteria
      def find(workflow_id: nil, status: nil, limit: 100)
        raise NotImplementedError
      end

      # Delete execution and its entries
      def delete(execution_id)
        raise NotImplementedError
      end

      # List all execution IDs (for cleanup, admin)
      def execution_ids(workflow_id: nil, limit: 1000)
        raise NotImplementedError
      end
    end
  end
end
```

### 2. `lib/durable_workflow/storage/redis.rb`

```ruby
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
```

### 3. `lib/durable_workflow/storage/active_record.rb`

```ruby
# frozen_string_literal: true

require "json"

module DurableWorkflow
  module Storage
    class ActiveRecord < Store
      # Assumes two tables exist:
      #   workflow_executions: id (uuid), workflow_id, status, input (json), ctx (json),
      #                        current_step, result (json), recover_to, halt_data (json),
      #                        error (text), created_at, updated_at
      #   workflow_entries:    id (uuid), execution_id, step_id, step_type, action,
      #                        duration_ms, input (json), output (json), error, timestamp

      def initialize(execution_class:, entry_class:)
        @execution_class = execution_class
        @entry_class = entry_class
      end

      def save(execution)
        record = @execution_class.find_or_initialize_by(id: execution.id)
        record.assign_attributes(
          workflow_id: execution.workflow_id,
          status: execution.status.to_s,
          input: execution.input.to_json,
          ctx: execution.ctx.to_json,
          current_step: execution.current_step,
          result: execution.result&.to_json,
          recover_to: execution.recover_to,
          halt_data: execution.halt_data&.to_json,
          error: execution.error
        )
        record.save!
        execution
      end

      def load(execution_id)
        record = @execution_class.find_by(id: execution_id)
        return nil unless record

        Core::Execution.new(
          id: record.id,
          workflow_id: record.workflow_id,
          status: record.status.to_sym,
          input: parse_json(record.input),
          ctx: parse_json(record.ctx),
          current_step: record.current_step,
          result: parse_json(record.result),
          recover_to: record.recover_to,
          halt_data: parse_json(record.halt_data),
          error: record.error,
          created_at: record.created_at,
          updated_at: record.updated_at
        )
      end

      def record(entry)
        @entry_class.create!(
          id: entry.id,
          execution_id: entry.execution_id,
          step_id: entry.step_id,
          step_type: entry.step_type,
          action: entry.action.to_s,
          duration_ms: entry.duration_ms,
          input: entry.input&.to_json,
          output: entry.output&.to_json,
          error: entry.error,
          timestamp: entry.timestamp
        )
        entry
      end

      def entries(execution_id)
        @entry_class.where(execution_id:).order(:timestamp).map do |r|
          Core::Entry.new(
            id: r.id,
            execution_id: r.execution_id,
            step_id: r.step_id,
            step_type: r.step_type,
            action: r.action.to_sym,
            duration_ms: r.duration_ms,
            input: parse_json(r.input),
            output: parse_json(r.output),
            error: r.error,
            timestamp: r.timestamp
          )
        end
      end

      def find(workflow_id: nil, status: nil, limit: 100)
        scope = @execution_class.all
        scope = scope.where(workflow_id:) if workflow_id
        scope = scope.where(status: status.to_s) if status
        scope.limit(limit).order(created_at: :desc).map do |record|
          Core::Execution.new(
            id: record.id,
            workflow_id: record.workflow_id,
            status: record.status.to_sym,
            input: parse_json(record.input),
            ctx: parse_json(record.ctx),
            current_step: record.current_step,
            result: parse_json(record.result),
            recover_to: record.recover_to,
            halt_data: parse_json(record.halt_data),
            error: record.error,
            created_at: record.created_at,
            updated_at: record.updated_at
          )
        end
      end

      def delete(execution_id)
        record = @execution_class.find_by(id: execution_id)
        return false unless record

        @entry_class.where(execution_id:).delete_all
        record.destroy
        true
      end

      def execution_ids(workflow_id: nil, limit: 1000)
        scope = @execution_class.all
        scope = scope.where(workflow_id:) if workflow_id
        scope.limit(limit).pluck(:id)
      end

      private

        def parse_json(str)
          return nil if str.nil? || str.empty?
          result = JSON.parse(str)
          result.is_a?(Hash) ? DurableWorkflow::Utils.deep_symbolize(result) : result
        rescue JSON::ParserError
          nil
        end
    end
  end
end
```

### 4. `lib/durable_workflow/storage/sequel.rb`

```ruby
# frozen_string_literal: true

require "json"
require "sequel"

module DurableWorkflow
  module Storage
    class Sequel < Store
      # Tables:
      #   workflow_executions: id (uuid pk), workflow_id, status, input (jsonb), ctx (jsonb),
      #                        current_step, result (jsonb), recover_to, halt_data (jsonb),
      #                        error (text), created_at, updated_at
      #   workflow_entries:    id (uuid pk), execution_id (fk), step_id, step_type, action,
      #                        duration_ms, input (jsonb), output (jsonb), error, timestamp

      def initialize(db:, executions_table: :workflow_executions, entries_table: :workflow_entries)
        @db = db
        @executions = db[executions_table]
        @entries = db[entries_table]
      end

      def save(execution)
        now = Time.now
        data = {
          workflow_id: execution.workflow_id,
          status: execution.status.to_s,
          input: ::Sequel.pg_jsonb(execution.input),
          ctx: ::Sequel.pg_jsonb(execution.ctx),
          current_step: execution.current_step,
          result: execution.result ? ::Sequel.pg_jsonb(execution.result) : nil,
          recover_to: execution.recover_to,
          halt_data: execution.halt_data ? ::Sequel.pg_jsonb(execution.halt_data) : nil,
          error: execution.error,
          updated_at: now
        }

        if @executions.where(id: execution.id).count > 0
          @executions.where(id: execution.id).update(data)
        else
          @executions.insert(data.merge(id: execution.id, created_at: now))
        end

        execution
      end

      def load(execution_id)
        row = @executions.where(id: execution_id).first
        return nil unless row

        Core::Execution.new(
          id: row[:id],
          workflow_id: row[:workflow_id],
          status: row[:status].to_sym,
          input: symbolize(row[:input] || {}),
          ctx: symbolize(row[:ctx] || {}),
          current_step: row[:current_step],
          result: symbolize(row[:result]),
          recover_to: row[:recover_to],
          halt_data: symbolize(row[:halt_data]),
          error: row[:error],
          created_at: row[:created_at],
          updated_at: row[:updated_at]
        )
      end

      def record(entry)
        @entries.insert(
          id: entry.id,
          execution_id: entry.execution_id,
          step_id: entry.step_id,
          step_type: entry.step_type,
          action: entry.action.to_s,
          duration_ms: entry.duration_ms,
          input: entry.input ? ::Sequel.pg_jsonb(entry.input) : nil,
          output: entry.output ? ::Sequel.pg_jsonb(entry.output) : nil,
          error: entry.error,
          timestamp: entry.timestamp
        )
        entry
      end

      def entries(execution_id)
        @entries.where(execution_id:).order(:timestamp).map do |row|
          Core::Entry.new(
            id: row[:id],
            execution_id: row[:execution_id],
            step_id: row[:step_id],
            step_type: row[:step_type],
            action: row[:action].to_sym,
            duration_ms: row[:duration_ms],
            input: symbolize(row[:input]),
            output: symbolize(row[:output]),
            error: row[:error],
            timestamp: row[:timestamp]
          )
        end
      end

      def find(workflow_id: nil, status: nil, limit: 100)
        scope = @executions
        scope = scope.where(workflow_id:) if workflow_id
        scope = scope.where(status: status.to_s) if status
        scope.order(::Sequel.desc(:created_at)).limit(limit).map do |row|
          Core::Execution.new(
            id: row[:id],
            workflow_id: row[:workflow_id],
            status: row[:status].to_sym,
            input: symbolize(row[:input] || {}),
            ctx: symbolize(row[:ctx] || {}),
            current_step: row[:current_step],
            result: symbolize(row[:result]),
            recover_to: row[:recover_to],
            halt_data: symbolize(row[:halt_data]),
            error: row[:error],
            created_at: row[:created_at],
            updated_at: row[:updated_at]
          )
        end
      end

      def delete(execution_id)
        count = @executions.where(id: execution_id).delete
        @entries.where(execution_id:).delete
        count > 0
      end

      def execution_ids(workflow_id: nil, limit: 1000)
        scope = @executions
        scope = scope.where(workflow_id:) if workflow_id
        scope.limit(limit).select_map(:id)
      end

      private

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
```

### 5. Migration Templates

#### For ActiveRecord: `db/migrate/XXX_create_workflow_tables.rb`

```ruby
class CreateWorkflowTables < ActiveRecord::Migration[7.0]
  def change
    create_table :workflow_executions, id: false do |t|
      t.uuid :id, primary_key: true, default: -> { "gen_random_uuid()" }
      t.string :workflow_id, null: false
      t.string :status, null: false, default: "running"
      t.jsonb :input, default: {}
      t.jsonb :ctx, default: {}
      t.string :current_step
      t.jsonb :result                    # Final output when completed
      t.string :recover_to               # Step to resume from
      t.jsonb :halt_data                 # Data from HaltResult
      t.text :error                      # Error message when failed

      t.timestamps
    end

    add_index :workflow_executions, :workflow_id
    add_index :workflow_executions, :status

    create_table :workflow_entries, id: false do |t|
      t.uuid :id, primary_key: true, default: -> { "gen_random_uuid()" }
      t.uuid :execution_id, null: false
      t.string :step_id, null: false
      t.string :step_type, null: false
      t.string :action, null: false
      t.integer :duration_ms
      t.jsonb :input
      t.jsonb :output
      t.text :error
      t.datetime :timestamp, null: false
    end

    add_index :workflow_entries, :execution_id
    add_foreign_key :workflow_entries, :workflow_executions, column: :execution_id
  end
end
```

#### For Sequel:

```ruby
Sequel.migration do
  change do
    create_table :workflow_executions do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      String :workflow_id, null: false
      String :status, null: false, default: "running"
      column :input, :jsonb, default: Sequel.pg_jsonb({})
      column :ctx, :jsonb, default: Sequel.pg_jsonb({})
      String :current_step
      column :result, :jsonb             # Final output when completed
      String :recover_to                 # Step to resume from
      column :halt_data, :jsonb          # Data from HaltResult
      String :error, text: true          # Error message when failed
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :workflow_id
      index :status
    end

    create_table :workflow_entries do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :execution_id, :workflow_executions, type: :uuid, null: false
      String :step_id, null: false
      String :step_type, null: false
      String :action, null: false
      Integer :duration_ms
      column :input, :jsonb
      column :output, :jsonb
      String :error, text: true
      DateTime :timestamp, null: false

      index :execution_id
    end
  end
end
```

## Usage

### Redis

```ruby
require "durable_workflow"
require "durable_workflow/storage/redis"

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end
```

### ActiveRecord

```ruby
require "durable_workflow"
require "durable_workflow/storage/active_record"

# Define your models
class WorkflowExecution < ApplicationRecord
  self.table_name = "workflow_executions"
end

class WorkflowEntry < ApplicationRecord
  self.table_name = "workflow_entries"
end

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::ActiveRecord.new(
    execution_class: WorkflowExecution,
    entry_class: WorkflowEntry
  )
end
```

### Sequel

```ruby
require "durable_workflow"
require "durable_workflow/storage/sequel"

DB = Sequel.connect("postgres://localhost/myapp")

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Sequel.new(db: DB)
end
```

## Acceptance Criteria

1. Redis adapter saves/loads Execution correctly (typed status, halt_data, error, recover_to)
2. ActiveRecord adapter works with standard Rails models
3. Sequel adapter works with Postgres JSONB
4. All adapters implement full Store interface
5. Entries are properly linked to executions
6. `find(status: :halted)` uses typed status field (not ctx[:_status])
7. `execution.to_state` conversion works for resume
8. No `ctx[:_status]`, `ctx[:_halt]`, `ctx[:_error]` - all in typed Execution fields
