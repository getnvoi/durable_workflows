# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Router < Base
        Registry.register('router', self)

        def call(state)
          routes = config.routes
          default = config.default

          route = ConditionEvaluator.find_route(state, routes)

          if route
            continue(state, next_step: route.target)
          elsif default
            continue(state, next_step: default)
          else
            raise ExecutionError, "No matching route and no default for '#{step.id}'"
          end
        end
      end
    end
  end
end
