# frozen_string_literal: true

module DurableWorkflow
  module Storage
    # In-memory store for testing only
    class TestStore < Store
      def initialize
        @executions = {}
        @entries = Hash.new { |h, k| h[k] = [] }
      end

      def save(execution)
        @executions[execution.id] = execution
      end

      def load(execution_id)
        @executions[execution_id]
      end

      def record(entry)
        @entries[entry.execution_id] << entry
      end

      def entries(execution_id)
        @entries[execution_id]
      end

      def find(workflow_id: nil, status: nil, limit: 100)
        results = @executions.values
        results = results.select { |e| e.workflow_id == workflow_id } if workflow_id
        results = results.select { |e| e.status == status } if status
        results.first(limit)
      end

      def delete(execution_id)
        deleted = @executions.delete(execution_id)
        @entries.delete(execution_id)
        !deleted.nil?
      end

      def execution_ids(workflow_id: nil, limit: 1000)
        results = @executions.values
        results = results.select { |e| e.workflow_id == workflow_id } if workflow_id
        results.first(limit).map(&:id)
      end

      def clear!
        @executions.clear
        @entries.clear
      end
    end
  end
end
