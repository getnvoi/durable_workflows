# frozen_string_literal: true

module DurableWorkflow
  module Core
    # Base for all step configs
    class StepConfig < BaseStruct; end

    class StartConfig < StepConfig
      attribute? :validate_input, Types::Strict::Bool.default(false)
    end

    class EndConfig < StepConfig
      attribute? :result, Types::Any
    end

    # Output with optional schema validation
    class OutputConfig < BaseStruct
      attribute :key, Types::Coercible::Symbol
      attribute? :schema, Types::Hash.optional
    end

    class CallConfig < StepConfig
      attribute :service, Types::Strict::String
      attribute :method_name, Types::Strict::String
      attribute? :input, Types::Any
      attribute? :output, Types::Coercible::Symbol.optional | OutputConfig
      attribute? :timeout, Types::Strict::Integer.optional
      attribute? :retries, Types::Strict::Integer.optional.default(0)
      attribute? :retry_delay, Types::Strict::Float.optional.default(1.0)
      attribute? :retry_backoff, Types::Strict::Float.optional.default(2.0)
    end

    class AssignConfig < StepConfig
      attribute :set, Types::Hash.default({}.freeze)
    end

    class RouterConfig < StepConfig
      attribute :routes, Types::Strict::Array.default([].freeze)
      attribute? :default, Types::Strict::String.optional
    end

    class LoopConfig < StepConfig
      # foreach mode
      attribute? :over, Types::Any
      attribute? :as, Types::Coercible::Symbol.optional.default(:item)
      attribute? :index_as, Types::Coercible::Symbol.optional.default(:index)
      # while mode
      attribute? :while, Types::Any
      # shared
      attribute? :do, Types::Strict::Array.default([].freeze)
      attribute? :output, Types::Coercible::Symbol.optional
      attribute? :max, Types::Strict::Integer.optional.default(100)
      attribute? :on_exhausted, Types::Strict::String.optional
    end

    class HaltConfig < StepConfig
      attribute? :reason, Types::Strict::String.optional
      attribute? :data, Types::Hash.default({}.freeze)
      attribute? :resume_step, Types::Strict::String.optional
    end

    class ApprovalConfig < StepConfig
      attribute :prompt, Types::Strict::String
      attribute? :context, Types::Any
      attribute? :approvers, Types::Strict::Array.of(Types::Strict::String).optional
      attribute? :on_reject, Types::Strict::String.optional
      attribute? :timeout, Types::Strict::Integer.optional
      attribute? :on_timeout, Types::Strict::String.optional
    end

    class TransformConfig < StepConfig
      attribute? :input, Types::Strict::String.optional
      attribute :expression, Types::Hash
      attribute :output, Types::Coercible::Symbol
    end

    class ParallelConfig < StepConfig
      attribute :branches, Types::Strict::Array.default([].freeze)
      attribute? :wait, Types::WaitMode
      attribute? :output, Types::Coercible::Symbol.optional
    end

    class WorkflowConfig < StepConfig
      attribute :workflow_id, Types::Strict::String
      attribute? :input, Types::Any
      attribute? :output, Types::Coercible::Symbol.optional
      attribute? :timeout, Types::Strict::Integer.optional
    end

    # Register core config types
    Core.register_config('start', StartConfig)
    Core.register_config('end', EndConfig)
    Core.register_config('call', CallConfig)
    Core.register_config('assign', AssignConfig)
    Core.register_config('router', RouterConfig)
    Core.register_config('loop', LoopConfig)
    Core.register_config('halt', HaltConfig)
    Core.register_config('approval', ApprovalConfig)
    Core.register_config('transform', TransformConfig)
    Core.register_config('parallel', ParallelConfig)
    Core.register_config('workflow', WorkflowConfig)
  end
end
