# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Approval < Base
        Registry.register('approval', self)

        def call(state)
          # Check if timed out (when resuming)
          requested_at_str = state.ctx.dig(:_halt, :requested_at)
          if requested_at_str && config.timeout
            requested_at = Time.parse(requested_at_str)
            if Time.now - requested_at > config.timeout
              return continue(state, next_step: config.on_timeout) if config.on_timeout

              raise ExecutionError, 'Approval timeout'

            end
          end

          # Resuming from approval
          if state.ctx.key?(:approved)
            approved = state.ctx[:approved]
            state = state.with(ctx: state.ctx.except(:approved))
            if approved
              return continue(state)
            elsif config.on_reject
              return continue(state, next_step: config.on_reject)
            else
              raise ExecutionError, 'Rejected'
            end
          end

          # Request approval
          halt(state,
               data: {
                 type: :approval,
                 prompt: resolve(state, config.prompt),
                 context: resolve(state, config.context),
                 approvers: config.approvers,
                 timeout: config.timeout,
                 requested_at: Time.now.iso8601
               },
               resume_step: step.id,
               prompt: resolve(state, config.prompt))
        end
      end
    end
  end
end
