# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class End < Base
        FINISHED = "__FINISHED__"
        Registry.register("end", self)

        def call(state)
          raw = config.result || state.ctx.dup
          result = resolve(state, raw)
          state = store(state, :result, result)
          continue(state, next_step: FINISHED, output: result)
        end
      end
    end
  end
end
