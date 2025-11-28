# frozen_string_literal: true

module DurableWorkflow
  module Core
    class ContinueResult < BaseStruct
      attribute? :next_step, Types::Strict::String.optional
      attribute? :output, Types::Any
    end

    class HaltResult < BaseStruct
      # data is required (no default) - distinguishes from ContinueResult in union
      attribute :data, Types::Hash
      attribute? :resume_step, Types::Strict::String.optional
      attribute? :prompt, Types::Strict::String.optional

      # Common interface with ContinueResult
      def output = data
    end

    # ExecutionResult - returned by Engine.run/resume
    # Note: ErrorResult removed - errors are captured in Execution.error field
    class ExecutionResult < BaseStruct
      attribute :status, ExecutionStatus
      attribute :execution_id, Types::Strict::String
      attribute? :output, Types::Any
      attribute? :halt, HaltResult.optional
      attribute? :error, Types::Strict::String.optional

      def completed? = status == :completed
      def halted? = status == :halted
      def failed? = status == :failed
    end

    # Outcome of executing a step: new state + result
    # HaltResult first - has required `data` field, so union can distinguish
    class StepOutcome < BaseStruct
      attribute :state, State
      attribute :result, HaltResult | ContinueResult
    end
  end
end
