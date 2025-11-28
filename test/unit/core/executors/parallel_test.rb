# frozen_string_literal: true

require "test_helper"

class ParallelExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def build_parallel_step(branches:, wait: nil, output: "results")
    config = { branches: branches }
    config[:wait] = wait if wait
    config[:output] = output

    DurableWorkflow::Core::StepDef.new(
      id: "parallel_step",
      type: "parallel",
      config: DurableWorkflow::Core::ParallelConfig.new(config),
      next_step: "next"
    )
  end

  def build_branch(id:, type: "assign", set: {})
    DurableWorkflow::Core::StepDef.new(
      id: id,
      type: type,
      config: DurableWorkflow::Core::AssignConfig.new(set: set),
      next_step: nil
    )
  end

  def test_parallel_with_empty_branches_continues
    step = build_parallel_step(branches: [])
    executor = DurableWorkflow::Core::Executors::Parallel.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_instance_of DurableWorkflow::Core::ContinueResult, outcome.result
    assert_equal "next", outcome.result.next_step
  end

  def test_parallel_executes_branches
    branches = [
      build_branch(id: "b1", set: { a: 1 }),
      build_branch(id: "b2", set: { b: 2 })
    ]
    step = build_parallel_step(branches: branches)
    executor = DurableWorkflow::Core::Executors::Parallel.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal 1, outcome.state.ctx[:a]
    assert_equal 2, outcome.state.ctx[:b]
  end

  def test_parallel_stores_results
    branches = [
      build_branch(id: "b1", set: { a: 1 }),
      build_branch(id: "b2", set: { b: 2 })
    ]
    step = build_parallel_step(branches: branches, output: "branch_results")
    executor = DurableWorkflow::Core::Executors::Parallel.new(step)
    state = build_state

    outcome = executor.call(state)

    assert outcome.state.ctx.key?(:branch_results)
    assert_instance_of Array, outcome.state.ctx[:branch_results]
  end

  def test_parallel_with_wait_any
    branches = [
      build_branch(id: "b1", set: { fast: true }),
      build_branch(id: "b2", set: { slow: true })
    ]
    step = build_parallel_step(branches: branches, wait: "any")
    executor = DurableWorkflow::Core::Executors::Parallel.new(step)
    state = build_state

    outcome = executor.call(state)

    # At least one should complete
    assert_instance_of DurableWorkflow::Core::ContinueResult, outcome.result
  end

  def test_parallel_with_wait_all
    branches = [
      build_branch(id: "b1", set: { x: 1 }),
      build_branch(id: "b2", set: { y: 2 }),
      build_branch(id: "b3", set: { z: 3 })
    ]
    step = build_parallel_step(branches: branches, wait: "all")
    executor = DurableWorkflow::Core::Executors::Parallel.new(step)
    state = build_state

    outcome = executor.call(state)

    # All branches should complete
    assert_equal 1, outcome.state.ctx[:x]
    assert_equal 2, outcome.state.ctx[:y]
    assert_equal 3, outcome.state.ctx[:z]
  end

  def test_parallel_with_wait_count
    branches = [
      build_branch(id: "b1", set: { a: 1 }),
      build_branch(id: "b2", set: { b: 2 }),
      build_branch(id: "b3", set: { c: 3 })
    ]
    step = build_parallel_step(branches: branches, wait: 2)
    executor = DurableWorkflow::Core::Executors::Parallel.new(step)
    state = build_state

    outcome = executor.call(state)

    # At least 2 should complete
    assert_instance_of DurableWorkflow::Core::ContinueResult, outcome.result
  end
end
