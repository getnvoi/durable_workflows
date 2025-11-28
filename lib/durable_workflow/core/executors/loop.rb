# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Loop < Base
        Registry.register("loop", self)
        MAX_ITER = 100

        def call(state)
          config.over ? foreach_loop(state) : while_loop(state)
        end

        private

          def foreach_loop(state)
            collection = resolve(state, config.over)
            raise ExecutionError, "Loop 'over' must be array" unless collection.is_a?(Array)

            item_key = config.as
            index_key = config.index_as
            max = config.max
            raise ExecutionError, "Collection exceeds max (#{max})" if collection.size > max

            results = []
            collection.each_with_index do |item, i|
              state = store(state, item_key, item)
              state = store(state, index_key, i)
              outcome = execute_body(state)

              # Bubble up halts
              return outcome if outcome.result.is_a?(HaltResult)

              state = outcome.state
              results << outcome.result.output
            end

            state = cleanup(state, item_key, index_key)
            state = store(state, config.output, results)
            continue(state)
          end

          def while_loop(state)
            cond = config.while
            max = config.max
            results = []
            i = 0

            while ConditionEvaluator.match?(state, cond)
              i += 1
              if i > max
                return config.on_exhausted ? continue(state, next_step: config.on_exhausted) : raise(ExecutionError, "Loop exceeded max")
              end
              state = store(state, :iteration, i)
              outcome = execute_body(state)

              # Bubble up halts
              return outcome if outcome.result.is_a?(HaltResult)

              state = outcome.state
              results << outcome.result.output
              break if state.ctx[:break_loop]
            end

            state = cleanup(state, :iteration, :break_loop)
            state = store(state, config.output, results)
            continue(state)
          end

          def execute_body(state)
            body = config.do
            result = nil

            body.each do |step_def|
              executor = Registry[step_def.type]
              raise ExecutionError, "Unknown step type: #{step_def.type}" unless executor

              start_time = Time.now
              outcome = executor.new(step_def).call(state)
              duration = ((Time.now - start_time) * 1000).to_i

              record_nested_entry(state, step_def, outcome, duration)

              # Bubble up halts
              return outcome if outcome.result.is_a?(HaltResult)

              state = outcome.state
              result = outcome.result
            end

            StepOutcome.new(state:, result: result || ContinueResult.new)
          end

          def record_nested_entry(state, step_def, outcome, duration)
            wf_store = DurableWorkflow.config&.store
            return unless wf_store

            wf_store.record(Entry.new(
              id: SecureRandom.uuid,
              execution_id: state.execution_id,
              step_id: "#{step.id}:#{step_def.id}",
              step_type: step_def.type,
              action: outcome.result.is_a?(HaltResult) ? :halted : :completed,
              duration_ms: duration,
              output: outcome.result.output,
              timestamp: Time.now
            ))
          end

          def cleanup(state, *keys)
            new_ctx = state.ctx.except(*keys)
            state.with(ctx: new_ctx)
          end
      end
    end
  end
end
