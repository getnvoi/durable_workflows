# frozen_string_literal: true

require "test_helper"

class TypesResultsTest < Minitest::Test
  def test_continue_result_can_be_created
    result = DurableWorkflow::Core::ContinueResult.new(
      next_step: "step2",
      output: { value: 42 }
    )

    assert_equal "step2", result.next_step
    assert_equal({ value: 42 }, result.output)
  end

  def test_halt_result_requires_data
    result = DurableWorkflow::Core::HaltResult.new(
      data: { reason: "waiting" }
    )

    assert_equal({ reason: "waiting" }, result.data)
  end

  def test_halt_result_output_returns_data
    result = DurableWorkflow::Core::HaltResult.new(
      data: { reason: "test" }
    )

    assert_equal result.data, result.output
  end

  def test_execution_result_status_enum
    [:completed, :halted, :failed].each do |status|
      result = DurableWorkflow::Core::ExecutionResult.new(
        status: status,
        execution_id: "exec-1"
      )
      assert_equal status, result.status
    end
  end

  def test_execution_result_completed?
    result = DurableWorkflow::Core::ExecutionResult.new(
      status: :completed,
      execution_id: "e"
    )
    assert result.completed?
    refute result.halted?
    refute result.failed?
  end

  def test_execution_result_halted?
    result = DurableWorkflow::Core::ExecutionResult.new(
      status: :halted,
      execution_id: "e"
    )
    refute result.completed?
    assert result.halted?
    refute result.failed?
  end

  def test_execution_result_failed?
    result = DurableWorkflow::Core::ExecutionResult.new(
      status: :failed,
      execution_id: "e"
    )
    refute result.completed?
    refute result.halted?
    assert result.failed?
  end

  def test_step_outcome_contains_state_and_result
    state = DurableWorkflow::Core::State.new(
      execution_id: "e",
      workflow_id: "w"
    )
    result = DurableWorkflow::Core::ContinueResult.new

    outcome = DurableWorkflow::Core::StepOutcome.new(
      state: state,
      result: result
    )

    assert_equal state, outcome.state
    assert_equal result, outcome.result
  end
end
