# frozen_string_literal: true

require "test_helper"
require "durable_workflow/extensions/ai"

class MCPExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers
  AI = DurableWorkflow::Extensions::AI

  def setup
    @workflow = build_mcp_workflow
    DurableWorkflow.register(@workflow)
    AI::MCP::Client.reset!
  end

  def teardown
    DurableWorkflow.registry.delete(@workflow.id)
    AI::MCP::Client.reset!
  end

  def test_registered_as_mcp
    assert DurableWorkflow::Core::Executors::Registry.registered?("mcp")
  end

  def test_raises_when_server_not_found
    step = build_mcp_step(
      server: "unknown_server",
      tool: "read_file"
    )
    executor = AI::Executors::MCP.new(step)
    state = build_state(workflow_id: @workflow.id)

    error = assert_raises(DurableWorkflow::ExecutionError) do
      executor.call(state)
    end

    assert_match(/MCP server not found/, error.message)
  end

  def test_resolves_arguments_from_state
    mock_response = AI::MockMCPResponse.new([{ text: "file content" }])

    step = build_mcp_step(
      server: "filesystem",
      tool: "read_file",
      arguments: { path: "$file_path" }
    )
    executor = AI::Executors::MCP.new(step)
    state = build_state(workflow_id: @workflow.id, ctx: { file_path: "/tmp/test.txt" })

    AI::MCP::Client.stub :call_tool, mock_response do
      outcome = executor.call(state)
      assert_equal "file content", outcome.result.output
    end
  end

  def test_stores_result_in_output
    mock_response = AI::MockMCPResponse.new([{ text: "result data" }])

    step = build_mcp_step(
      server: "filesystem",
      tool: "read_file",
      output: :file_content
    )
    executor = AI::Executors::MCP.new(step)
    state = build_state(workflow_id: @workflow.id)

    AI::MCP::Client.stub :call_tool, mock_response do
      outcome = executor.call(state)
      assert_equal "result data", outcome.state.ctx[:file_content]
    end
  end

  def test_calls_mcp_client
    called_with = nil
    mock_call = lambda do |server_config, tool_name, args|
      called_with = { server: server_config, tool: tool_name, args: args }
      AI::MockMCPResponse.new([{ text: "ok" }])
    end

    step = build_mcp_step(server: "filesystem", tool: "read_file", arguments: { path: "/test" })
    executor = AI::Executors::MCP.new(step)
    state = build_state(workflow_id: @workflow.id)

    AI::MCP::Client.stub :call_tool, mock_call do
      executor.call(state)
    end

    assert_equal "read_file", called_with[:tool]
    assert_equal({ path: "/test" }, called_with[:args])
  end

  private

    def build_mcp_workflow
      DurableWorkflow::Core::WorkflowDef.new(
        id: "mcp_test_wf",
        name: "MCP Test",
        steps: [
          DurableWorkflow::Core::StepDef.new(
            id: "start",
            type: "start",
            config: DurableWorkflow::Core::StartConfig.new
          )
        ],
        extensions: {
          ai: {
            mcp_servers: {
              filesystem: AI::MCPServerConfig.new(
                url: "https://mcp.example.com",
                transport: :http
              )
            }
          }
        }
      )
    end

    def build_mcp_step(server:, tool:, arguments: {}, output: nil)
      DurableWorkflow::Core::StepDef.new(
        id: "mcp",
        type: "mcp",
        config: AI::MCPConfig.new(
          server: server,
          tool: tool,
          arguments: arguments,
          output: output
        ),
        next_step: "next"
      )
    end
end
