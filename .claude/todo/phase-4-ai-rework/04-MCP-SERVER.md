# 04-MCP-SERVER: Expose Workflow Tools via MCP

## Goal

Expose workflow tools as an MCP server. External AI agents (Claude Desktop, etc.) can discover and call them.

## Architecture

```
Workflow tools (RubyLLM::Tool)
         ↓
    MCP::Adapter
         ↓
    MCP::Server
         ↓
  ┌──────┴──────┐
  │             │
Stdio         HTTP
(Claude)    (Remote)
```

## Files to Create

### `lib/durable_workflow/extensions/ai/mcp/adapter.rb`

Converts RubyLLM::Tool → MCP::Tool:

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module MCP
        class Adapter
          class << self
            # Convert RubyLLM::Tool instance to MCP::Tool
            def to_mcp_tool(ruby_llm_tool)
              tool_name = extract_name(ruby_llm_tool)
              tool_description = ruby_llm_tool.description
              tool_schema = ruby_llm_tool.params_schema

              captured_tool = ruby_llm_tool

              ::MCP::Tool.define(
                name: tool_name,
                description: tool_description,
                input_schema: normalize_schema(tool_schema)
              ) do |server_context:, **params|
                execute_tool(captured_tool, params, server_context)
              end
            end

            def execute_tool(tool, params, server_context)
              result = tool.call(params.transform_keys(&:to_sym))
              formatted = format_result(result)

              ::MCP::Tool::Response.new([
                { type: "text", text: formatted }
              ])
            rescue StandardError => e
              ::MCP::Tool::Response.new([
                { type: "text", text: "Error: #{e.message}" }
              ], error: true)
            end

            private

            def extract_name(tool)
              if tool.class.respond_to?(:tool_def) && tool.class.tool_def
                tool.class.tool_def.id
              else
                tool.name || tool.class.name&.demodulize&.underscore || "unknown"
              end
            end

            def normalize_schema(schema)
              return { properties: {}, required: [] } if schema.nil?
              {
                properties: schema["properties"] || schema[:properties] || {},
                required: schema["required"] || schema[:required] || []
              }
            end

            def format_result(result)
              case result
              when String then result
              when Hash, Array then JSON.pretty_generate(result)
              else result.to_s
              end
            end
          end
        end
      end
    end
  end
end
```

### `lib/durable_workflow/extensions/ai/mcp/server.rb`

Builds MCP::Server from workflow:

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module MCP
        class Server
          attr_reader :workflow, :options

          def initialize(workflow, **options)
            @workflow = workflow
            @options = options
          end

          # Build MCP::Server with workflow tools
          def build(server_context: {})
            ::MCP::Server.new(
              name: server_name,
              version: server_version,
              tools: build_tools,
              server_context: server_context
            )
          end

          # Run as stdio transport (for Claude Desktop)
          def stdio(server_context: {})
            server = build(server_context: server_context)
            transport = ::MCP::Server::Transports::StdioTransport.new(server)
            transport.open
          end

          # Build Rack app for HTTP transport
          def rack_app(server_context: {})
            server = build(server_context: server_context)
            RackApp.new(server)
          end

          class << self
            def build(workflow, **options)
              new(workflow, **options).build
            end

            def stdio(workflow, **options)
              new(workflow, **options).stdio
            end

            def rack_app(workflow, **options)
              new(workflow, **options).rack_app
            end
          end

          private

          def server_name
            options[:name] || "durable_workflow_#{workflow.id}"
          end

          def server_version
            options[:version] || DurableWorkflow::VERSION
          end

          def build_tools
            mcp_tools = []

            # Convert workflow tools to MCP tools
            ToolRegistry.for_workflow(workflow).each do |tool_class|
              tool_instance = tool_class.new
              mcp_tools << Adapter.to_mcp_tool(tool_instance)
            end

            # Optionally expose workflow itself as a tool
            if options[:expose_workflow]
              mcp_tools << build_workflow_tool
            end

            mcp_tools
          end

          def build_workflow_tool
            wf = workflow
            store = DurableWorkflow.config&.store

            ::MCP::Tool.define(
              name: "run_#{workflow.id}",
              description: workflow.description || "Run #{workflow.name} workflow",
              input_schema: workflow_input_schema
            ) do |server_context:, **params|
              runner = DurableWorkflow::Runners::Sync.new(wf, store: store)
              result = runner.run(params)

              ::MCP::Tool::Response.new([{
                type: "text",
                text: JSON.pretty_generate({
                  status: result.status,
                  output: result.output
                })
              }])
            end
          end

          def workflow_input_schema
            props = {}
            required = []

            (workflow.inputs || []).each do |input_def|
              props[input_def.name] = {
                type: input_def.type,
                description: input_def.description
              }.compact
              required << input_def.name if input_def.required
            end

            { properties: props, required: required }
          end
        end
      end
    end
  end
end
```

### `lib/durable_workflow/extensions/ai/mcp/rack_app.rb`

HTTP transport wrapper:

```ruby
# frozen_string_literal: true

require "json"

module DurableWorkflow
  module Extensions
    module AI
      module MCP
        class RackApp
          def initialize(server)
            @server = server
          end

          def call(env)
            request = Rack::Request.new(env)

            case request.request_method
            when "POST"
              handle_post(request)
            when "GET"
              handle_sse(request)
            when "DELETE"
              handle_delete(request)
            else
              [405, { "Content-Type" => "text/plain" }, ["Method not allowed"]]
            end
          end

          private

          def handle_post(request)
            body = request.body.read
            result = @server.handle_json(body)

            [200, { "Content-Type" => "application/json" }, [result]]
          rescue JSON::ParserError => e
            error_response(-32700, "Parse error: #{e.message}")
          rescue StandardError => e
            error_response(-32603, "Internal error")
          end

          def handle_sse(request)
            # SSE for notifications (optional)
            [501, { "Content-Type" => "text/plain" }, ["SSE not implemented"]]
          end

          def handle_delete(request)
            # Session cleanup
            [200, {}, [""]]
          end

          def error_response(code, message)
            [400, { "Content-Type" => "application/json" }, [
              JSON.generate({
                jsonrpc: "2.0",
                error: { code: code, message: message },
                id: nil
              })
            ]]
          end
        end
      end
    end
  end
end
```

### `exe/durable_workflow_mcp`

CLI for Claude Desktop:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "durable_workflow"
require "durable_workflow/extensions/ai"

workflow_path = ARGV[0]
unless workflow_path
  $stderr.puts "Usage: durable_workflow_mcp <workflow.yml>"
  exit 1
end

# Suppress stdout logging (corrupts MCP protocol)
DurableWorkflow.configure do |c|
  c.logger = Logger.new("/dev/null")
end

workflow = DurableWorkflow.load(workflow_path)
DurableWorkflow::Extensions::AI::MCP::Server.stdio(workflow)
```

Make executable: `chmod +x exe/durable_workflow_mcp`

## Usage

### Claude Desktop Configuration

`~/.config/claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "my_workflow": {
      "command": "bundle",
      "args": ["exec", "durable_workflow_mcp", "path/to/workflow.yml"],
      "cwd": "/path/to/project"
    }
  }
}
```

### Rails Integration

```ruby
# config/routes.rb
workflow = DurableWorkflow.load("support.yml")
mount DurableWorkflow::Extensions::AI::MCP::Server.rack_app(workflow), at: "/mcp"
```

### Expose Workflow as Tool

```ruby
# Workflow itself becomes a callable tool
server = MCP::Server.build(workflow, expose_workflow: true)

# Claude can now call: run_support_workflow(input)
```

## Tests

### `test/unit/extensions/ai/mcp/adapter_test.rb`

```ruby
class AdapterTest < Minitest::Test
  def test_to_mcp_tool_converts_ruby_llm_tool
    ruby_tool = create_ruby_llm_tool
    mcp_tool = Adapter.to_mcp_tool(ruby_tool)

    assert_respond_to mcp_tool, :name
    assert_respond_to mcp_tool, :description
  end

  def test_converted_tool_executes
    ruby_tool = create_ruby_llm_tool_that_returns("result")
    mcp_tool = Adapter.to_mcp_tool(ruby_tool)

    response = mcp_tool.call(server_context: {}, arg: "value")
    assert_includes response.content.first[:text], "result"
  end

  def test_converted_tool_handles_errors
    ruby_tool = create_ruby_llm_tool_that_raises
    mcp_tool = Adapter.to_mcp_tool(ruby_tool)

    response = mcp_tool.call(server_context: {})
    assert response.error
  end
end
```

### `test/unit/extensions/ai/mcp/server_test.rb`

```ruby
class ServerTest < Minitest::Test
  def test_build_creates_mcp_server
    workflow = create_workflow_with_tools
    server = MCP::Server.build(workflow)

    assert_instance_of ::MCP::Server, server
  end

  def test_server_includes_workflow_tools
    workflow = create_workflow_with_tools(["tool_a", "tool_b"])
    server = MCP::Server.build(workflow)

    tool_names = server.tools.map(&:name)
    assert_includes tool_names, "tool_a"
    assert_includes tool_names, "tool_b"
  end

  def test_expose_workflow_adds_workflow_tool
    workflow = create_workflow(id: "my_flow")
    server = MCP::Server.build(workflow, expose_workflow: true)

    tool_names = server.tools.map(&:name)
    assert_includes tool_names, "run_my_flow"
  end
end
```

## Acceptance Criteria

1. `Adapter.to_mcp_tool` converts RubyLLM::Tool to MCP::Tool
2. Converted tools execute correctly
3. Converted tools handle errors gracefully
4. `Server.build` creates MCP::Server with workflow tools
5. `Server.stdio` runs stdio transport
6. `Server.rack_app` returns Rack-compatible app
7. `expose_workflow: true` adds workflow as callable tool
8. CLI works with Claude Desktop
