# frozen_string_literal: true

require "test_helper"
require "durable_workflow/extensions/ai"

class ToolDefTest < Minitest::Test
  AI = DurableWorkflow::Extensions::AI

  def setup
    # Clean up generated tools
    clean_generated_tools
  end

  def teardown
    clean_generated_tools
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

    # description is a class method on RubyLLM::Tool
    assert_equal "This is the description", tool_class.description
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

  def test_generated_tool_handles_snake_case_id
    tool_def = AI::ToolDef.new(
      id: "my_snake_case_tool",
      description: "Snake case tool",
      parameters: [],
      service: "SnakeService",
      method_name: "call"
    )

    tool_class = tool_def.to_ruby_llm_tool

    assert AI::GeneratedTools.const_defined?(:MySnakeCaseTool)
    assert_equal AI::GeneratedTools::MySnakeCaseTool, tool_class
  end

  def test_generated_tool_with_parameters
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

    # Verify the tool was created
    refute_nil tool_class
    assert tool_class < RubyLLM::Tool
  end

  def test_to_function_schema
    tool_def = AI::ToolDef.new(
      id: "schema_tool",
      description: "Schema test tool",
      parameters: [
        AI::ToolParam.new(name: "query", type: "string", required: true, description: "Search query"),
        AI::ToolParam.new(name: "limit", type: "integer", required: false, description: "Max results")
      ],
      service: "SchemaService",
      method_name: "search"
    )

    schema = tool_def.to_function_schema

    assert_equal "schema_tool", schema[:name]
    assert_equal "Schema test tool", schema[:description]
    assert_equal "object", schema[:parameters][:type]
    assert_includes schema[:parameters][:properties].keys, "query"
    assert_includes schema[:parameters][:properties].keys, "limit"
    assert_equal ["query"], schema[:parameters][:required]
  end

  private

  def clean_generated_tools
    AI::GeneratedTools.constants.each do |c|
      AI::GeneratedTools.send(:remove_const, c)
    end
  end
end
