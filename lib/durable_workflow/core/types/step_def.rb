# frozen_string_literal: true

module DurableWorkflow
  module Core
    class StepDef < BaseStruct
      attribute :id, Types::Strict::String
      attribute :type, Types::StepType  # Just a string, not enum
      attribute :config, Types::Any
      attribute? :next_step, Types::Strict::String.optional
      attribute? :on_error, Types::Strict::String.optional

      def terminal? = type == "end"
    end
  end
end
