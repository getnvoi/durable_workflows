# frozen_string_literal: true

require "test_helper"

class TypesStateTest < Minitest::Test
  def test_state_can_be_created
    state = DurableWorkflow::Core::State.new(
      execution_id: "exec-123",
      workflow_id: "wf-1"
    )

    assert_equal "exec-123", state.execution_id
    assert_equal "wf-1", state.workflow_id
  end

  def test_state_input_defaults_to_empty_hash
    state = DurableWorkflow::Core::State.new(
      execution_id: "e",
      workflow_id: "w"
    )

    assert_equal({}, state.input)
  end

  def test_state_ctx_defaults_to_empty_hash
    state = DurableWorkflow::Core::State.new(
      execution_id: "e",
      workflow_id: "w"
    )

    assert_equal({}, state.ctx)
  end

  def test_state_history_defaults_to_empty_array
    state = DurableWorkflow::Core::State.new(
      execution_id: "e",
      workflow_id: "w"
    )

    assert_equal [], state.history
  end

  def test_with_returns_new_state_with_updates
    state = DurableWorkflow::Core::State.new(
      execution_id: "e",
      workflow_id: "w"
    )

    new_state = state.with(current_step: "step1")

    refute_same state, new_state
    assert_equal "step1", new_state.current_step
    assert_nil state.current_step
  end

  def test_with_ctx_merges_into_ctx
    state = DurableWorkflow::Core::State.new(
      execution_id: "e",
      workflow_id: "w",
      ctx: { a: 1 }
    )

    new_state = state.with_ctx(b: 2)

    assert_equal({ a: 1, b: 2 }, new_state.ctx)
  end

  def test_with_current_step_updates_current_step
    state = DurableWorkflow::Core::State.new(
      execution_id: "e",
      workflow_id: "w"
    )

    new_state = state.with_current_step("step2")

    assert_equal "step2", new_state.current_step
  end

end

class TypesExecutionTest < Minitest::Test
  def test_execution_can_be_created
    exec = DurableWorkflow::Core::Execution.new(
      id: "exec-1",
      workflow_id: "wf-1",
      status: :running
    )

    assert_equal "exec-1", exec.id
    assert_equal "wf-1", exec.workflow_id
    assert_equal :running, exec.status
  end

  def test_execution_stores_halt_data
    exec = DurableWorkflow::Core::Execution.new(
      id: "e",
      workflow_id: "w",
      status: :halted,
      halt_data: { reason: "waiting" }
    )

    assert_equal({ reason: "waiting" }, exec.halt_data)
  end
end
