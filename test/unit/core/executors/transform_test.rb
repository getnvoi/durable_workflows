# frozen_string_literal: true

require "test_helper"

class TransformExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def build_transform_step(input: nil, expression:, output: "result")
    config = { expression: expression, output: output }
    config[:input] = input if input

    DurableWorkflow::Core::StepDef.new(
      id: "transform_step",
      type: "transform",
      config: DurableWorkflow::Core::TransformConfig.new(config),
      next_step: "next"
    )
  end

  # Array operations

  def test_map_operation
    step = build_transform_step(
      input: "items",
      expression: { map: "value" }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { items: [{ value: 1 }, { value: 2 }] })

    outcome = executor.call(state)

    assert_equal [1, 2], outcome.state.ctx[:result]
  end

  def test_select_operation
    step = build_transform_step(
      input: "items",
      expression: { select: { active: true } }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: {
      items: [
        { name: "a", active: true },
        { name: "b", active: false },
        { name: "c", active: true }
      ]
    })

    outcome = executor.call(state)

    assert_equal 2, outcome.state.ctx[:result].size
    assert outcome.state.ctx[:result].all? { |i| i[:active] }
  end

  def test_reject_operation
    step = build_transform_step(
      input: "items",
      expression: { reject: { deleted: true } }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: {
      items: [
        { name: "a", deleted: false },
        { name: "b", deleted: true }
      ]
    })

    outcome = executor.call(state)

    assert_equal 1, outcome.state.ctx[:result].size
  end

  def test_pluck_operation
    step = build_transform_step(
      input: "users",
      expression: { pluck: "email" }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: {
      users: [{ email: "a@test.com" }, { email: "b@test.com" }]
    })

    outcome = executor.call(state)

    assert_equal ["a@test.com", "b@test.com"], outcome.state.ctx[:result]
  end

  def test_first_operation
    step = build_transform_step(
      input: "items",
      expression: { first: 2 }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { items: [1, 2, 3, 4, 5] })

    outcome = executor.call(state)

    assert_equal [1, 2], outcome.state.ctx[:result]
  end

  def test_last_operation
    step = build_transform_step(
      input: "items",
      expression: { last: 2 }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { items: [1, 2, 3, 4, 5] })

    outcome = executor.call(state)

    assert_equal [4, 5], outcome.state.ctx[:result]
  end

  def test_compact_operation
    step = build_transform_step(
      input: "items",
      expression: { compact: nil }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { items: [1, nil, 2, nil, 3] })

    outcome = executor.call(state)

    assert_equal [1, 2, 3], outcome.state.ctx[:result]
  end

  def test_uniq_operation
    step = build_transform_step(
      input: "items",
      expression: { uniq: nil }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { items: [1, 2, 2, 3, 3, 3] })

    outcome = executor.call(state)

    assert_equal [1, 2, 3], outcome.state.ctx[:result]
  end

  def test_reverse_operation
    step = build_transform_step(
      input: "items",
      expression: { reverse: nil }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { items: [1, 2, 3] })

    outcome = executor.call(state)

    assert_equal [3, 2, 1], outcome.state.ctx[:result]
  end

  def test_count_operation
    step = build_transform_step(
      input: "items",
      expression: { count: nil }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { items: [1, 2, 3, 4, 5] })

    outcome = executor.call(state)

    assert_equal 5, outcome.state.ctx[:result]
  end

  def test_sum_operation
    step = build_transform_step(
      input: "items",
      expression: { sum: nil }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { items: [1, 2, 3, 4] })

    outcome = executor.call(state)

    assert_equal 10.0, outcome.state.ctx[:result]
  end

  # Hash operations

  def test_keys_operation
    step = build_transform_step(
      input: "data",
      expression: { keys: nil }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { data: { a: 1, b: 2, c: 3 } })

    outcome = executor.call(state)

    assert_equal [:a, :b, :c], outcome.state.ctx[:result]
  end

  def test_values_operation
    step = build_transform_step(
      input: "data",
      expression: { values: nil }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { data: { a: 1, b: 2, c: 3 } })

    outcome = executor.call(state)

    assert_equal [1, 2, 3], outcome.state.ctx[:result]
  end

  def test_pick_operation
    step = build_transform_step(
      input: "data",
      expression: { pick: %w[a c] }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { data: { a: 1, b: 2, c: 3 } })

    outcome = executor.call(state)

    assert_equal({ a: 1, c: 3 }, outcome.state.ctx[:result])
  end

  def test_omit_operation
    step = build_transform_step(
      input: "data",
      expression: { omit: ["b"] }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { data: { a: 1, b: 2, c: 3 } })

    outcome = executor.call(state)

    assert_equal({ a: 1, c: 3 }, outcome.state.ctx[:result])
  end

  def test_merge_operation
    step = build_transform_step(
      input: "data",
      expression: { merge: { d: 4 } }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { data: { a: 1, b: 2 } })

    outcome = executor.call(state)

    assert_equal({ a: 1, b: 2, d: 4 }, outcome.state.ctx[:result])
  end

  # Chained operations

  def test_chained_operations
    step = build_transform_step(
      input: "items",
      expression: { compact: nil, uniq: nil, count: nil }
    )
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { items: [1, nil, 2, 2, nil, 3] })

    outcome = executor.call(state)

    assert_equal 3, outcome.state.ctx[:result]
  end

  def test_continues_to_next_step
    step = build_transform_step(input: "items", expression: { count: nil })
    executor = DurableWorkflow::Core::Executors::Transform.new(step)
    state = build_state(ctx: { items: [1, 2, 3] })

    outcome = executor.call(state)

    assert_equal "next", outcome.result.next_step
  end
end
