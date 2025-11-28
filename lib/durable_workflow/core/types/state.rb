# frozen_string_literal: true

module DurableWorkflow
  module Core
    # Runtime state - immutable during execution
    # Used by executors. Contains only workflow variables in ctx (no internal _prefixed fields).
    class State < BaseStruct
      attribute :execution_id, Types::Strict::String
      attribute :workflow_id, Types::Strict::String
      attribute :input, Types::Hash.default({}.freeze)
      attribute :ctx, Types::Hash.default({}.freeze)  # User workflow variables only
      attribute? :current_step, Types::Strict::String.optional
      attribute :history, Types::Strict::Array.default([].freeze)

      # Immutable update helpers
      def with(**updates)
        self.class.new(to_h.merge(updates))
      end

      def with_ctx(**updates)
        with(ctx: ctx.merge(DurableWorkflow::Utils.deep_symbolize(updates)))
      end

      def with_current_step(step_id)
        with(current_step: step_id)
      end
    end

    # Execution status enum
    ExecutionStatus = Types::Strict::Symbol.enum(:pending, :running, :completed, :halted, :failed)

    # Typed execution record for storage
    # Storage layer saves/loads Execution, Engine works with State internally.
    # This separation keeps ctx clean and provides typed status/halt_data/error fields.
    class Execution < BaseStruct
      attribute :id, Types::Strict::String
      attribute :workflow_id, Types::Strict::String
      attribute :status, ExecutionStatus
      attribute :input, Types::Hash.default({}.freeze)
      attribute :ctx, Types::Hash.default({}.freeze)  # User workflow variables only
      attribute? :current_step, Types::Strict::String.optional
      attribute? :result, Types::Any                   # Final output when completed
      attribute? :recover_to, Types::Strict::String.optional  # Step to resume from
      attribute? :halt_data, Types::Hash.optional      # Data from HaltResult
      attribute? :error, Types::Strict::String.optional  # Error message when failed
      attribute? :created_at, Types::Any
      attribute? :updated_at, Types::Any

      # Convert to State for executor use
      def to_state
        State.new(
          execution_id: id,
          workflow_id: workflow_id,
          input: input,
          ctx: ctx,
          current_step: current_step
        )
      end

      # Build from State + ExecutionResult
      def self.from_state(state, result)
        new(
          id: state.execution_id,
          workflow_id: state.workflow_id,
          status: result.status,
          input: state.input,
          ctx: state.ctx,
          current_step: state.current_step,
          result: result.output,
          recover_to: result.halt&.resume_step,
          halt_data: result.halt&.data,
          error: result.error,
          updated_at: Time.now
        )
      end

      def self.from_h(hash)
        new(
          id: hash[:id],
          workflow_id: hash[:workflow_id],
          status: hash[:status]&.to_sym || :pending,
          input: DurableWorkflow::Utils.deep_symbolize(hash[:input] || {}),
          ctx: DurableWorkflow::Utils.deep_symbolize(hash[:ctx] || {}),
          current_step: hash[:current_step],
          result: hash[:result],
          recover_to: hash[:recover_to],
          halt_data: hash[:halt_data],
          error: hash[:error],
          created_at: hash[:created_at],
          updated_at: hash[:updated_at]
        )
      end
    end
  end
end
