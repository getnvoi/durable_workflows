# frozen_string_literal: true

require "test_helper"
require "durable_workflow/extensions/ai"

class ToolRegistryTest < Minitest::Test
  AI = DurableWorkflow::Extensions::AI

  def setup
    AI::ToolRegistry.reset!
    # Clean up generated tools
    clean_generated_tools
  end

  def teardown
    AI::ToolRegistry.reset!
    clean_generated_tools
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
      id: "registry_test_tool",
      description: "A test tool",
      parameters: [],
      service: "TestService",
      method_name: "call"
    )

    AI::ToolRegistry.register_from_def(tool_def)

    tool_class = AI::ToolRegistry["registry_test_tool"]
    refute_nil tool_class
    assert tool_class < RubyLLM::Tool
  end

  def test_bracket_accessor_retrieves_tool
    tool_def = AI::ToolDef.new(
      id: "registry_lookup",
      description: "Lookup",
      parameters: [],
      service: "LookupService",
      method_name: "find"
    )

    AI::ToolRegistry.register_from_def(tool_def)

    assert_equal AI::ToolRegistry["registry_lookup"], AI::ToolRegistry.registry["registry_lookup"]
  end

  def test_all_returns_all_tool_classes
    tool_def1 = AI::ToolDef.new(
      id: "registry_tool_a",
      description: "Tool A",
      parameters: [],
      service: "ServiceA",
      method_name: "call"
    )
    tool_def2 = AI::ToolDef.new(
      id: "registry_tool_b",
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
      id: "registry_temp",
      description: "Temp",
      parameters: [],
      service: "TempService",
      method_name: "call"
    )

    AI::ToolRegistry.register_from_def(tool_def)
    AI::ToolRegistry.reset!

    assert_empty AI::ToolRegistry.all
  end

  def test_for_tool_ids_returns_tool_instances
    tool_def = AI::ToolDef.new(
      id: "workflow_tool",
      description: "Workflow tool",
      parameters: [],
      service: "WorkflowService",
      method_name: "call"
    )

    AI::ToolRegistry.register_from_def(tool_def)

    tools = AI::ToolRegistry.for_tool_ids(["workflow_tool"])

    assert_equal 1, tools.size
    assert_kind_of RubyLLM::Tool, tools.first
  end

  def test_for_tool_ids_ignores_unknown_tools
    tools = AI::ToolRegistry.for_tool_ids(["nonexistent_tool"])

    assert_empty tools
  end

  private

  def clean_generated_tools
    AI::GeneratedTools.constants.each do |c|
      AI::GeneratedTools.send(:remove_const, c)
    end
  end
end
