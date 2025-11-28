# frozen_string_literal: true

require "test_helper"

class AssignExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def build_assign_step(set:, next_step: "next")
    DurableWorkflow::Core::StepDef.new(
      id: "assign_step",
      type: "assign",
      config: DurableWorkflow::Core::AssignConfig.new(set: set),
      next_step: next_step
    )
  end

  def test_assign_sets_static_values
    step = build_assign_step(set: { counter: 0, name: "test" })
    executor = DurableWorkflow::Core::Executors::Assign.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal 0, outcome.state.ctx[:counter]
    assert_equal "test", outcome.state.ctx[:name]
  end

  def test_assign_resolves_references
    step = build_assign_step(set: { doubled: "$value" })
    executor = DurableWorkflow::Core::Executors::Assign.new(step)
    state = build_state(ctx: { value: 21 })

    outcome = executor.call(state)

    assert_equal 21, outcome.state.ctx[:doubled]
  end

  def test_assign_continues_to_next_step
    step = build_assign_step(set: { x: 1 }, next_step: "process")
    executor = DurableWorkflow::Core::Executors::Assign.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal "process", outcome.result.next_step
  end

  def test_assign_multiple_values_sequentially
    step = build_assign_step(set: { a: 1, b: "$a" })
    executor = DurableWorkflow::Core::Executors::Assign.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal 1, outcome.state.ctx[:a]
    # b should get the value of a as it was set in the same assign
    assert_equal 1, outcome.state.ctx[:b]
  end

  def test_assign_preserves_existing_ctx
    step = build_assign_step(set: { new_key: "new_value" })
    executor = DurableWorkflow::Core::Executors::Assign.new(step)
    state = build_state(ctx: { existing: "value" })

    outcome = executor.call(state)

    assert_equal "value", outcome.state.ctx[:existing]
    assert_equal "new_value", outcome.state.ctx[:new_key]
  end
end
