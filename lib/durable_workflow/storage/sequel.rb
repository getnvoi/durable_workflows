# frozen_string_literal: true

require 'json'
require 'sequel'

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

        if @executions.where(id: execution.id).any?
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
        count.positive?
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
