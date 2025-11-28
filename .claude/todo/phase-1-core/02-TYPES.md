# 02-TYPES: Core Type Definitions

## Goal

Define all core types using dry-struct. **Critical change**: `StepType` is no longer an enum - it's a simple string validated against the executor registry at parse time. This decouples core from AI types.

## Dependencies

- 01-GEMSPEC completed

## Files to Create

### 1. `lib/durable_workflow/core/types.rb` (loader)

```ruby
# frozen_string_literal: true

# Load base types first
require_relative "types/base"
require_relative "types/condition"
require_relative "types/configs"
require_relative "types/step_def"
require_relative "types/workflow_def"
require_relative "types/state"
require_relative "types/entry"
require_relative "types/results"
```

### 2. `lib/durable_workflow/core/types/base.rb`

```ruby
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
      "contains", "starts_with", "ends_with", "in", "exists"
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
```

### 3. `lib/durable_workflow/core/types/condition.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    # Operator type with default
    OperatorType = Types::Strict::String.default("eq").enum(
      "eq", "neq", "gt", "gte", "lt", "lte",
      "contains", "starts_with", "ends_with", "in", "exists"
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
```

### 4. `lib/durable_workflow/core/types/configs.rb`

```ruby
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

    class CallConfig < StepConfig
      attribute :service, Types::Strict::String
      attribute :method_name, Types::Strict::String
      attribute? :input, Types::Any
      attribute? :output, Types::Coercible::Symbol.optional
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

    # Registry mapping type -> config class
    # Extensions add to this registry
    CONFIG_REGISTRY = {
      "start" => StartConfig,
      "end" => EndConfig,
      "call" => CallConfig,
      "assign" => AssignConfig,
      "router" => RouterConfig,
      "loop" => LoopConfig,
      "halt" => HaltConfig,
      "approval" => ApprovalConfig,
      "transform" => TransformConfig,
      "parallel" => ParallelConfig,
      "workflow" => WorkflowConfig
    }

    # Allow extensions to register config classes
    def self.register_config(type, klass)
      CONFIG_REGISTRY[type.to_s] = klass
    end
  end
end
```

### 5. `lib/durable_workflow/core/types/step_def.rb`

```ruby
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
```

### 6. `lib/durable_workflow/core/types/workflow_def.rb`

```ruby
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
    end
  end
end
```

### 7. `lib/durable_workflow/core/types/state.rb`

```ruby
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
```

### 8. `lib/durable_workflow/core/types/entry.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    class Entry < BaseStruct
      attribute :id, Types::Strict::String
      attribute :execution_id, Types::Strict::String
      attribute :step_id, Types::Strict::String
      attribute :step_type, Types::StepType  # Just a string
      attribute :action, Types::EntryAction
      attribute? :duration_ms, Types::Strict::Integer.optional
      attribute? :input, Types::Any
      attribute? :output, Types::Any
      attribute? :error, Types::Strict::String.optional
      attribute :timestamp, Types::Any

      def self.from_h(h)
        new(
          **h,
          action: h[:action]&.to_sym,
          timestamp: h[:timestamp].is_a?(String) ? Time.parse(h[:timestamp]) : h[:timestamp]
        )
      end
    end
  end
end
```

### 9. `lib/durable_workflow/core/types/results.rb`

```ruby
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
```

## Key Changes from Original

1. **`StepType` is now just `Types::Strict::String`** - no enum, no hardcoded types
2. **`WorkflowDef` has `extensions` instead of `agents`/`tools`** - generic hash for extension data
3. **`CONFIG_REGISTRY` is mutable** - extensions call `Core.register_config(type, klass)` to add their configs
4. **No `MessageRole` in core** - that's AI-specific, lives in extension
5. **`State` vs `Execution` separation** - State for runtime (clean ctx), Execution for storage (typed status/halt_data/error)
6. **`ErrorResult` removed** - errors captured in `Execution.error` field
7. **`ExecutionStatus` enum** - `:pending`, `:running`, `:completed`, `:halted`, `:failed`

## Acceptance Criteria

1. Can create State, StepDef, WorkflowDef without AI types
2. `StepDef.new(id: "x", type: "anything", config: {})` succeeds (type is just string)
3. `Core.register_config("custom", MyConfig)` adds to registry
4. `WorkflowDef` has no `agents` or `tools` attributes
5. `Execution.from_state(state, result)` creates typed Execution from State + ExecutionResult
6. `execution.to_state` converts back to State for executor use
7. `ctx` contains only user workflow variables - no `_status`, `_halt`, `_error`, `_resume_step`
