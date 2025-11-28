# frozen_string_literal: true

module DurableWorkflow
  module Storage
    # Abstract base class for storage backends
    class Store
      # Save execution state
      def save(state)
        raise NotImplementedError
      end

      # Load execution state by ID
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

      # Find executions
      def find(workflow_id: nil, status: nil, limit: 100)
        raise NotImplementedError
      end

      # Delete execution
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
