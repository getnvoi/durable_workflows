# frozen_string_literal: true

require "test_helper"

class EngineTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def setup
    @store = TestStore.new
  end

  def teardown
    @store.clear!
  end

  def build_workflow(id: "test_workflow", steps:, inputs: [], timeout: nil)
    DurableWorkflow::Core::WorkflowDef.new(
      id: id,
      name: "Test Workflow",
      version: "1.0",
      steps: steps,
      inputs: inputs,
      timeout: timeout
    )
  end

  def build_step(id:, type:, config: nil, next_step: nil, on_error: nil)
    config ||= case type
    when "start" then DurableWorkflow::Core::StartConfig.new
    when "end" then DurableWorkflow::Core::EndConfig.new
    when "assign" then DurableWorkflow::Core::AssignConfig.new(set: {})
    else DurableWorkflow::Core::AssignConfig.new(set: {})
    end

    DurableWorkflow::Core::StepDef.new(
      id: id,
      type: type,
      config: config,
      next_step: next_step,
      on_error: on_error
    )
  end

  # Initialization

  def test_engine_requires_store
    workflow = build_workflow(steps: [])

    assert_raises(DurableWorkflow::ConfigError) do
      DurableWorkflow::Core::Engine.new(workflow)
    end
  end

  def test_engine_accepts_explicit_store
    workflow = build_workflow(steps: [])
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    assert_equal @store, engine.store
  end

  # Simple Workflow Execution

  def test_run_simple_workflow
    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "end"),
      build_step(id: "end", type: "end")
    ])

    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)
    result = engine.run

    assert_equal :completed, result.status
    assert result.execution_id
  end

  def test_run_with_input
    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "end"),
      build_step(
        id: "end",
        type: "end",
        config: DurableWorkflow::Core::EndConfig.new(result: "$input")
      )
    ])

    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)
    result = engine.run(input: { name: "test" })

    assert_equal :completed, result.status
    assert_equal({ name: "test" }, result.output)
  end

  def test_run_with_custom_execution_id
    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "end"),
      build_step(id: "end", type: "end")
    ])

    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)
    result = engine.run(execution_id: "custom-123")

    assert_equal "custom-123", result.execution_id
  end

  # Workflow with Assign Steps

  def test_run_workflow_with_assign
    assign_config = DurableWorkflow::Core::AssignConfig.new(set: { counter: 42 })

    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "assign"),
      build_step(id: "assign", type: "assign", config: assign_config, next_step: "end"),
      build_step(
        id: "end",
        type: "end",
        config: DurableWorkflow::Core::EndConfig.new(result: { counter: "$counter" })
      )
    ])

    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)
    result = engine.run

    assert_equal :completed, result.status
    assert_equal({ counter: 42 }, result.output)
  end

  # Halting

  def test_run_workflow_that_halts
    halt_config = DurableWorkflow::Core::HaltConfig.new(reason: "Waiting")

    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "halt"),
      build_step(id: "halt", type: "halt", config: halt_config, next_step: "end"),
      build_step(id: "end", type: "end")
    ])

    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)
    result = engine.run

    assert_equal :halted, result.status
    assert result.halt
    assert_equal "Waiting", result.halt.data[:reason]
  end

  # Resume

  def test_resume_halted_workflow
    halt_config = DurableWorkflow::Core::HaltConfig.new(reason: "Waiting")

    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "halt"),
      build_step(id: "halt", type: "halt", config: halt_config, next_step: "end"),
      build_step(id: "end", type: "end")
    ])

    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    # First run halts
    halted_result = engine.run
    assert_equal :halted, halted_result.status

    # Resume continues
    resumed_result = engine.resume(halted_result.execution_id)
    assert_equal :completed, resumed_result.status
  end

  def test_resume_with_response
    halt_config = DurableWorkflow::Core::HaltConfig.new(reason: "Need input")

    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "halt"),
      build_step(id: "halt", type: "halt", config: halt_config, next_step: "end"),
      build_step(
        id: "end",
        type: "end",
        config: DurableWorkflow::Core::EndConfig.new(result: { response: "$response" })
      )
    ])

    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    halted_result = engine.run
    resumed_result = engine.resume(halted_result.execution_id, response: "user input")

    assert_equal :completed, resumed_result.status
    assert_equal({ response: "user input" }, resumed_result.output)
  end

  def test_resume_raises_for_unknown_execution
    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "end"),
      build_step(id: "end", type: "end")
    ])

    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    assert_raises(DurableWorkflow::ExecutionError) do
      engine.resume("nonexistent-id")
    end
  end

  # Error Handling

  def test_step_with_on_error_continues_to_error_handler
    # Create a step that will fail
    call_config = DurableWorkflow::Core::CallConfig.new(
      service: "NonexistentService",
      method_name: "call",
      output: "result"
    )

    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "risky"),
      DurableWorkflow::Core::StepDef.new(
        id: "risky",
        type: "call",
        config: call_config,
        next_step: "success",
        on_error: "error_handler"
      ),
      build_step(id: "success", type: "end"),
      build_step(
        id: "error_handler",
        type: "end",
        config: DurableWorkflow::Core::EndConfig.new(result: { error: true })
      )
    ])

    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)
    result = engine.run

    assert_equal :completed, result.status
    assert_equal({ error: true }, result.output)
  end

  # State Persistence

  def test_engine_saves_state_after_each_step
    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "assign"),
      build_step(
        id: "assign",
        type: "assign",
        config: DurableWorkflow::Core::AssignConfig.new(set: { x: 1 }),
        next_step: "end"
      ),
      build_step(id: "end", type: "end")
    ])

    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)
    result = engine.run

    saved_state = @store.load(result.execution_id)
    assert saved_state
    assert_equal 1, saved_state.ctx[:x]
  end

  # Entry Recording

  def test_engine_records_entries
    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "end"),
      build_step(id: "end", type: "end")
    ])

    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)
    result = engine.run

    entries = @store.entries(result.execution_id)
    assert_equal 2, entries.size
    assert_equal "start", entries[0].step_id
    assert_equal "end", entries[1].step_id
  end
end
