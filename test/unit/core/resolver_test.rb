# frozen_string_literal: true

require "test_helper"

class ResolverTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def test_resolve_returns_non_string_unchanged
    state = build_state
    assert_equal 42, DurableWorkflow::Core::Resolver.resolve(state, 42)
    assert_equal [1, 2], DurableWorkflow::Core::Resolver.resolve(state, [1, 2])
  end

  def test_resolve_input_reference
    state = build_state(input: { name: "John" })
    result = DurableWorkflow::Core::Resolver.resolve(state, "$input")
    assert_equal({ name: "John" }, result)
  end

  def test_resolve_input_nested_reference
    state = build_state(input: { user: { name: "John" } })
    result = DurableWorkflow::Core::Resolver.resolve(state, "$input.user.name")
    assert_equal "John", result
  end

  def test_resolve_ctx_var
    state = build_state(ctx: { counter: 5 })
    result = DurableWorkflow::Core::Resolver.resolve(state, "$counter")
    assert_equal 5, result
  end

  def test_resolve_now_returns_time
    state = build_state
    result = DurableWorkflow::Core::Resolver.resolve(state, "$now")
    assert_instance_of Time, result
  end

  def test_resolve_history
    state = DurableWorkflow::Core::State.new(
      execution_id: "e",
      workflow_id: "w",
      history: ["entry1", "entry2"]
    )
    result = DurableWorkflow::Core::Resolver.resolve(state, "$history")
    assert_equal ["entry1", "entry2"], result
  end

  def test_resolve_interpolates_multiple_refs
    state = build_state(ctx: { first: "John", last: "Doe" })
    result = DurableWorkflow::Core::Resolver.resolve(state, "Hello $first $last!")
    assert_equal "Hello John Doe!", result
  end

  def test_resolve_handles_hashes_recursively
    state = build_state(ctx: { name: "test" })
    input = { greeting: "Hello $name", value: 42 }
    result = DurableWorkflow::Core::Resolver.resolve(state, input)
    assert_equal({ greeting: "Hello test", value: 42 }, result)
  end

  def test_resolve_handles_arrays_recursively
    state = build_state(ctx: { x: 1, y: 2 })
    input = ["$x", "$y", 3]
    result = DurableWorkflow::Core::Resolver.resolve(state, input)
    assert_equal [1, 2, 3], result
  end

  def test_resolve_ref_digs_into_nested_hash
    state = build_state(ctx: { data: { nested: { value: "deep" } } })
    result = DurableWorkflow::Core::Resolver.resolve(state, "$data.nested.value")
    assert_equal "deep", result
  end

  def test_resolve_ref_accesses_array_by_index
    state = build_state(ctx: { items: ["a", "b", "c"] })
    result = DurableWorkflow::Core::Resolver.resolve(state, "$items.1")
    assert_equal "b", result
  end
end
