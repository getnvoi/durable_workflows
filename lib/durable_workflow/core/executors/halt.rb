# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Halt < Base
        Registry.register('halt', self)

        def call(state)
          extra_data = resolve(state, config.data)

          halt(state,
               data: {
                 reason: resolve(state, config.reason) || 'Halted',
                 halted_at: Time.now.iso8601,
                 **extra_data
               },
               resume_step: config.resume_step || next_step,
               prompt: resolve(state, config.reason))
        end
      end
    end
  end
end
