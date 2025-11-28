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

  def test_build_with_custom_version
    workflow = create_workflow_with_tools

    server = nil
    ::MCP::Server.stub :new, ->(version:, **) {
      server = { version: version }
      Object.new
    } do
      AI::MCP::Server.build(workflow, version: "2.0.0")
    end

    assert_equal "2.0.0", server[:version]
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
