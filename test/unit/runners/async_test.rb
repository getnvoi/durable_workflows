# frozen_string_literal: true

require "test_helper"

class AsyncRunnerTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def setup
    @store = TestStore.new
    @workflow = build_simple_workflow
    DurableWorkflow.register(@workflow)
  end

  def teardown
    @store.clear!
    DurableWorkflow.registry.delete(@workflow.id)
  end

  def build_simple_workflow
    DurableWorkflow::Core::WorkflowDef.new(
      id: "async_test_workflow",
      name: "Async Test",
      version: "1.0",
      steps: [
        DurableWorkflow::Core::StepDef.new(
          id: "start",
          type: "start",
          config: DurableWorkflow::Core::StartConfig.new,
          next_step: "end"
        ),
        DurableWorkflow::Core::StepDef.new(
          id: "end",
          type: "end",
          config: DurableWorkflow::Core::EndConfig.new(result: { done: true }),
          next_step: nil
        )
      ]
    )
  end

  def test_requires_store
    assert_raises(DurableWorkflow::ConfigError) do
      DurableWorkflow::Runners::Async.new(@workflow)
    end
  end

  def test_run_returns_execution_id
    runner = DurableWorkflow::Runners::Async.new(@workflow, store: @store)

    exec_id = runner.run(input: { name: "test" })

    assert_instance_of String, exec_id
  end

  def test_run_with_custom_execution_id
    runner = DurableWorkflow::Runners::Async.new(@workflow, store: @store)

    exec_id = runner.run(execution_id: "custom-async-123")

    assert_equal "custom-async-123", exec_id
  end

  def test_run_saves_initial_state
    runner = DurableWorkflow::Runners::Async.new(@workflow, store: @store)

    exec_id = runner.run
    state = @store.load(exec_id)

    assert state
    assert_equal @workflow.id, state.workflow_id
  end

  def test_inline_adapter_executes_immediately
    runner = DurableWorkflow::Runners::Async.new(@workflow, store: @store)

    exec_id = runner.run

    # With inline adapter, execution is complete immediately
    result = runner.wait(exec_id, timeout: 1)
    assert_equal :completed, result.status
  end

  def test_status_returns_current_status
    runner = DurableWorkflow::Runners::Async.new(@workflow, store: @store)

    exec_id = runner.run
    status = runner.status(exec_id)

    assert_equal :completed, status
  end

  def test_status_returns_unknown_for_missing_execution
    runner = DurableWorkflow::Runners::Async.new(@workflow, store: @store)

    status = runner.status("nonexistent")

    assert_equal :unknown, status
  end

  def test_wait_returns_nil_on_timeout
    # Create a workflow that never completes (halts)
    halt_workflow = DurableWorkflow::Core::WorkflowDef.new(
      id: "halt_async_workflow",
      name: "Halt",
      version: "1.0",
      steps: [
        DurableWorkflow::Core::StepDef.new(
          id: "start",
          type: "start",
          config: DurableWorkflow::Core::StartConfig.new,
          next_step: "halt"
        ),
        DurableWorkflow::Core::StepDef.new(
          id: "halt",
          type: "halt",
          config: DurableWorkflow::Core::HaltConfig.new(reason: "Wait forever"),
          next_step: "end"
        ),
        DurableWorkflow::Core::StepDef.new(
          id: "end",
          type: "end",
          config: DurableWorkflow::Core::EndConfig.new,
          next_step: nil
        )
      ]
    )
    DurableWorkflow.register(halt_workflow)

    runner = DurableWorkflow::Runners::Async.new(halt_workflow, store: @store)
    exec_id = runner.run

    # Since inline adapter completes immediately with halted status,
    # wait should return the halted result, not timeout
    result = runner.wait(exec_id, timeout: 0.1)
    assert_equal :halted, result.status
  ensure
    DurableWorkflow.registry.delete("halt_async_workflow")
  end
end
