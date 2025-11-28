# frozen_string_literal: true

module DurableWorkflow
  module Runners
    module Adapters
      class Inline
        def initialize(store: nil)
          @store = store
        end

        def enqueue(workflow_id:, workflow_data:, execution_id:, action:, **kwargs)
          # Execute immediately in current thread (for testing/dev)
          perform(
            workflow_id:,
            workflow_data:,
            execution_id:,
            action:,
            **kwargs
          )
        end

        def perform(workflow_id:, workflow_data:, execution_id:, action:, input: {}, response: nil, approved: nil, **_)
          workflow = DurableWorkflow.registry[workflow_id]
          raise ExecutionError, "Workflow not found: #{workflow_id}" unless workflow

          store = @store || DurableWorkflow.config&.store
          raise ConfigError, 'No store configured' unless store

          engine = Core::Engine.new(workflow, store:)

          # Engine saves Execution with proper typed status - no manual status update needed
          case action.to_sym
          when :start
            engine.run(input:, execution_id:)
          when :resume
            engine.resume(execution_id, response:, approved:)
          end
        end
      end
    end
  end
end
