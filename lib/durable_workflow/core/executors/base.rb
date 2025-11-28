# frozen_string_literal: true

require 'timeout'

module DurableWorkflow
  module Core
    module Executors
      class Base
        attr_reader :step, :config

        def initialize(step)
          @step = step
          @config = step.config
        end

        # Executors receive state and return StepOutcome
        def call(state)
          raise NotImplementedError
        end

        private

        def next_step
          step.next_step
        end

        # Pure resolve - takes state explicitly
        def resolve(state, v)
          Resolver.resolve(state, v)
        end

        # Return StepOutcome with continue result
        def continue(state, next_step: nil, output: nil)
          StepOutcome.new(
            state:,
            result: ContinueResult.new(next_step: next_step || self.next_step, output:)
          )
        end

        # Return StepOutcome with halt result
        def halt(state, data: {}, resume_step: nil, prompt: nil)
          StepOutcome.new(
            state:,
            result: HaltResult.new(data:, resume_step: resume_step || next_step, prompt:)
          )
        end

        # Immutable store - returns new state
        def store(state, key, val)
          return state unless key

          state.with_ctx(key.to_sym => DurableWorkflow::Utils.deep_symbolize(val))
        end

        def with_timeout(seconds = nil, &)
          timeout = seconds || config_timeout
          return yield unless timeout

          Timeout.timeout(timeout, &)
        rescue Timeout::Error
          raise ExecutionError, "Step '#{step.id}' timed out after #{timeout}s"
        end

        def with_retry(max_retries: 0, delay: 1.0, backoff: 2.0)
          attempts = 0
          begin
            attempts += 1
            yield
          rescue StandardError => e
            if attempts <= max_retries
              sleep_time = delay * (backoff**(attempts - 1))
              log(:warn, "Retry #{attempts}/#{max_retries} after #{sleep_time}s", error: e.message)
              sleep(sleep_time)
              retry
            end
            raise
          end
        end

        def config_timeout
          config.respond_to?(:timeout) ? config.timeout : nil
        end

        def log(level, msg, **data)
          DurableWorkflow.log(level, msg, step_id: step.id, step_type: step.type, **data)
        end
      end
    end
  end
end
