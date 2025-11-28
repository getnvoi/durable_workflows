# 05-MCP-CLIENT: Consume External MCP Servers

## Goal

Workflow steps can call tools on external MCP servers. The `mcp` step executor uses MCP::Client.

## Architecture

```
Workflow step:              MCP Client:              External Server:
  type: mcp          →      Client.for(config)   →   tools/list
  server: github            Client.call_tool()   →   tools/call
  tool: list_issues
```

## Workflow YAML

```yaml
mcp_servers:
  github:
    url: "https://mcp.github.com/v1"
    headers:
      Authorization: "Bearer ${GITHUB_TOKEN}"
  local_db:
    transport: stdio
    command: ["python", "db_server.py"]

steps:
  - id: get_issues
    type: mcp
    server: github
    tool: list_issues
    arguments:
      repo: "$input.repo"
    output: issues
```

## Files to Create

### `lib/durable_workflow/extensions/ai/mcp/client.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module MCP
        class Client
          @connections = {}

          class << self
            # Get or create client for server config
            def for(server_config)
              cache_key = server_config[:url] || server_config[:command].to_s
              @connections[cache_key] ||= build_client(server_config)
            end

            # List tools from server
            def tools(server_config)
              client = self.for(server_config)
              client.tools
            end

            # Call tool on server
            def call_tool(server_config, tool_name, arguments)
              client = self.for(server_config)
              tool = client.tools.find { |t| t.name == tool_name }
              raise DurableWorkflow::ExecutionError, "MCP tool not found: #{tool_name}" unless tool

              client.call_tool(tool: tool, arguments: arguments)
            end

            # Clear connection cache
            def reset!
              @connections.clear
            end

            private

            def build_client(server_config)
              transport = build_transport(server_config)
              ::MCP::Client.new(transport: transport)
            end

            def build_transport(server_config)
              case server_config[:transport]&.to_sym
              when :stdio
                build_stdio_transport(server_config)
              else
                build_http_transport(server_config)
              end
            end

            def build_http_transport(config)
              ::MCP::Client::HTTP.new(
                url: config[:url],
                headers: interpolate_env(config[:headers] || {})
              )
            end

            def build_stdio_transport(config)
              ::MCP::Client::Stdio.new(
                command: config[:command]
              )
            end

            # Replace ${ENV_VAR} with actual values
            def interpolate_env(headers)
              headers.transform_values do |v|
                v.gsub(/\$\{(\w+)\}/) { ENV.fetch(::Regexp.last_match(1), "") }
              end
            end
          end
        end
      end
    end
  end
end
```

## Files to Update

### `lib/durable_workflow/extensions/ai/types.rb`

Add MCPServerConfig:

```ruby
class MCPServerConfig < BaseStruct
  attribute? :url, Types::Strict::String.optional
  attribute? :headers, Types::Hash.default({}.freeze)
  attribute? :transport, Types::Coercible::Symbol.default(:http)
  attribute? :command, Types::Strict::Array.of(Types::Strict::String).optional
end
```

### `lib/durable_workflow/extensions/ai/executors/mcp.rb`

Rewrite with real MCP::Client:

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module Executors
        class MCP < Core::Executors::Base
          Core::Executors::Registry.register("mcp", self)

          def call(state)
            server_config = resolve_server(config.server)
            tool_name = config.tool
            arguments = resolve(state, config.arguments || {})

            result = AI::MCP::Client.call_tool(server_config, tool_name, arguments)

            # Extract text content from MCP response
            output = extract_output(result)

            state = store(state, config.output, output) if config.output
            continue(state, output: output)
          end

          private

          def resolve_server(server_id)
            servers = AI.data_from(workflow)[:mcp_servers] || {}
            server_config = servers[server_id.to_sym]
            raise ExecutionError, "MCP server not found: #{server_id}" unless server_config
            server_config
          end

          def extract_output(result)
            if result.respond_to?(:content)
              result.content.map { |c| c[:text] || c["text"] }.compact.join("\n")
            else
              result.to_s
            end
          end

          def workflow
            @workflow ||= DurableWorkflow.registry[state.workflow_id]
          end
        end
      end
    end
  end
end
```

### Parser Updates

In `lib/durable_workflow/extensions/ai/ai.rb`, add mcp_servers parsing:

```ruby
# In after_parse hook
def self.parse_mcp_servers(raw)
  return {} unless raw[:mcp_servers]

  raw[:mcp_servers].transform_values do |config|
    MCPServerConfig.new(
      url: config[:url],
      headers: config[:headers] || {},
      transport: config[:transport]&.to_sym || :http,
      command: config[:command]
    )
  end
end
```

## Tests

### `test/unit/extensions/ai/mcp/client_test.rb`

```ruby
class ClientTest < Minitest::Test
  def setup
    AI::MCP::Client.reset!
  end

  def test_for_creates_client_with_http_transport
    config = { url: "https://example.com/mcp" }

    mock_transport = Minitest::Mock.new
    mock_client = Minitest::Mock.new

    ::MCP::Client::HTTP.stub :new, mock_transport do
      ::MCP::Client.stub :new, mock_client do
        result = AI::MCP::Client.for(config)
        assert_equal mock_client, result
      end
    end
  end

  def test_for_caches_connections
    config = { url: "https://example.com/mcp" }

    client1 = AI::MCP::Client.for(config)
    client2 = AI::MCP::Client.for(config)

    assert_same client1, client2
  end

  def test_call_tool_invokes_tool
    config = { url: "https://example.com/mcp" }

    mock_tool = OpenStruct.new(name: "my_tool")
    mock_response = OpenStruct.new(content: [{ text: "result" }])

    mock_client = Minitest::Mock.new
    mock_client.expect :tools, [mock_tool]
    mock_client.expect :call_tool, mock_response, [{ tool: mock_tool, arguments: { a: 1 } }]

    AI::MCP::Client.stub :for, mock_client do
      result = AI::MCP::Client.call_tool(config, "my_tool", { a: 1 })
      assert_equal mock_response, result
    end
  end

  def test_call_tool_raises_for_unknown_tool
    config = { url: "https://example.com/mcp" }

    mock_client = Minitest::Mock.new
    mock_client.expect :tools, []

    AI::MCP::Client.stub :for, mock_client do
      assert_raises(DurableWorkflow::ExecutionError) do
        AI::MCP::Client.call_tool(config, "unknown", {})
      end
    end
  end

  def test_interpolate_env_replaces_variables
    ENV["TEST_TOKEN"] = "secret123"
    headers = { "Authorization" => "Bearer ${TEST_TOKEN}" }

    result = AI::MCP::Client.send(:interpolate_env, headers)
    assert_equal "Bearer secret123", result["Authorization"]
  ensure
    ENV.delete("TEST_TOKEN")
  end
end
```

### `test/unit/extensions/ai/executors/mcp_test.rb`

```ruby
class MCPExecutorTest < Minitest::Test
  def test_mcp_executor_resolves_server_config
    workflow = create_workflow_with_mcp_servers({
      github: { url: "https://mcp.github.com" }
    })

    executor = create_mcp_executor(server: "github", tool: "list_issues")

    AI::MCP::Client.stub :call_tool, mock_response do
      outcome = executor.call(state)
      # Verify server config was resolved
    end
  end

  def test_mcp_executor_calls_tool
    # ...
  end

  def test_mcp_executor_stores_result
    # ...
  end

  def test_mcp_executor_raises_for_unknown_server
    workflow = create_workflow_with_mcp_servers({})
    executor = create_mcp_executor(server: "unknown", tool: "test")

    assert_raises(ExecutionError) do
      executor.call(state)
    end
  end
end
```

## Acceptance Criteria

1. `Client.for` creates client with HTTP transport
2. `Client.for` creates client with stdio transport
3. `Client.for` caches connections
4. `Client.call_tool` invokes tool and returns result
5. `Client.call_tool` raises for unknown tool
6. Environment variables interpolated in headers
7. MCP executor resolves server from workflow config
8. MCP executor calls tool via Client
9. MCP executor stores result in output
10. MCP executor raises for unknown server
