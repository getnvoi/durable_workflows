# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Assign < Base
        Registry.register('assign', self)

        def call(state)
          state = config.set.reduce(state) do |s, (k, v)|
            store(s, k, resolve(s, v))
          end
          continue(state)
        end
      end
    end
  end
end
