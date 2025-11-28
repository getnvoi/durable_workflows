# frozen_string_literal: true

require "test_helper"
require "durable_workflow/extensions/ai"

class MCPClientTest < Minitest::Test
  AI = DurableWorkflow::Extensions::AI

  def setup
    AI::MCP::Client.reset!
  end

  def teardown
    AI::MCP::Client.reset!
  end

  def test_for_caches_connections_by_url
    config = AI::MCPServerConfig.new(url: "https://example.com/mcp")

    mock_client = Object.new
    ::MCP::Client.stub :new, mock_client do
      ::MCP::Client::HTTP.stub :new, Object.new do
        client1 = AI::MCP::Client.for(config)
        client2 = AI::MCP::Client.for(config)

        assert_same client1, client2
      end
    end
  end

  def test_for_creates_http_transport_by_default
    config = AI::MCPServerConfig.new(url: "https://example.com/mcp")
    transport_created = nil

    ::MCP::Client::HTTP.stub :new, ->(url:, headers:) {
      transport_created = { url: url, headers: headers }
      Object.new
    } do
      ::MCP::Client.stub :new, Object.new do
        AI::MCP::Client.for(config)
      end
    end

    assert_equal "https://example.com/mcp", transport_created[:url]
  end

  def test_for_raises_for_stdio_transport
    config = AI::MCPServerConfig.new(
      transport: :stdio,
      command: ["python", "server.py"]
    )

    assert_raises(NotImplementedError) do
      AI::MCP::Client.for(config)
    end
  end

  def test_interpolate_env_replaces_variables
    ENV["TEST_MCP_SECRET"] = "my_secret_value"

    config = AI::MCPServerConfig.new(
      url: "https://example.com",
      headers: { "Authorization" => "Bearer ${TEST_MCP_SECRET}" }
    )

    # Access private method for testing
    result = AI::MCP::Client.send(:interpolate_env, config.headers)

    assert_equal "Bearer my_secret_value", result["Authorization"]
  ensure
    ENV.delete("TEST_MCP_SECRET")
  end

  def test_call_tool_raises_for_unknown_tool
    config = AI::MCPServerConfig.new(url: "https://example.com")

    mock_tool = ::MCP::Client::Tool.new(name: "known_tool", description: "A tool", input_schema: {})
    mock_client = Object.new
    mock_client.define_singleton_method(:tools) { [mock_tool] }

    AI::MCP::Client.stub :for, mock_client do
      error = assert_raises(DurableWorkflow::ExecutionError) do
        AI::MCP::Client.call_tool(config, "unknown_tool", {})
      end

      assert_match(/MCP tool not found/, error.message)
    end
  end

  def test_reset_clears_connection_cache
    config = AI::MCPServerConfig.new(url: "https://example.com")

    call_count = 0
    ::MCP::Client.stub :new, ->(*) { call_count += 1; Object.new } do
      ::MCP::Client::HTTP.stub :new, Object.new do
        AI::MCP::Client.for(config)
        AI::MCP::Client.reset!

        # After reset, should create new client
        AI::MCP::Client.for(config)
        assert_equal 2, call_count
      end
    end
  end

  def test_tools_returns_tools_from_client
    config = AI::MCPServerConfig.new(url: "https://example.com")

    mock_tools = [
      ::MCP::Client::Tool.new(name: "tool1", description: "Tool 1", input_schema: {}),
      ::MCP::Client::Tool.new(name: "tool2", description: "Tool 2", input_schema: {})
    ]
    mock_client = Object.new
    mock_client.define_singleton_method(:tools) { mock_tools }

    AI::MCP::Client.stub :for, mock_client do
      tools = AI::MCP::Client.tools(config)

      assert_equal 2, tools.size
      assert_equal "tool1", tools[0].name
    end
  end
end
