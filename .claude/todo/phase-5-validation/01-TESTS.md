# 01-TESTS: Minitest Test Suite

## Goal

Complete test coverage using Minitest for all components: types, executors, engine, parser, storage, runners, and extensions.

## Dependencies

- Phase 1 complete
- Phase 2 complete
- Phase 3 complete

## Test Structure

```
test/
├── test_helper.rb
├── core/
│   ├── types_test.rb
│   ├── state_test.rb
│   ├── engine_test.rb
│   ├── registry_test.rb
│   ├── resolver_test.rb
│   ├── condition_test.rb
│   ├── validator_test.rb
│   └── executors/
│       ├── start_test.rb
│       ├── end_test.rb
│       ├── call_test.rb
│       ├── assign_test.rb
│       ├── router_test.rb
│       ├── loop_test.rb
│       ├── halt_test.rb
│       ├── approval_test.rb
│       ├── transform_test.rb
│       ├── parallel_test.rb
│       └── workflow_test.rb
├── parser_test.rb
├── storage/
│   ├── redis_test.rb
│   ├── active_record_test.rb
│   └── sequel_test.rb
├── runners/
│   ├── sync_test.rb
│   ├── async_test.rb
│   └── stream_test.rb
└── extensions/
    ├── base_test.rb
    └── ai/
        ├── extension_test.rb
        ├── agent_executor_test.rb
        └── tool_executor_test.rb
```

## Files to Create

### 1. `test/test_helper.rb`

```ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "minitest/pride"
require "mocha/minitest"

require "durable_workflow"

# Test-only storage adapter (in-memory)
# NOTE: This is NOT shipped with the gem - it's only in test_helper.rb
# Production code must use Redis, ActiveRecord, or Sequel
module DurableWorkflow
  module Storage
    class Memory < Store
      def initialize
        @states = {}
        @entries = {}
      end

      def save(state)
        @states[state.execution_id] = state
        state
      end

      def load(execution_id)
        @states[execution_id]
      end

      def record(entry)
        @entries[entry.execution_id] ||= []
        @entries[entry.execution_id] << entry
        entry
      end

      def entries(execution_id)
        @entries[execution_id] || []
      end

      def find(workflow_id: nil, status: nil, limit: 100)
        results = @states.values
        results = results.select { _1.workflow_id == workflow_id } if workflow_id
        results = results.select { _1.ctx[:_status] == status } if status
        results.first(limit)
      end

      def delete(execution_id)
        deleted = @states.delete(execution_id)
        @entries.delete(execution_id)
        !!deleted
      end

      def execution_ids(workflow_id: nil, limit: 1000)
        ids = @states.keys
        ids = ids.select { @states[_1].workflow_id == workflow_id } if workflow_id
        ids.first(limit)
      end

      def clear!
        @states.clear
        @entries.clear
      end
    end
  end
end

# Test fixtures
module TestFixtures
  def simple_workflow_yaml
    <<~YAML
      id: test_workflow
      name: Test Workflow
      version: "1.0"
      input_schema:
        type: object
        properties:
          value:
            type: integer
      steps:
        - id: start
          type: start
          next: process
        - id: process
          type: assign
          config:
            assignments:
              result: "$.input.value * 2"
          next: done
        - id: done
          type: end
    YAML
  end

  def router_workflow_yaml
    <<~YAML
      id: router_test
      name: Router Test
      version: "1.0"
      steps:
        - id: start
          type: start
          next: route
        - id: route
          type: router
          config:
            routes:
              - condition: "$.input.path == 'a'"
                next: path_a
              - condition: "$.input.path == 'b'"
                next: path_b
            default: path_default
        - id: path_a
          type: assign
          config:
            assignments:
              result: "'went_a'"
          next: done
        - id: path_b
          type: assign
          config:
            assignments:
              result: "'went_b'"
          next: done
        - id: path_default
          type: assign
          config:
            assignments:
              result: "'went_default'"
          next: done
        - id: done
          type: end
    YAML
  end

  def loop_workflow_yaml
    <<~YAML
      id: loop_test
      name: Loop Test
      version: "1.0"
      steps:
        - id: start
          type: start
          next: init
        - id: init
          type: assign
          config:
            assignments:
              counter: 0
              sum: 0
          next: loop
        - id: loop
          type: loop
          config:
            collection: "$.input.items"
            item_var: item
            body:
              - id: add
                type: assign
                config:
                  assignments:
                    counter: "$.ctx.counter + 1"
                    sum: "$.ctx.sum + $.ctx.item"
          next: done
        - id: done
          type: end
    YAML
  end

  def halt_workflow_yaml
    <<~YAML
      id: halt_test
      name: Halt Test
      version: "1.0"
      steps:
        - id: start
          type: start
          next: halting
        - id: halting
          type: halt
          config:
            data:
              message: "Waiting for input"
          next: after_halt
        - id: after_halt
          type: assign
          config:
            assignments:
              result: "$.ctx._response"
          next: done
        - id: done
          type: end
    YAML
  end

  def approval_workflow_yaml
    <<~YAML
      id: approval_test
      name: Approval Test
      version: "1.0"
      steps:
        - id: start
          type: start
          next: approve
        - id: approve
          type: approval
          config:
            prompt: "Do you approve?"
            approved_next: approved_path
            rejected_next: rejected_path
        - id: approved_path
          type: assign
          config:
            assignments:
              result: "'approved'"
          next: done
        - id: rejected_path
          type: assign
          config:
            assignments:
              result: "'rejected'"
          next: done
        - id: done
          type: end
    YAML
  end

  def parallel_workflow_yaml
    <<~YAML
      id: parallel_test
      name: Parallel Test
      version: "1.0"
      steps:
        - id: start
          type: start
          next: parallel
        - id: parallel
          type: parallel
          config:
            branches:
              branch_a:
                - id: a1
                  type: assign
                  config:
                    assignments:
                      a_result: "'from_a'"
              branch_b:
                - id: b1
                  type: assign
                  config:
                    assignments:
                      b_result: "'from_b'"
            merge_strategy: all
          next: done
        - id: done
          type: end
    YAML
  end

  def call_workflow_yaml
    <<~YAML
      id: call_test
      name: Call Test
      version: "1.0"
      steps:
        - id: start
          type: start
          next: call_service
        - id: call_service
          type: call
          config:
            service: test_service
            method: echo
            args:
              message: "$.input.message"
          next: done
        - id: done
          type: end
    YAML
  end

  def transform_workflow_yaml
    <<~YAML
      id: transform_test
      name: Transform Test
      version: "1.0"
      steps:
        - id: start
          type: start
          next: transform
        - id: transform
          type: transform
          config:
            source: "$.input.data"
            template:
              name: "$.item.first_name + ' ' + $.item.last_name"
              email: "$.item.email"
          next: done
        - id: done
          type: end
    YAML
  end

  def workflow_step_yaml
    <<~YAML
      id: parent_workflow
      name: Parent Workflow
      version: "1.0"
      steps:
        - id: start
          type: start
          next: sub
        - id: sub
          type: workflow
          config:
            workflow_id: child_workflow
            input:
              value: "$.input.value"
          next: done
        - id: done
          type: end
    YAML
  end

  def child_workflow_yaml
    <<~YAML
      id: child_workflow
      name: Child Workflow
      version: "1.0"
      steps:
        - id: start
          type: start
          next: double
        - id: double
          type: assign
          config:
            assignments:
              result: "$.input.value * 2"
          next: done
        - id: done
          type: end
    YAML
  end
end

class DurableWorkflowTest < Minitest::Test
  include TestFixtures

  def setup
    @store = DurableWorkflow::Storage::Memory.new
    DurableWorkflow.configure do |c|
      c.store = @store
    end
    DurableWorkflow.registry.clear if DurableWorkflow.registry.respond_to?(:clear)
  end

  def teardown
    @store.clear!
  end
end
```

### 2. `test/core/types_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class TypesTest < DurableWorkflowTest
  def test_state_creation
    state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: { value: 42 }
    )

    assert_equal "exec-1", state.execution_id
    assert_equal "wf-1", state.workflow_id
    assert_equal({ value: 42 }, state.input)
    assert_equal({}, state.ctx)
    assert_nil state.current_step
    assert_equal [], state.history
  end

  def test_state_with_ctx_immutable
    state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: {}
    )

    new_state = state.with_ctx(foo: "bar")

    refute_same state, new_state
    assert_equal({}, state.ctx)
    assert_equal({ foo: "bar" }, new_state.ctx)
  end

  def test_state_with_ctx_merges
    state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: {},
      ctx: { existing: "value" }
    )

    new_state = state.with_ctx(new_key: "new_value")

    assert_equal({ existing: "value", new_key: "new_value" }, new_state.ctx)
  end

  def test_step_def_creation
    step = DurableWorkflow::Core::StepDef.new(
      id: "my_step",
      type: "assign",
      config: { assignments: { x: 1 } },
      next_step: "next_one"
    )

    assert_equal "my_step", step.id
    assert_equal "assign", step.type
    assert_equal({ assignments: { x: 1 } }, step.config)
    assert_equal "next_one", step.next_step
  end

  def test_workflow_def_creation
    wf = DurableWorkflow::Core::WorkflowDef.new(
      id: "my_workflow",
      name: "My Workflow",
      version: "1.0",
      steps: []
    )

    assert_equal "my_workflow", wf.id
    assert_equal "My Workflow", wf.name
    assert_equal "1.0", wf.version
    assert_equal [], wf.steps
    assert_equal({}, wf.extensions)
  end

  def test_workflow_def_with_extensions
    wf = DurableWorkflow::Core::WorkflowDef.new(
      id: "my_workflow",
      name: "My Workflow",
      version: "1.0",
      steps: [],
      extensions: { ai: { agents: {} } }
    )

    assert_equal({ ai: { agents: {} } }, wf.extensions)
  end

  def test_step_result_creation
    result = DurableWorkflow::Core::StepResult.new(output: { value: 42 })

    assert_equal({ value: 42 }, result.output)
    refute result.halted?
  end

  def test_halt_result_creation
    halt = DurableWorkflow::Core::HaltResult.new(
      data: { reason: "waiting" },
      prompt: "Please provide input"
    )

    assert_equal({ reason: "waiting" }, halt.data)
    assert_equal "Please provide input", halt.prompt
    assert halt.halted?
  end

  def test_step_outcome_continue
    outcome = DurableWorkflow::Core::StepOutcome.continue(
      state: DurableWorkflow::Core::State.new(
        execution_id: "e1",
        workflow_id: "w1",
        input: {}
      ),
      result: DurableWorkflow::Core::StepResult.new(output: {}),
      next_step: "next"
    )

    assert_equal "next", outcome.next_step
    refute outcome.halted?
    refute outcome.terminal?
  end

  def test_step_outcome_halt
    outcome = DurableWorkflow::Core::StepOutcome.halt(
      state: DurableWorkflow::Core::State.new(
        execution_id: "e1",
        workflow_id: "w1",
        input: {}
      ),
      result: DurableWorkflow::Core::HaltResult.new(data: {})
    )

    assert outcome.halted?
    refute outcome.terminal?
  end

  def test_step_outcome_terminal
    outcome = DurableWorkflow::Core::StepOutcome.terminal(
      state: DurableWorkflow::Core::State.new(
        execution_id: "e1",
        workflow_id: "w1",
        input: {}
      ),
      result: DurableWorkflow::Core::StepResult.new(output: { final: true })
    )

    assert outcome.terminal?
    refute outcome.halted?
    assert_nil outcome.next_step
  end

  def test_execution_result_completed
    result = DurableWorkflow::Core::ExecutionResult.new(
      status: :completed,
      execution_id: "exec-1",
      output: { value: 42 }
    )

    assert result.completed?
    refute result.halted?
    refute result.failed?
    assert_equal({ value: 42 }, result.output)
  end

  def test_execution_result_halted
    result = DurableWorkflow::Core::ExecutionResult.new(
      status: :halted,
      execution_id: "exec-1",
      halt: DurableWorkflow::Core::HaltResult.new(data: { waiting: true })
    )

    assert result.halted?
    refute result.completed?
    assert_equal({ waiting: true }, result.halt.data)
  end

  def test_execution_result_failed
    result = DurableWorkflow::Core::ExecutionResult.new(
      status: :failed,
      execution_id: "exec-1",
      error: "Something went wrong"
    )

    assert result.failed?
    assert_equal "Something went wrong", result.error
  end

  def test_entry_creation
    entry = DurableWorkflow::Core::Entry.new(
      id: "entry-1",
      execution_id: "exec-1",
      step_id: "step-1",
      step_type: "assign",
      action: :execute,
      duration_ms: 100,
      input: { a: 1 },
      output: { b: 2 },
      timestamp: Time.now
    )

    assert_equal "entry-1", entry.id
    assert_equal :execute, entry.action
    assert_equal 100, entry.duration_ms
  end
end
```

### 3. `test/core/state_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class StateTest < DurableWorkflowTest
  def test_state_to_h
    state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: { value: 42 },
      ctx: { result: 84 },
      current_step: "process",
      history: ["start"]
    )

    h = state.to_h

    assert_equal "exec-1", h[:execution_id]
    assert_equal "wf-1", h[:workflow_id]
    assert_equal({ value: 42 }, h[:input])
    assert_equal({ result: 84 }, h[:ctx])
    assert_equal "process", h[:current_step]
    assert_equal ["start"], h[:history]
  end

  def test_state_from_h
    h = {
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: { value: 42 },
      ctx: { result: 84 },
      current_step: "process",
      history: ["start"]
    }

    state = DurableWorkflow::Core::State.from_h(h)

    assert_equal "exec-1", state.execution_id
    assert_equal({ value: 42 }, state.input)
    assert_equal({ result: 84 }, state.ctx)
  end

  def test_state_move_to
    state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: {},
      current_step: "step1"
    )

    new_state = state.move_to("step2")

    refute_same state, new_state
    assert_equal "step1", state.current_step
    assert_equal "step2", new_state.current_step
    assert_includes new_state.history, "step1"
  end

  def test_state_add_history
    state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: {},
      history: ["step1"]
    )

    new_state = state.add_history("step2")

    assert_equal ["step1"], state.history
    assert_equal ["step1", "step2"], new_state.history
  end
end
```

### 4. `test/core/engine_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class EngineTest < DurableWorkflowTest
  def test_run_simple_workflow
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run({ value: 21 })

    assert result.completed?
    assert_equal 42, result.output[:result]
  end

  def test_run_with_execution_id
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run({ value: 10 }, execution_id: "my-exec-id")

    assert_equal "my-exec-id", result.execution_id
    assert result.completed?
  end

  def test_run_generates_execution_id
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run({ value: 10 })

    refute_nil result.execution_id
    assert_match(/\A[0-9a-f-]{36}\z/, result.execution_id)
  end

  def test_run_saves_state
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run({ value: 10 })
    state = @store.load(result.execution_id)

    refute_nil state
    assert_equal 20, state.ctx[:result]
  end

  def test_run_router_path_a
    workflow = DurableWorkflow::Core::Parser.parse(router_workflow_yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run({ path: "a" })

    assert result.completed?
    assert_equal "went_a", result.output[:result]
  end

  def test_run_router_path_b
    workflow = DurableWorkflow::Core::Parser.parse(router_workflow_yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run({ path: "b" })

    assert result.completed?
    assert_equal "went_b", result.output[:result]
  end

  def test_run_router_default
    workflow = DurableWorkflow::Core::Parser.parse(router_workflow_yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run({ path: "unknown" })

    assert result.completed?
    assert_equal "went_default", result.output[:result]
  end

  def test_run_loop
    workflow = DurableWorkflow::Core::Parser.parse(loop_workflow_yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run({ items: [1, 2, 3, 4, 5] })

    assert result.completed?
    assert_equal 5, result.output[:counter]
    assert_equal 15, result.output[:sum]
  end

  def test_run_halt_and_resume
    workflow = DurableWorkflow::Core::Parser.parse(halt_workflow_yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run({})

    assert result.halted?
    assert_equal "Waiting for input", result.halt.data[:message]

    # Resume with response
    result = engine.resume(result.execution_id, response: "user_input")

    assert result.completed?
    assert_equal "user_input", result.output[:result]
  end

  def test_run_approval_approved
    workflow = DurableWorkflow::Core::Parser.parse(approval_workflow_yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run({})

    assert result.halted?
    assert_equal "Do you approve?", result.halt.prompt

    result = engine.resume(result.execution_id, approved: true)

    assert result.completed?
    assert_equal "approved", result.output[:result]
  end

  def test_run_approval_rejected
    workflow = DurableWorkflow::Core::Parser.parse(approval_workflow_yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run({})
    result = engine.resume(result.execution_id, approved: false)

    assert result.completed?
    assert_equal "rejected", result.output[:result]
  end

  def test_run_parallel
    workflow = DurableWorkflow::Core::Parser.parse(parallel_workflow_yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run({})

    assert result.completed?
    assert_equal "from_a", result.output[:a_result]
    assert_equal "from_b", result.output[:b_result]
  end

  def test_run_records_entries
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run({ value: 10 })
    entries = @store.entries(result.execution_id)

    refute_empty entries
    assert entries.any? { _1.step_id == "start" }
    assert entries.any? { _1.step_id == "process" }
    assert entries.any? { _1.step_id == "done" }
  end

  def test_resume_nonexistent_execution_fails
    workflow = DurableWorkflow::Core::Parser.parse(halt_workflow_yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    error = assert_raises(DurableWorkflow::ExecutionError) do
      engine.resume("nonexistent-id")
    end

    assert_match(/not found/i, error.message)
  end
end
```

### 5. `test/core/registry_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class RegistryTest < DurableWorkflowTest
  def test_register_and_get_executor
    registry = DurableWorkflow::Core::Executors::Registry

    # Core executors should be registered
    assert registry.registered?("start")
    assert registry.registered?("end")
    assert registry.registered?("assign")
    assert registry.registered?("call")
    assert registry.registered?("router")
    assert registry.registered?("loop")
    assert registry.registered?("halt")
    assert registry.registered?("approval")
    assert registry.registered?("transform")
    assert registry.registered?("parallel")
    assert registry.registered?("workflow")
  end

  def test_get_executor_class
    registry = DurableWorkflow::Core::Executors::Registry

    klass = registry.get("assign")

    assert_equal DurableWorkflow::Core::Executors::Assign, klass
  end

  def test_unregistered_type_returns_nil
    registry = DurableWorkflow::Core::Executors::Registry

    refute registry.registered?("nonexistent_type")
    assert_nil registry.get("nonexistent_type")
  end

  def test_register_custom_executor
    registry = DurableWorkflow::Core::Executors::Registry

    custom_executor = Class.new(DurableWorkflow::Core::Executors::Base) do
      def call(state)
        continue(state.with_ctx(custom: true))
      end
    end

    registry.register("custom", custom_executor)

    assert registry.registered?("custom")
    assert_equal custom_executor, registry.get("custom")
  ensure
    # Clean up
    registry.instance_variable_get(:@executors).delete("custom")
  end

  def test_types_returns_all_registered
    registry = DurableWorkflow::Core::Executors::Registry

    types = registry.types

    assert_includes types, "start"
    assert_includes types, "end"
    assert_includes types, "assign"
  end
end
```

### 6. `test/core/resolver_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class ResolverTest < DurableWorkflowTest
  def setup
    super
    @state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: { name: "Alice", value: 42, nested: { deep: "data" } },
      ctx: { counter: 10, items: [1, 2, 3] }
    )
    @resolver = DurableWorkflow::Core::Resolver.new(@state)
  end

  def test_resolve_input_value
    result = @resolver.resolve("$.input.name")

    assert_equal "Alice", result
  end

  def test_resolve_ctx_value
    result = @resolver.resolve("$.ctx.counter")

    assert_equal 10, result
  end

  def test_resolve_nested_input
    result = @resolver.resolve("$.input.nested.deep")

    assert_equal "data", result
  end

  def test_resolve_array_access
    result = @resolver.resolve("$.ctx.items[1]")

    assert_equal 2, result
  end

  def test_resolve_expression
    result = @resolver.resolve("$.input.value * 2")

    assert_equal 84, result
  end

  def test_resolve_string_concatenation
    result = @resolver.resolve("'Hello, ' + $.input.name")

    assert_equal "Hello, Alice", result
  end

  def test_resolve_comparison
    result = @resolver.resolve("$.input.value > 40")

    assert_equal true, result
  end

  def test_resolve_static_string
    result = @resolver.resolve("'static value'")

    assert_equal "static value", result
  end

  def test_resolve_static_number
    result = @resolver.resolve("123")

    assert_equal 123, result
  end

  def test_resolve_hash
    hash = { key: "$.input.name", static: "value" }
    result = @resolver.resolve(hash)

    assert_equal({ key: "Alice", static: "value" }, result)
  end

  def test_resolve_array
    arr = ["$.input.name", "$.ctx.counter"]
    result = @resolver.resolve(arr)

    assert_equal ["Alice", 10], result
  end

  def test_resolve_missing_path_returns_nil
    result = @resolver.resolve("$.input.nonexistent")

    assert_nil result
  end
end
```

### 7. `test/core/condition_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class ConditionTest < DurableWorkflowTest
  def setup
    super
    @state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: { status: "active", count: 5 },
      ctx: { approved: true, items: [1, 2, 3] }
    )
  end

  def test_evaluate_equality
    result = DurableWorkflow::Core::Condition.evaluate(
      "$.input.status == 'active'",
      @state
    )

    assert result
  end

  def test_evaluate_inequality
    result = DurableWorkflow::Core::Condition.evaluate(
      "$.input.status != 'inactive'",
      @state
    )

    assert result
  end

  def test_evaluate_greater_than
    result = DurableWorkflow::Core::Condition.evaluate(
      "$.input.count > 3",
      @state
    )

    assert result
  end

  def test_evaluate_less_than
    result = DurableWorkflow::Core::Condition.evaluate(
      "$.input.count < 10",
      @state
    )

    assert result
  end

  def test_evaluate_boolean_ctx
    result = DurableWorkflow::Core::Condition.evaluate(
      "$.ctx.approved",
      @state
    )

    assert result
  end

  def test_evaluate_and
    result = DurableWorkflow::Core::Condition.evaluate(
      "$.ctx.approved && $.input.count > 0",
      @state
    )

    assert result
  end

  def test_evaluate_or
    result = DurableWorkflow::Core::Condition.evaluate(
      "$.input.status == 'inactive' || $.ctx.approved",
      @state
    )

    assert result
  end

  def test_evaluate_not
    result = DurableWorkflow::Core::Condition.evaluate(
      "!$.ctx.approved",
      @state
    )

    refute result
  end

  def test_evaluate_array_includes
    result = DurableWorkflow::Core::Condition.evaluate(
      "$.ctx.items.includes(2)",
      @state
    )

    assert result
  end

  def test_evaluate_array_length
    result = DurableWorkflow::Core::Condition.evaluate(
      "$.ctx.items.length == 3",
      @state
    )

    assert result
  end

  def test_evaluate_false_condition
    result = DurableWorkflow::Core::Condition.evaluate(
      "$.input.count > 100",
      @state
    )

    refute result
  end
end
```

### 8. `test/core/validator_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class ValidatorTest < DurableWorkflowTest
  def test_valid_workflow_passes
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    validator = DurableWorkflow::Core::Validator.new(workflow)

    result = validator.validate

    assert result.valid?
    assert_empty result.errors
  end

  def test_missing_start_step_fails
    yaml = <<~YAML
      id: no_start
      name: No Start
      version: "1.0"
      steps:
        - id: process
          type: assign
          config:
            assignments:
              x: 1
          next: done
        - id: done
          type: end
    YAML

    workflow = DurableWorkflow::Core::Parser.parse(yaml)
    validator = DurableWorkflow::Core::Validator.new(workflow)

    result = validator.validate

    refute result.valid?
    assert result.errors.any? { _1.include?("start") }
  end

  def test_missing_end_step_fails
    yaml = <<~YAML
      id: no_end
      name: No End
      version: "1.0"
      steps:
        - id: start
          type: start
          next: process
        - id: process
          type: assign
          config:
            assignments:
              x: 1
    YAML

    workflow = DurableWorkflow::Core::Parser.parse(yaml)
    validator = DurableWorkflow::Core::Validator.new(workflow)

    result = validator.validate

    refute result.valid?
    assert result.errors.any? { _1.include?("end") }
  end

  def test_unreachable_step_warning
    yaml = <<~YAML
      id: unreachable
      name: Unreachable
      version: "1.0"
      steps:
        - id: start
          type: start
          next: done
        - id: orphan
          type: assign
          config:
            assignments:
              x: 1
          next: done
        - id: done
          type: end
    YAML

    workflow = DurableWorkflow::Core::Parser.parse(yaml)
    validator = DurableWorkflow::Core::Validator.new(workflow)

    result = validator.validate

    assert result.valid? # Warnings don't fail validation
    assert result.warnings.any? { _1.include?("orphan") }
  end

  def test_invalid_next_step_fails
    yaml = <<~YAML
      id: bad_next
      name: Bad Next
      version: "1.0"
      steps:
        - id: start
          type: start
          next: nonexistent
        - id: done
          type: end
    YAML

    workflow = DurableWorkflow::Core::Parser.parse(yaml)
    validator = DurableWorkflow::Core::Validator.new(workflow)

    result = validator.validate

    refute result.valid?
    assert result.errors.any? { _1.include?("nonexistent") }
  end

  def test_unknown_step_type_fails
    yaml = <<~YAML
      id: unknown_type
      name: Unknown Type
      version: "1.0"
      steps:
        - id: start
          type: start
          next: bad
        - id: bad
          type: nonexistent_type
          next: done
        - id: done
          type: end
    YAML

    workflow = DurableWorkflow::Core::Parser.parse(yaml)
    validator = DurableWorkflow::Core::Validator.new(workflow)

    result = validator.validate

    refute result.valid?
    assert result.errors.any? { _1.include?("nonexistent_type") }
  end

  def test_duplicate_step_ids_fail
    yaml = <<~YAML
      id: duplicate_ids
      name: Duplicate IDs
      version: "1.0"
      steps:
        - id: start
          type: start
          next: process
        - id: process
          type: assign
          config:
            assignments:
              x: 1
          next: process
        - id: process
          type: assign
          config:
            assignments:
              y: 2
          next: done
        - id: done
          type: end
    YAML

    workflow = DurableWorkflow::Core::Parser.parse(yaml)
    validator = DurableWorkflow::Core::Validator.new(workflow)

    result = validator.validate

    refute result.valid?
    assert result.errors.any? { _1.include?("duplicate") || _1.include?("process") }
  end

  def test_validate_bang_raises_on_invalid
    yaml = <<~YAML
      id: invalid
      name: Invalid
      version: "1.0"
      steps:
        - id: start
          type: start
          next: nowhere
    YAML

    workflow = DurableWorkflow::Core::Parser.parse(yaml)
    validator = DurableWorkflow::Core::Validator.new(workflow)

    assert_raises(DurableWorkflow::ValidationError) do
      validator.validate!
    end
  end
end
```

### 9. `test/core/executors/assign_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class AssignExecutorTest < DurableWorkflowTest
  def setup
    super
    @step = DurableWorkflow::Core::StepDef.new(
      id: "assign_step",
      type: "assign",
      config: {},
      next_step: "next"
    )
    @state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: { value: 10 },
      ctx: { existing: "keep" }
    )
  end

  def test_assign_static_value
    @step = @step.with(config: { assignments: { result: "'static'" } })
    executor = DurableWorkflow::Core::Executors::Assign.new(@step, nil)

    outcome = executor.call(@state)

    assert_equal "static", outcome.state.ctx[:result]
    assert_equal "keep", outcome.state.ctx[:existing]
    assert_equal "next", outcome.next_step
  end

  def test_assign_from_input
    @step = @step.with(config: { assignments: { doubled: "$.input.value * 2" } })
    executor = DurableWorkflow::Core::Executors::Assign.new(@step, nil)

    outcome = executor.call(@state)

    assert_equal 20, outcome.state.ctx[:doubled]
  end

  def test_assign_multiple_values
    @step = @step.with(config: {
      assignments: {
        a: "$.input.value",
        b: "$.input.value + 5",
        c: "'constant'"
      }
    })
    executor = DurableWorkflow::Core::Executors::Assign.new(@step, nil)

    outcome = executor.call(@state)

    assert_equal 10, outcome.state.ctx[:a]
    assert_equal 15, outcome.state.ctx[:b]
    assert_equal "constant", outcome.state.ctx[:c]
  end

  def test_assign_from_ctx
    @state = @state.with_ctx(source: 100)
    @step = @step.with(config: { assignments: { target: "$.ctx.source / 2" } })
    executor = DurableWorkflow::Core::Executors::Assign.new(@step, nil)

    outcome = executor.call(@state)

    assert_equal 50, outcome.state.ctx[:target]
  end
end
```

### 10. `test/core/executors/router_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class RouterExecutorTest < DurableWorkflowTest
  def setup
    super
    @step = DurableWorkflow::Core::StepDef.new(
      id: "router_step",
      type: "router",
      config: {
        routes: [
          { condition: "$.input.type == 'a'", next: "path_a" },
          { condition: "$.input.type == 'b'", next: "path_b" }
        ],
        default: "path_default"
      },
      next_step: nil
    )
    @state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: {},
      ctx: {}
    )
  end

  def test_routes_to_first_match
    @state = @state.with(input: { type: "a" })
    executor = DurableWorkflow::Core::Executors::Router.new(@step, nil)

    outcome = executor.call(@state)

    assert_equal "path_a", outcome.next_step
  end

  def test_routes_to_second_match
    @state = @state.with(input: { type: "b" })
    executor = DurableWorkflow::Core::Executors::Router.new(@step, nil)

    outcome = executor.call(@state)

    assert_equal "path_b", outcome.next_step
  end

  def test_routes_to_default
    @state = @state.with(input: { type: "unknown" })
    executor = DurableWorkflow::Core::Executors::Router.new(@step, nil)

    outcome = executor.call(@state)

    assert_equal "path_default", outcome.next_step
  end

  def test_routes_based_on_ctx
    @step = @step.with(config: {
      routes: [
        { condition: "$.ctx.score > 80", next: "high" },
        { condition: "$.ctx.score > 50", next: "medium" }
      ],
      default: "low"
    })
    @state = @state.with_ctx(score: 75)
    executor = DurableWorkflow::Core::Executors::Router.new(@step, nil)

    outcome = executor.call(@state)

    assert_equal "medium", outcome.next_step
  end
end
```

### 11. `test/core/executors/loop_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class LoopExecutorTest < DurableWorkflowTest
  def setup
    super
    @workflow = DurableWorkflow::Core::Parser.parse(loop_workflow_yaml)
  end

  def test_loop_iterates_all_items
    engine = DurableWorkflow::Core::Engine.new(@workflow, store: @store)

    result = engine.run({ items: [10, 20, 30] })

    assert result.completed?
    assert_equal 3, result.output[:counter]
    assert_equal 60, result.output[:sum]
  end

  def test_loop_empty_collection
    engine = DurableWorkflow::Core::Engine.new(@workflow, store: @store)

    result = engine.run({ items: [] })

    assert result.completed?
    assert_equal 0, result.output[:counter]
    assert_equal 0, result.output[:sum]
  end

  def test_loop_single_item
    engine = DurableWorkflow::Core::Engine.new(@workflow, store: @store)

    result = engine.run({ items: [100] })

    assert result.completed?
    assert_equal 1, result.output[:counter]
    assert_equal 100, result.output[:sum]
  end
end
```

### 12. `test/core/executors/halt_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class HaltExecutorTest < DurableWorkflowTest
  def setup
    super
    @step = DurableWorkflow::Core::StepDef.new(
      id: "halt_step",
      type: "halt",
      config: {
        data: { reason: "waiting", message: "Please provide input" }
      },
      next_step: "after_halt"
    )
    @state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: {},
      ctx: { existing: "data" }
    )
  end

  def test_halt_returns_halted_outcome
    executor = DurableWorkflow::Core::Executors::Halt.new(@step, nil)

    outcome = executor.call(@state)

    assert outcome.halted?
    assert_equal({ reason: "waiting", message: "Please provide input" }, outcome.result.data)
  end

  def test_halt_preserves_next_step
    executor = DurableWorkflow::Core::Executors::Halt.new(@step, nil)

    outcome = executor.call(@state)

    assert_equal "after_halt", outcome.next_step
  end

  def test_halt_with_dynamic_data
    @step = @step.with(config: {
      data: {
        value: "$.input.amount",
        status: "$.ctx.status"
      }
    })
    @state = @state.with(input: { amount: 100 }).with_ctx(status: "pending")
    executor = DurableWorkflow::Core::Executors::Halt.new(@step, nil)

    outcome = executor.call(@state)

    assert_equal({ value: 100, status: "pending" }, outcome.result.data)
  end
end
```

### 13. `test/core/executors/call_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class CallExecutorTest < DurableWorkflowTest
  def setup
    super
    # Register a test service
    DurableWorkflow.register_service(:test_service, TestService.new)
  end

  def teardown
    super
    DurableWorkflow.services.delete(:test_service)
  end

  class TestService
    def echo(message:)
      { echoed: message }
    end

    def add(a:, b:)
      { sum: a + b }
    end

    def failing
      raise "Service error"
    end
  end

  def test_call_service_method
    step = DurableWorkflow::Core::StepDef.new(
      id: "call_step",
      type: "call",
      config: {
        service: "test_service",
        method: "echo",
        args: { message: "'Hello'" }
      },
      next_step: "next"
    )
    state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: {},
      ctx: {}
    )
    executor = DurableWorkflow::Core::Executors::Call.new(step, nil)

    outcome = executor.call(state)

    assert_equal({ echoed: "Hello" }, outcome.result.output)
    assert_equal "next", outcome.next_step
  end

  def test_call_with_resolved_args
    step = DurableWorkflow::Core::StepDef.new(
      id: "call_step",
      type: "call",
      config: {
        service: "test_service",
        method: "add",
        args: { a: "$.input.x", b: "$.input.y" }
      },
      next_step: "next"
    )
    state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: { x: 10, y: 20 },
      ctx: {}
    )
    executor = DurableWorkflow::Core::Executors::Call.new(step, nil)

    outcome = executor.call(state)

    assert_equal({ sum: 30 }, outcome.result.output)
  end

  def test_call_stores_result_in_ctx
    step = DurableWorkflow::Core::StepDef.new(
      id: "call_step",
      type: "call",
      config: {
        service: "test_service",
        method: "echo",
        args: { message: "'test'" },
        result_key: "call_result"
      },
      next_step: "next"
    )
    state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: {},
      ctx: {}
    )
    executor = DurableWorkflow::Core::Executors::Call.new(step, nil)

    outcome = executor.call(state)

    assert_equal({ echoed: "test" }, outcome.state.ctx[:call_result])
  end

  def test_call_unregistered_service_fails
    step = DurableWorkflow::Core::StepDef.new(
      id: "call_step",
      type: "call",
      config: {
        service: "nonexistent",
        method: "foo"
      },
      next_step: "next"
    )
    state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: {},
      ctx: {}
    )
    executor = DurableWorkflow::Core::Executors::Call.new(step, nil)

    assert_raises(DurableWorkflow::ExecutionError) do
      executor.call(state)
    end
  end
end
```

### 14. `test/parser_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class ParserTest < DurableWorkflowTest
  def test_parse_simple_workflow
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)

    assert_equal "test_workflow", workflow.id
    assert_equal "Test Workflow", workflow.name
    assert_equal "1.0", workflow.version
    assert_equal 3, workflow.steps.size
  end

  def test_parse_creates_step_defs
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)

    start_step = workflow.steps.find { _1.id == "start" }
    assert_equal "start", start_step.type
    assert_equal "process", start_step.next_step

    process_step = workflow.steps.find { _1.id == "process" }
    assert_equal "assign", process_step.type
    assert_equal({ assignments: { result: "$.input.value * 2" } }, process_step.config)
  end

  def test_parse_with_input_schema
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)

    expected_schema = {
      type: "object",
      properties: { value: { type: "integer" } }
    }
    assert_equal expected_schema, workflow.input_schema
  end

  def test_parse_router_config
    workflow = DurableWorkflow::Core::Parser.parse(router_workflow_yaml)

    route_step = workflow.steps.find { _1.id == "route" }
    assert_equal "router", route_step.type
    assert_equal 2, route_step.config[:routes].size
    assert_equal "path_default", route_step.config[:default]
  end

  def test_parse_loop_config
    workflow = DurableWorkflow::Core::Parser.parse(loop_workflow_yaml)

    loop_step = workflow.steps.find { _1.id == "loop" }
    assert_equal "loop", loop_step.type
    assert_equal "$.input.items", loop_step.config[:collection]
    assert_equal "item", loop_step.config[:item_var]
    refute_empty loop_step.config[:body]
  end

  def test_parse_parallel_config
    workflow = DurableWorkflow::Core::Parser.parse(parallel_workflow_yaml)

    parallel_step = workflow.steps.find { _1.id == "parallel" }
    assert_equal "parallel", parallel_step.type
    assert_equal 2, parallel_step.config[:branches].keys.size
    assert_equal "all", parallel_step.config[:merge_strategy]
  end

  def test_parse_from_file
    # Create temp file
    require "tempfile"
    file = Tempfile.new(["workflow", ".yml"])
    file.write(simple_workflow_yaml)
    file.close

    workflow = DurableWorkflow::Core::Parser.parse_file(file.path)

    assert_equal "test_workflow", workflow.id
  ensure
    file.unlink
  end

  def test_parse_invalid_yaml_raises
    assert_raises(DurableWorkflow::ParseError) do
      DurableWorkflow::Core::Parser.parse("not: valid: yaml: :")
    end
  end

  def test_parse_missing_id_raises
    yaml = <<~YAML
      name: No ID
      version: "1.0"
      steps: []
    YAML

    assert_raises(DurableWorkflow::ParseError) do
      DurableWorkflow::Core::Parser.parse(yaml)
    end
  end

  def test_before_parse_hook
    hook_called = false
    DurableWorkflow::Core::Parser.before_parse do |yaml|
      hook_called = true
      yaml
    end

    DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)

    assert hook_called
  ensure
    DurableWorkflow::Core::Parser.instance_variable_get(:@before_hooks).clear
  end

  def test_after_parse_hook
    DurableWorkflow::Core::Parser.after_parse do |workflow|
      workflow.with(extensions: workflow.extensions.merge(test: { added: true }))
    end

    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)

    assert_equal({ added: true }, workflow.extensions[:test])
  ensure
    DurableWorkflow::Core::Parser.instance_variable_get(:@after_hooks).clear
  end

  def test_config_transformer_hook
    DurableWorkflow::Core::Parser.transform_config("assign") do |config|
      config.merge(transformed: true)
    end

    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    assign_step = workflow.steps.find { _1.type == "assign" }

    assert assign_step.config[:transformed]
  ensure
    DurableWorkflow::Core::Parser.instance_variable_get(:@config_transformers).clear
  end
end
```

### 15. `test/storage/redis_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class RedisStorageTest < DurableWorkflowTest
  def setup
    skip "Redis not available" unless redis_available?

    @redis = ::Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/15"))
    @redis.flushdb
    @store = DurableWorkflow::Storage::Redis.new(redis: @redis)
  end

  def teardown
    @redis&.flushdb
  end

  def test_save_and_load_state
    state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: { value: 42 },
      ctx: { result: 84 },
      current_step: "process"
    )

    @store.save(state)
    loaded = @store.load("exec-1")

    assert_equal "exec-1", loaded.execution_id
    assert_equal "wf-1", loaded.workflow_id
    assert_equal({ value: 42 }, loaded.input)
    assert_equal({ result: 84 }, loaded.ctx)
    assert_equal "process", loaded.current_step
  end

  def test_load_nonexistent_returns_nil
    result = @store.load("nonexistent")

    assert_nil result
  end

  def test_record_and_get_entries
    entry1 = DurableWorkflow::Core::Entry.new(
      id: "entry-1",
      execution_id: "exec-1",
      step_id: "step-1",
      step_type: "assign",
      action: :execute,
      duration_ms: 10,
      timestamp: Time.now
    )
    entry2 = DurableWorkflow::Core::Entry.new(
      id: "entry-2",
      execution_id: "exec-1",
      step_id: "step-2",
      step_type: "call",
      action: :execute,
      duration_ms: 20,
      timestamp: Time.now
    )

    @store.record(entry1)
    @store.record(entry2)
    entries = @store.entries("exec-1")

    assert_equal 2, entries.size
    assert_equal "step-1", entries[0].step_id
    assert_equal "step-2", entries[1].step_id
  end

  def test_find_by_workflow_id
    state1 = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: {}
    )
    state2 = DurableWorkflow::Core::State.new(
      execution_id: "exec-2",
      workflow_id: "wf-1",
      input: {}
    )
    state3 = DurableWorkflow::Core::State.new(
      execution_id: "exec-3",
      workflow_id: "wf-2",
      input: {}
    )

    @store.save(state1)
    @store.save(state2)
    @store.save(state3)

    results = @store.find(workflow_id: "wf-1")

    assert_equal 2, results.size
    assert results.all? { _1.workflow_id == "wf-1" }
  end

  def test_find_by_status
    state1 = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: {},
      ctx: { _status: :completed }
    )
    state2 = DurableWorkflow::Core::State.new(
      execution_id: "exec-2",
      workflow_id: "wf-1",
      input: {},
      ctx: { _status: :halted }
    )

    @store.save(state1)
    @store.save(state2)

    results = @store.find(status: :completed)

    assert_equal 1, results.size
    assert_equal "exec-1", results[0].execution_id
  end

  def test_delete_execution
    state = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: {}
    )
    entry = DurableWorkflow::Core::Entry.new(
      id: "entry-1",
      execution_id: "exec-1",
      step_id: "step-1",
      step_type: "assign",
      action: :execute,
      timestamp: Time.now
    )

    @store.save(state)
    @store.record(entry)

    result = @store.delete("exec-1")

    assert result
    assert_nil @store.load("exec-1")
    assert_empty @store.entries("exec-1")
  end

  def test_execution_ids
    state1 = DurableWorkflow::Core::State.new(
      execution_id: "exec-1",
      workflow_id: "wf-1",
      input: {}
    )
    state2 = DurableWorkflow::Core::State.new(
      execution_id: "exec-2",
      workflow_id: "wf-1",
      input: {}
    )

    @store.save(state1)
    @store.save(state2)

    ids = @store.execution_ids

    assert_includes ids, "exec-1"
    assert_includes ids, "exec-2"
  end

  private

    def redis_available?
      ::Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/15")).ping
      true
    rescue
      false
    end
end
```

### 16. `test/runners/sync_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class SyncRunnerTest < DurableWorkflowTest
  def test_run_workflow
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    runner = DurableWorkflow::Runners::Sync.new(workflow, store: @store)

    result = runner.run({ value: 21 })

    assert result.completed?
    assert_equal 42, result.output[:result]
  end

  def test_run_with_execution_id
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    runner = DurableWorkflow::Runners::Sync.new(workflow, store: @store)

    result = runner.run({ value: 10 }, execution_id: "my-id")

    assert_equal "my-id", result.execution_id
  end

  def test_run_until_complete_with_halt
    workflow = DurableWorkflow::Core::Parser.parse(halt_workflow_yaml)
    runner = DurableWorkflow::Runners::Sync.new(workflow, store: @store)

    result = runner.run_until_complete({}) do |halt|
      assert_equal "Waiting for input", halt.data[:message]
      "user_response"
    end

    assert result.completed?
    assert_equal "user_response", result.output[:result]
  end

  def test_run_until_complete_without_block_returns_halted
    workflow = DurableWorkflow::Core::Parser.parse(halt_workflow_yaml)
    runner = DurableWorkflow::Runners::Sync.new(workflow, store: @store)

    result = runner.run_until_complete({})

    assert result.halted?
  end

  def test_resume_halted_workflow
    workflow = DurableWorkflow::Core::Parser.parse(halt_workflow_yaml)
    runner = DurableWorkflow::Runners::Sync.new(workflow, store: @store)

    result = runner.run({})
    assert result.halted?

    result = runner.resume(result.execution_id, response: "resumed")

    assert result.completed?
    assert_equal "resumed", result.output[:result]
  end

  def test_resume_approval_approved
    workflow = DurableWorkflow::Core::Parser.parse(approval_workflow_yaml)
    runner = DurableWorkflow::Runners::Sync.new(workflow, store: @store)

    result = runner.run({})
    result = runner.resume(result.execution_id, approved: true)

    assert result.completed?
    assert_equal "approved", result.output[:result]
  end

  def test_resume_approval_rejected
    workflow = DurableWorkflow::Core::Parser.parse(approval_workflow_yaml)
    runner = DurableWorkflow::Runners::Sync.new(workflow, store: @store)

    result = runner.run({})
    result = runner.resume(result.execution_id, approved: false)

    assert result.completed?
    assert_equal "rejected", result.output[:result]
  end
end
```

### 17. `test/runners/stream_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class StreamRunnerTest < DurableWorkflowTest
  def test_emits_workflow_started_event
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)

    events = []
    runner.subscribe { |e| events << e }

    runner.run({ value: 10 })

    assert events.any? { _1.type == "workflow.started" }
  end

  def test_emits_workflow_completed_event
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)

    events = []
    runner.subscribe { |e| events << e }

    runner.run({ value: 10 })

    assert events.any? { _1.type == "workflow.completed" }
  end

  def test_emits_step_events
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)

    events = []
    runner.subscribe { |e| events << e }

    runner.run({ value: 10 })

    step_started = events.select { _1.type == "step.started" }
    step_completed = events.select { _1.type == "step.completed" }

    assert step_started.size >= 3
    assert step_completed.size >= 3
  end

  def test_emits_workflow_halted_event
    workflow = DurableWorkflow::Core::Parser.parse(halt_workflow_yaml)
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)

    events = []
    runner.subscribe { |e| events << e }

    runner.run({})

    halted_event = events.find { _1.type == "workflow.halted" }
    assert halted_event
    assert_equal "Waiting for input", halted_event.data[:halt][:message]
  end

  def test_filter_events
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)

    events = []
    runner.subscribe(events: ["workflow.completed"]) { |e| events << e }

    runner.run({ value: 10 })

    assert_equal 1, events.size
    assert_equal "workflow.completed", events[0].type
  end

  def test_event_to_sse
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)

    event = nil
    runner.subscribe(events: ["workflow.completed"]) { |e| event = e }

    runner.run({ value: 10 })

    sse = event.to_sse

    assert_match(/event: workflow\.completed/, sse)
    assert_match(/data: \{/, sse)
  end

  def test_multiple_subscribers
    workflow = DurableWorkflow::Core::Parser.parse(simple_workflow_yaml)
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)

    events1 = []
    events2 = []
    runner.subscribe { |e| events1 << e }
    runner.subscribe { |e| events2 << e }

    runner.run({ value: 10 })

    assert_equal events1.size, events2.size
  end
end
```

### 18. `test/extensions/base_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class ExtensionsBaseTest < DurableWorkflowTest
  def test_extension_name_from_class
    ext = Class.new(DurableWorkflow::Extensions::Base)
    ext.instance_variable_set(:@name, "TestExtension")

    assert_equal "testextension", ext.extension_name
  end

  def test_extension_name_can_be_set
    ext = Class.new(DurableWorkflow::Extensions::Base)
    ext.extension_name = "custom"

    assert_equal "custom", ext.extension_name
  end

  def test_data_from_workflow
    ext = Class.new(DurableWorkflow::Extensions::Base)
    ext.extension_name = "test"

    workflow = DurableWorkflow::Core::WorkflowDef.new(
      id: "wf",
      name: "WF",
      version: "1.0",
      steps: [],
      extensions: { test: { foo: "bar" } }
    )

    data = ext.data_from(workflow)

    assert_equal({ foo: "bar" }, data)
  end

  def test_store_in_workflow
    ext = Class.new(DurableWorkflow::Extensions::Base)
    ext.extension_name = "test"

    workflow = DurableWorkflow::Core::WorkflowDef.new(
      id: "wf",
      name: "WF",
      version: "1.0",
      steps: [],
      extensions: {}
    )

    new_workflow = ext.store_in(workflow, { added: true })

    assert_equal({}, workflow.extensions)
    assert_equal({ test: { added: true } }, new_workflow.extensions)
  end

  def test_register_extension
    ext = Class.new(DurableWorkflow::Extensions::Base) do
      self.extension_name = "test_ext"

      def self.register_configs; end
      def self.register_executors; end
      def self.register_parser_hooks; end
    end

    DurableWorkflow::Extensions.register(:test_ext, ext)

    assert DurableWorkflow::Extensions.loaded?(:test_ext)
    assert_equal ext, DurableWorkflow::Extensions[:test_ext]
  ensure
    DurableWorkflow::Extensions.extensions.delete(:test_ext)
  end
end
```

### 19. `Rakefile` (test task)

```ruby
# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

task default: :test
```

## Running Tests

```bash
# Run all tests
bundle exec rake test

# Run specific test file
bundle exec ruby -Ilib:test test/core/engine_test.rb

# Run with verbose output
bundle exec rake test TESTOPTS="--verbose"

# Run specific test method
bundle exec ruby -Ilib:test test/core/engine_test.rb -n test_run_simple_workflow
```

## Acceptance Criteria

1. All core types have full test coverage
2. Engine tests cover run, resume, halt, approval flows
3. Each executor has dedicated tests
4. Parser tests cover YAML parsing and hooks
5. Storage tests verify save/load/find/delete
6. Runner tests cover sync, async, and stream modes
7. Extension tests verify registration and hooks
8. All tests use Minitest (not RSpec)
9. Test helper provides Memory store for isolated tests
