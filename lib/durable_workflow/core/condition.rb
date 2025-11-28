# frozen_string_literal: true

module DurableWorkflow
  module Core
    # Stateless condition evaluator
    class ConditionEvaluator
      OPS = {
        "eq"          => ->(v, e) { v == e },
        "neq"         => ->(v, e) { v != e },
        "gt"          => ->(v, e) { v.to_f > e.to_f },
        "lt"          => ->(v, e) { v.to_f < e.to_f },
        "gte"         => ->(v, e) { v.to_f >= e.to_f },
        "lte"         => ->(v, e) { v.to_f <= e.to_f },
        "in"          => ->(v, e) { Array(e).include?(v) },
        "not_in"      => ->(v, e) { !Array(e).include?(v) },
        "contains"    => ->(v, e) { v.to_s.include?(e.to_s) },
        "starts_with" => ->(v, e) { v.to_s.start_with?(e.to_s) },
        "ends_with"   => ->(v, e) { v.to_s.end_with?(e.to_s) },
        "matches"     => ->(v, e) { v.to_s.match?(Regexp.new(e.to_s)) },
        "exists"      => ->(v, _) { !v.nil? },
        "empty"       => ->(v, _) { v.nil? || (v.respond_to?(:empty?) && v.empty?) },
        "truthy"      => ->(v, _) { !!v },
        "falsy"       => ->(v, _) { !v }
      }.freeze

      class << self
        # Evaluate Route or Condition
        def match?(state, cond)
          val = Resolver.resolve(state, "$#{cond.field}")
          exp = Resolver.resolve(state, cond.value)
          op = OPS.fetch(cond.op) { ->(_, _) { false } }
          op.call(val, exp)
        rescue => e
          DurableWorkflow.log(:warn, "Condition failed: #{e.message}", field: cond.field, op: cond.op)
          false
        end

        # Find first matching route
        def find_route(state, routes)
          routes.find { match?(state, _1) }
        end
      end
    end
  end
end
