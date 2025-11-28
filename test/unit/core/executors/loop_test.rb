# frozen_string_literal: true

require "test_helper"

class LoopExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def build_loop_step(over: nil, while_cond: nil, do_steps: [], output: "results", max: 100)
    config = { output: output, max: max, do: do_steps }
    config[:over] = over if over
    config[:while] = while_cond if while_cond

    DurableWorkflow::Core::StepDef.new(
      id: "loop_step",
      type: "loop",
      config: DurableWorkflow::Core::LoopConfig.new(config),
      next_step: "after_loop"
    )
  end

  def build_body_step(id: "body", type: "assign", config: {})
    DurableWorkflow::Core::StepDef.new(
      id: id,
      type: type,
      config: DurableWorkflow::Core::AssignConfig.new(config),
      next_step: nil
    )
  end

  def test_foreach_loop_iterates_over_array
    body_step = build_body_step(
      id: "process",
      config: { set: { processed: "$item" } }
    )
    step = build_loop_step(
      over: "$items",
      do_steps: [body_step]
    )
    executor = DurableWorkflow::Core::Executors::Loop.new(step)
    state = build_state(ctx: { items: [1, 2, 3] })

    outcome = executor.call(state)

    assert_equal "after_loop", outcome.result.next_step
    assert_instance_of Array, outcome.state.ctx[:results]
  end

  def test_foreach_loop_raises_when_over_not_array
    step = build_loop_step(over: "$data")
    executor = DurableWorkflow::Core::Executors::Loop.new(step)
    state = build_state(ctx: { data: "not an array" })

    assert_raises(DurableWorkflow::ExecutionError) do
      executor.call(state)
    end
  end

  def test_foreach_loop_raises_when_exceeds_max
    step = build_loop_step(over: "$items", max: 2)
    executor = DurableWorkflow::Core::Executors::Loop.new(step)
    state = build_state(ctx: { items: [1, 2, 3, 4, 5] })

    assert_raises(DurableWorkflow::ExecutionError) do
      executor.call(state)
    end
  end

  def test_while_loop_exits_when_condition_false
    # Test that while loop exits immediately when condition is false
    body_step = build_body_step(config: { set: { x: 1 } })
    while_cond = DurableWorkflow::Core::Condition.new(
      field: "run",
      op: "eq",
      value: true
    )
    step = build_loop_step(while_cond: while_cond, do_steps: [body_step])
    executor = DurableWorkflow::Core::Executors::Loop.new(step)
    # run is false, so condition is not met, loop should exit immediately
    state = build_state(ctx: { run: false })

    outcome = executor.call(state)

    assert_equal "after_loop", outcome.result.next_step
    # Body never ran, so x should not be set
    refute outcome.state.ctx.key?(:x)
  end

  def test_while_loop_cleans_up_iteration_variable
    # Test that when condition is immediately false, iteration vars are cleaned
    body_step = build_body_step(config: { set: { x: "$iteration" } })
    while_cond = DurableWorkflow::Core::Condition.new(
      field: "run",
      op: "eq",
      value: true
    )
    step = build_loop_step(while_cond: while_cond, do_steps: [body_step])
    executor = DurableWorkflow::Core::Executors::Loop.new(step)
    # run is false, so condition won't match
    state = build_state(ctx: { run: false })

    outcome = executor.call(state)

    # iteration should be cleaned up (or never set since loop didn't run)
    refute outcome.state.ctx.key?(:iteration)
  end
end
