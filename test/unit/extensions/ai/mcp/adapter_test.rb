# frozen_string_literal: true

require "test_helper"
require "durable_workflow/extensions/ai"

class MCPAdapterTest < Minitest::Test
  AI = DurableWorkflow::Extensions::AI

  def test_format_result_handles_hash
    result = AI::MCP::Adapter.send(:format_result, { key: "value" })

    assert_includes result, "key"
    assert_includes result, "value"
  end

  def test_format_result_handles_string
    result = AI::MCP::Adapter.send(:format_result, "plain string")

    assert_equal "plain string", result
  end

  def test_format_result_handles_array
    result = AI::MCP::Adapter.send(:format_result, [1, 2, 3])

    assert_includes result, "1"
    assert_includes result, "2"
  end

  def test_format_result_handles_nil
    result = AI::MCP::Adapter.send(:format_result, nil)

    assert_equal "", result
  end

  def test_format_result_handles_numeric
    result = AI::MCP::Adapter.send(:format_result, 42)

    assert_equal "42", result
  end
end
