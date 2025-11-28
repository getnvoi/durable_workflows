# frozen_string_literal: true

module DurableWorkflow
  module Core
    # Operator type with default
    OperatorType = Types::Strict::String.default('eq').enum(
      'eq', 'neq', 'gt', 'gte', 'lt', 'lte',
      'contains', 'starts_with', 'ends_with', 'matches',
      'in', 'not_in', 'exists', 'empty', 'truthy', 'falsy'
    )

    class Condition < BaseStruct
      attribute :field, Types::Strict::String
      attribute :op, OperatorType
      attribute :value, Types::Any
    end

    class Route < BaseStruct
      attribute :field, Types::Strict::String
      attribute :op, OperatorType
      attribute :value, Types::Any
      attribute :target, Types::Strict::String
    end
  end
end
