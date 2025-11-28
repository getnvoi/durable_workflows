# frozen_string_literal: true

module DurableWorkflow
  module Core
    class InputDef < BaseStruct
      attribute :name, Types::Strict::String
      attribute? :type, Types::Strict::String.optional.default("string")
      attribute? :required, Types::Strict::Bool.default(true)
      attribute? :default, Types::Any
      attribute? :description, Types::Strict::String.optional
    end

    class WorkflowDef < BaseStruct
      attribute :id, Types::Strict::String
      attribute :name, Types::Strict::String
      attribute? :version, Types::Strict::String.optional.default("1.0")
      attribute? :description, Types::Strict::String.optional
      attribute? :timeout, Types::Strict::Integer.optional
      attribute :inputs, Types::Strict::Array.of(InputDef).default([].freeze)
      attribute :steps, Types::Strict::Array.of(StepDef).default([].freeze)
      # Generic extension data - AI extension stores agents/tools here
      attribute? :extensions, Types::Hash.default({}.freeze)

      def find_step(id) = steps.find { _1.id == id }
      def first_step = steps.first
      def step_ids = steps.map(&:id)

      # Immutable update - preserve struct instances
      def with(**updates)
        self.class.new(
          id: updates.fetch(:id, id),
          name: updates.fetch(:name, name),
          version: updates.fetch(:version, version),
          description: updates.fetch(:description, description),
          timeout: updates.fetch(:timeout, timeout),
          inputs: updates.fetch(:inputs, inputs),
          steps: updates.fetch(:steps, steps),
          extensions: updates.fetch(:extensions, extensions)
        )
      end
    end
  end
end
