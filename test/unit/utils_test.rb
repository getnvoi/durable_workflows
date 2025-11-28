# frozen_string_literal: true

require "test_helper"

class UtilsTest < Minitest::Test
  def test_deep_symbolize_converts_string_keys
    input = { "foo" => "bar", "nested" => { "baz" => 1 } }
    result = DurableWorkflow::Utils.deep_symbolize(input)

    assert_equal({ foo: "bar", nested: { baz: 1 } }, result)
  end

  def test_deep_symbolize_handles_arrays
    input = [{ "a" => 1 }, { "b" => 2 }]
    result = DurableWorkflow::Utils.deep_symbolize(input)

    assert_equal([{ a: 1 }, { b: 2 }], result)
  end

  def test_deep_symbolize_handles_nested_arrays_in_hashes
    input = { "items" => [{ "name" => "x" }] }
    result = DurableWorkflow::Utils.deep_symbolize(input)

    assert_equal({ items: [{ name: "x" }] }, result)
  end

  def test_deep_symbolize_returns_non_hash_values_unchanged
    assert_equal("string", DurableWorkflow::Utils.deep_symbolize("string"))
    assert_equal(42, DurableWorkflow::Utils.deep_symbolize(42))
    assert_nil(DurableWorkflow::Utils.deep_symbolize(nil))
  end
end
