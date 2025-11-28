# frozen_string_literal: true

require "dry-types"
require "dry-struct"

module DurableWorkflow
  module Types
    include Dry.Types()

    # StepType is just a string - validated at parse time against executor registry
    # This decouples core from extensions (no hardcoded AI types)
    StepType = Types::Strict::String

    # Condition operator enum
    Operator = Types::Strict::String.enum(
      "eq", "neq", "gt", "gte", "lt", "lte",
      "contains", "starts_with", "ends_with", "matches",
      "in", "not_in", "exists", "empty", "truthy", "falsy"
    )

    # Entry action enum
    EntryAction = Types::Strict::Symbol.enum(:completed, :halted, :failed)

    # Wait mode for parallel - default "all"
    WaitMode = Types::Strict::String.default("all").enum("all", "any") | Types::Strict::Integer
  end

  class BaseStruct < Dry::Struct
    transform_keys(&:to_sym)

    def to_h
      super.transform_values do |v|
        case v
        when BaseStruct then v.to_h
        when Array then v.map { |e| e.is_a?(BaseStruct) ? e.to_h : e }
        else v
        end
      end
    end
  end
end
