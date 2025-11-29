# frozen_string_literal: true

require 'timeout'

module DurableWorkflow
  module Core
    class Engine
      FINISHED = '__FINISHED__'

      attr_reader :workflow, :store

      def initialize(workflow, store: nil)
        @workflow = workflow
        @store = store || DurableWorkflow.config&.store
        raise ConfigError, 'No store configured. Use Redis, ActiveRecord, or Sequel.' unless @store
      end

      def run(input: {}, execution_id: nil)
        exec_id = execution_id || SecureRandom.uuid

        state = State.new(
          execution_id: exec_id,
          workflow_id: workflow.id,
          input: DurableWorkflow::Utils.deep_symbolize(input)
        )

        # Save initial Execution with :running status
        save_execution(state, ExecutionResult.new(status: :running, execution_id: exec_id))

        if workflow.timeout
          Timeout.timeout(workflow.timeout) do
            execute_from(state, workflow.first_step.id)
          end
        else
          execute_from(state, workflow.first_step.id)
        end
      rescue Timeout::Error
        result = ExecutionResult.new(status: :failed, execution_id: state.execution_id, error: "Workflow timeout after #{workflow.timeout}s")
        save_execution(state, result)
        result
      end

      def resume(execution_id, response: nil, approved: nil)
        execution = @store.load(execution_id)
        raise ExecutionError, "Execution not found: #{execution_id}" unless execution

        state = execution.to_state
        state = state.with_ctx(response:) if response
        state = state.with_ctx(approved:) unless approved.nil?

        # Use recover_to from Execution, or fall back to current_step
        resume_step = execution.recover_to || execution.current_step

        execute_from(state, resume_step)
      end

      private

      def execute_from(state, step_id)
        while step_id && step_id != FINISHED
          state = state.with_current_step(step_id)

          # Save intermediate state as :running
          save_execution(state, ExecutionResult.new(status: :running, execution_id: state.execution_id))

          step = workflow.find_step(step_id)
          raise ExecutionError, "Step not found: #{step_id}" unless step

          outcome = execute_step(state, step)
          state = outcome.state

          case outcome.result
          when HaltResult
            return handle_halt(state, outcome.result)
          when ContinueResult
            step_id = outcome.result.next_step
          else
            raise ExecutionError, "Unknown result: #{outcome.result.class}"
          end
        end

        # Completed
        result = ExecutionResult.new(status: :completed, execution_id: state.execution_id, output: state.ctx[:result])
        save_execution(state, result)
        result
      end

      def execute_step(state, step)
        executor_class = Executors::Registry[step.type]
        raise ExecutionError, "No executor for: #{step.type}" unless executor_class

        start = Time.now
        outcome = executor_class.new(step).call(state)
        duration = ((Time.now - start) * 1000).to_i

        @store.record(Entry.new(
                        id: SecureRandom.uuid,
                        execution_id: state.execution_id,
                        step_id: step.id,
                        step_type: step.type,
                        action: outcome.result.is_a?(HaltResult) ? :halted : :completed,
                        duration_ms: duration,
                        output: outcome.result.output,
                        timestamp: Time.now
                      ))

        outcome
      rescue StandardError => e
        @store.record(Entry.new(
                        id: SecureRandom.uuid,
                        execution_id: state.execution_id,
                        step_id: step.id,
                        step_type: step.type,
                        action: :failed,
                        error: "#{e.class}: #{e.message}",
                        timestamp: Time.now
                      ))

        if step.on_error
          # Store error info in ctx for access by error handler step
          error_state = state.with_ctx(_last_error: { step: step.id, message: e.message, class: e.class.name })
          return StepOutcome.new(state: error_state, result: ContinueResult.new(next_step: step.on_error))
        end

        # Persist failed status before re-raising
        result = ExecutionResult.new(status: :failed, execution_id: state.execution_id, error: "#{e.class}: #{e.message}")
        save_execution(state, result)

        raise
      end

      def handle_halt(state, halt_result)
        result = ExecutionResult.new(
          status: :halted,
          execution_id: state.execution_id,
          output: state.ctx[:result],
          halt: halt_result
        )
        save_execution(state, result)
        result
      end

      def save_execution(state, result)
        execution = Execution.from_state(state, result)
        @store.save(execution)
      end
    end
  end
end
