# 01-TEST-GAPS: Missing Test Coverage

## Goal

Identify and fill gaps in existing test coverage. Most tests already exist - this focuses on what's missing.

## Current State

- 423 tests passing
- Core types, executors, engine, parser well covered
- Storage adapters have basic coverage

## Missing Tests

### 1. MCP Components (NEW from Phase 4)

```
test/unit/extensions/ai/mcp/
  client_test.rb
  adapter_test.rb
  server_test.rb
  rack_app_test.rb
```

#### `test/unit/extensions/ai/mcp/client_test.rb`

```ruby
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

    # Stub the actual MCP client creation
    mock_client = Object.new
    ::MCP::Client.stub :new, mock_client do
      ::MCP::Transports::HTTP.stub :new, Object.new do
        client1 = AI::MCP::Client.for(config)
        client2 = AI::MCP::Client.for(config)

        assert_same client1, client2
      end
    end
  end

  def test_for_creates_http_transport_by_default
    config = AI::MCPServerConfig.new(url: "https://example.com/mcp")
    transport_created = nil

    ::MCP::Transports::HTTP.stub :new, ->(url:, headers:) {
      transport_created = { url: url, headers: headers }
      Object.new
    } do
      ::MCP::Client.stub :new, Object.new do
        AI::MCP::Client.for(config)
      end
    end

    assert_equal "https://example.com/mcp", transport_created[:url]
  end

  def test_for_creates_stdio_transport_when_specified
    config = AI::MCPServerConfig.new(
      transport: :stdio,
      command: ["python", "server.py"]
    )
    transport_created = nil

    ::MCP::Transports::Stdio.stub :new, ->(command:) {
      transport_created = { command: command }
      Object.new
    } do
      ::MCP::Client.stub :new, Object.new do
        AI::MCP::Client.for(config)
      end
    end

    assert_equal ["python", "server.py"], transport_created[:command]
  end

  def test_interpolate_env_replaces_variables
    ENV["TEST_SECRET"] = "my_secret_value"

    config = AI::MCPServerConfig.new(
      url: "https://example.com",
      headers: { "Authorization" => "Bearer ${TEST_SECRET}" }
    )

    # Access private method for testing
    result = AI::MCP::Client.send(:interpolate_env, config.headers)

    assert_equal "Bearer my_secret_value", result["Authorization"]
  ensure
    ENV.delete("TEST_SECRET")
  end

  def test_call_tool_raises_for_unknown_tool
    config = AI::MCPServerConfig.new(url: "https://example.com")

    mock_client = Minitest::Mock.new
    mock_client.expect :tools, []

    AI::MCP::Client.stub :for, mock_client do
      error = assert_raises(DurableWorkflow::ExecutionError) do
        AI::MCP::Client.call_tool(config, "unknown_tool", {})
      end

      assert_match(/MCP tool not found/, error.message)
    end
  end

  def test_reset_clears_connection_cache
    config = AI::MCPServerConfig.new(url: "https://example.com")

    ::MCP::Client.stub :new, Object.new do
      ::MCP::Transports::HTTP.stub :new, Object.new do
        AI::MCP::Client.for(config)
        AI::MCP::Client.reset!

        # After reset, should create new client
        client = AI::MCP::Client.for(config)
        refute_nil client
      end
    end
  end
end
```

#### `test/unit/extensions/ai/mcp/adapter_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"
require "durable_workflow/extensions/ai"

class MCPAdapterTest < Minitest::Test
  AI = DurableWorkflow::Extensions::AI

  def test_to_mcp_tool_creates_mcp_tool
    # Create a simple RubyLLM::Tool subclass
    tool_class = Class.new(RubyLLM::Tool) do
      description "Test tool description"
      param :input, type: :string, desc: "Input parameter"

      def execute(input:)
        "Result: #{input}"
      end
    end

    tool_instance = tool_class.new
    mcp_tool = nil

    ::MCP::Tool.stub :define, ->(name:, description:, input_schema:, &block) {
      mcp_tool = { name: name, description: description, schema: input_schema, block: block }
      Object.new
    } do
      AI::MCP::Adapter.to_mcp_tool(tool_instance)
    end

    assert_equal "Test tool description", mcp_tool[:description]
  end

  def test_execute_tool_returns_response
    tool_class = Class.new(RubyLLM::Tool) do
      description "Echo tool"

      def execute(**args)
        "Echoed: #{args[:message]}"
      end
    end

    tool = tool_class.new
    response = nil

    ::MCP::Tool::Response.stub :new, ->(content, **opts) {
      response = { content: content, opts: opts }
      Object.new
    } do
      AI::MCP::Adapter.execute_tool(tool, { message: "hello" }, {})
    end

    assert_equal [{ type: "text", text: "Echoed: hello" }], response[:content]
  end

  def test_execute_tool_handles_errors
    tool_class = Class.new(RubyLLM::Tool) do
      description "Failing tool"

      def execute(**)
        raise "Tool error"
      end
    end

    tool = tool_class.new
    response = nil

    ::MCP::Tool::Response.stub :new, ->(content, **opts) {
      response = { content: content, opts: opts }
      Object.new
    } do
      AI::MCP::Adapter.execute_tool(tool, {}, {})
    end

    assert response[:opts][:is_error]
    assert_match(/Error:/, response[:content].first[:text])
  end

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
end
```

#### `test/unit/extensions/ai/mcp/server_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"
require "durable_workflow/extensions/ai"

class MCPServerTest < Minitest::Test
  include DurableWorkflow::TestHelpers
  AI = DurableWorkflow::Extensions::AI

  def setup
    AI::ToolRegistry.reset!
  end

  def teardown
    AI::ToolRegistry.reset!
  end

  def test_build_creates_mcp_server
    workflow = create_workflow_with_tools

    server = nil
    ::MCP::Server.stub :new, ->(name:, version:, tools:, server_context:) {
      server = { name: name, version: version, tools: tools }
      Object.new
    } do
      AI::MCP::Server.build(workflow)
    end

    assert_match(/durable_workflow/, server[:name])
  end

  def test_build_with_custom_name
    workflow = create_workflow_with_tools

    server = nil
    ::MCP::Server.stub :new, ->(name:, **) {
      server = { name: name }
      Object.new
    } do
      AI::MCP::Server.build(workflow, name: "custom_server")
    end

    assert_equal "custom_server", server[:name]
  end

  def test_expose_workflow_adds_workflow_tool
    workflow = create_workflow_with_tools

    tools_count = 0
    ::MCP::Server.stub :new, ->(tools:, **) {
      tools_count = tools.size
      Object.new
    } do
      ::MCP::Tool.stub :define, Object.new do
        AI::MCP::Server.build(workflow, expose_workflow: true)
      end
    end

    # Should have workflow tools + exposed workflow tool
    assert tools_count >= 1
  end

  private

  def create_workflow_with_tools
    DurableWorkflow::Core::WorkflowDef.new(
      id: "test_wf",
      name: "Test Workflow",
      version: "1.0",
      steps: [
        DurableWorkflow::Core::StepDef.new(
          id: "start",
          type: "start",
          config: DurableWorkflow::Core::StartConfig.new
        )
      ],
      extensions: {
        ai: {
          tools: {}
        }
      }
    )
  end
end
```

### 2. Configuration Tests

```ruby
# test/unit/extensions/ai/configuration_test.rb

class ConfigurationTest < Minitest::Test
  AI = DurableWorkflow::Extensions::AI

  def test_default_model_is_gpt_4o_mini
    config = AI::Configuration.new
    assert_equal "gpt-4o-mini", config.default_model
  end

  def test_api_keys_empty_by_default
    config = AI::Configuration.new
    assert_equal({}, config.api_keys)
  end

  def test_configure_yields_configuration
    AI.configure do |c|
      c.default_model = "claude-3-sonnet"
      c.api_keys[:anthropic] = "test-key"
    end

    assert_equal "claude-3-sonnet", AI.configuration.default_model
    assert_equal "test-key", AI.configuration.api_keys[:anthropic]
  end

  def test_chat_uses_default_model
    model_used = nil

    RubyLLM.stub :chat, ->(model:) {
      model_used = model
      Object.new
    } do
      AI.chat
    end

    assert_equal AI.configuration.default_model, model_used
  end

  def test_chat_accepts_model_override
    model_used = nil

    RubyLLM.stub :chat, ->(model:) {
      model_used = model
      Object.new
    } do
      AI.chat(model: "gpt-4")
    end

    assert_equal "gpt-4", model_used
  end
end
```

### 3. ToolRegistry Tests

```ruby
# test/unit/extensions/ai/tool_registry_test.rb

class ToolRegistryTest < Minitest::Test
  AI = DurableWorkflow::Extensions::AI

  def setup
    AI::ToolRegistry.reset!
    # Clean up generated tools
    AI::GeneratedTools.constants.each do |c|
      AI::GeneratedTools.send(:remove_const, c)
    end
  end

  def teardown
    AI::ToolRegistry.reset!
  end

  def test_register_stores_tool_class
    tool_class = Class.new(RubyLLM::Tool) do
      description "Test"
    end

    AI::ToolRegistry.register(tool_class)

    refute_empty AI::ToolRegistry.all
  end

  def test_register_from_def_creates_ruby_llm_tool
    tool_def = AI::ToolDef.new(
      id: "test_tool",
      description: "A test tool",
      parameters: [],
      service: "TestService",
      method_name: "call"
    )

    AI::ToolRegistry.register_from_def(tool_def)

    tool_class = AI::ToolRegistry["test_tool"]
    refute_nil tool_class
    assert tool_class < RubyLLM::Tool
  end

  def test_bracket_accessor_retrieves_tool
    tool_def = AI::ToolDef.new(
      id: "lookup",
      description: "Lookup",
      parameters: [],
      service: "LookupService",
      method_name: "find"
    )

    AI::ToolRegistry.register_from_def(tool_def)

    assert_equal AI::ToolRegistry["lookup"], AI::ToolRegistry.registry["lookup"]
  end

  def test_all_returns_all_tool_classes
    tool_def1 = AI::ToolDef.new(
      id: "tool_a",
      description: "Tool A",
      parameters: [],
      service: "ServiceA",
      method_name: "call"
    )
    tool_def2 = AI::ToolDef.new(
      id: "tool_b",
      description: "Tool B",
      parameters: [],
      service: "ServiceB",
      method_name: "call"
    )

    AI::ToolRegistry.register_from_def(tool_def1)
    AI::ToolRegistry.register_from_def(tool_def2)

    assert_equal 2, AI::ToolRegistry.all.size
  end

  def test_reset_clears_registry
    tool_def = AI::ToolDef.new(
      id: "temp",
      description: "Temp",
      parameters: [],
      service: "TempService",
      method_name: "call"
    )

    AI::ToolRegistry.register_from_def(tool_def)
    AI::ToolRegistry.reset!

    assert_empty AI::ToolRegistry.all
  end
end
```

### 4. ToolDef#to_ruby_llm_tool Tests

```ruby
# test/unit/extensions/ai/types/tool_def_test.rb

class ToolDefTest < Minitest::Test
  AI = DurableWorkflow::Extensions::AI

  def setup
    # Clean up generated tools
    AI::GeneratedTools.constants.each do |c|
      AI::GeneratedTools.send(:remove_const, c)
    end
  end

  def test_to_ruby_llm_tool_creates_subclass
    tool_def = AI::ToolDef.new(
      id: "my_tool",
      description: "My tool description",
      parameters: [],
      service: "MyService",
      method_name: "call"
    )

    tool_class = tool_def.to_ruby_llm_tool

    assert tool_class < RubyLLM::Tool
  end

  def test_generated_tool_has_description
    tool_def = AI::ToolDef.new(
      id: "described_tool",
      description: "This is the description",
      parameters: [],
      service: "MyService",
      method_name: "call"
    )

    tool_class = tool_def.to_ruby_llm_tool

    assert_equal "This is the description", tool_class.new.description
  end

  def test_generated_tool_has_parameters
    tool_def = AI::ToolDef.new(
      id: "param_tool",
      description: "Tool with params",
      parameters: [
        AI::ToolParam.new(name: "query", type: "string", required: true, description: "Search query"),
        AI::ToolParam.new(name: "limit", type: "integer", required: false, description: "Max results")
      ],
      service: "SearchService",
      method_name: "search"
    )

    tool_class = tool_def.to_ruby_llm_tool

    # Verify the tool was created with proper params
    refute_nil tool_class
  end

  def test_generated_tool_stores_tool_def_reference
    tool_def = AI::ToolDef.new(
      id: "ref_tool",
      description: "Reference tool",
      parameters: [],
      service: "RefService",
      method_name: "call"
    )

    tool_class = tool_def.to_ruby_llm_tool

    assert_equal tool_def, tool_class.tool_def
  end

  def test_generated_tool_execute_calls_service
    # Define a test service
    Object.const_set(:ExecuteTestService, Module.new do
      def self.do_thing(input:)
        "Result: #{input}"
      end
    end)

    tool_def = AI::ToolDef.new(
      id: "execute_tool",
      description: "Execute test",
      parameters: [
        AI::ToolParam.new(name: "input", type: "string", required: true)
      ],
      service: "ExecuteTestService",
      method_name: "do_thing"
    )

    tool_class = tool_def.to_ruby_llm_tool
    tool_instance = tool_class.new

    result = tool_instance.execute(input: "test")

    assert_equal "Result: test", result
  ensure
    Object.send(:remove_const, :ExecuteTestService) if defined?(ExecuteTestService)
  end

  def test_generated_tool_class_is_named
    tool_def = AI::ToolDef.new(
      id: "named_tool",
      description: "Named tool",
      parameters: [],
      service: "NamedService",
      method_name: "call"
    )

    tool_class = tool_def.to_ruby_llm_tool

    # Should be defined under GeneratedTools module
    assert AI::GeneratedTools.const_defined?(:NamedTool)
    assert_equal AI::GeneratedTools::NamedTool, tool_class
  end
end
```

## Acceptance Criteria

1. All MCP components have tests
2. Configuration tests verify API key handling
3. ToolRegistry tests cover registration and retrieval
4. ToolDef#to_ruby_llm_tool tests verify class generation
5. All new tests pass with existing 423 tests
