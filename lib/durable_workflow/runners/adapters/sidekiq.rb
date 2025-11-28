# frozen_string_literal: true

module DurableWorkflow
  module Runners
    module Adapters
      class Sidekiq
        def initialize(job_class: nil)
          @job_class = job_class || default_job_class
        end

        def enqueue(workflow_id:, workflow_data:, execution_id:, action:, queue: nil, priority: nil, **kwargs)
          job_args = {
            workflow_id:,
            workflow_data:,
            execution_id:,
            action: action.to_s,
            **kwargs.compact
          }

          if queue
            @job_class.set(queue:).perform_async(job_args)
          else
            @job_class.perform_async(job_args)
          end

          execution_id
        end

        private

          def default_job_class
            # Define a default job class if sidekiq is available
            return @default_job_class if defined?(@default_job_class)

            @default_job_class = Class.new do
              if defined?(::Sidekiq::Job)
                include ::Sidekiq::Job

                def perform(args)
                  args = DurableWorkflow::Utils.deep_symbolize(args)

                  workflow = DurableWorkflow.registry[args[:workflow_id]]
                  raise DurableWorkflow::ExecutionError, "Workflow not found: #{args[:workflow_id]}" unless workflow

                  store = DurableWorkflow.config&.store
                  raise DurableWorkflow::ConfigError, "No store configured" unless store

                  engine = DurableWorkflow::Core::Engine.new(workflow, store:)

                  # Engine saves Execution with proper typed status - no manual status update needed
                  case args[:action].to_sym
                  when :start
                    engine.run(input: args[:input], execution_id: args[:execution_id])
                  when :resume
                    engine.resume(args[:execution_id], response: args[:response], approved: args[:approved])
                  end
                end
              end
            end

            # Register in Object so it can be found by Sidekiq
            Object.const_set(:DurableWorkflowJob, @default_job_class) unless defined?(::DurableWorkflowJob)

            @default_job_class
          end
      end
    end
  end
end
