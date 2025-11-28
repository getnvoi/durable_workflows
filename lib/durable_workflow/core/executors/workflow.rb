# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class SubWorkflow < Base
        Registry.register("workflow", self)

        def call(state)
          child_wf = DurableWorkflow.registry[config.workflow_id]
          raise ExecutionError, "Workflow not found: #{config.workflow_id}" unless child_wf

          input = resolve(state, config.input) || {}

          result = with_timeout(config.timeout) do
            Engine.new(child_wf, store: DurableWorkflow.config&.store).run(input:)
          end

          case result.status
          when :completed
            state = store(state, config.output, result.output)
            continue(state, output: result.output)
          when :halted
            halt(state, data: result.halt.data, resume_step: step.id, prompt: result.halt.prompt)
          when :failed
            raise ExecutionError, "Sub-workflow failed: #{result.error}"
          end
        end
      end
    end
  end
end
