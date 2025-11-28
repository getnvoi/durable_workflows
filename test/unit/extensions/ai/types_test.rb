# frozen_string_literal: true

require "test_helper"
require "durable_workflow/extensions/ai"

class AITypesTest < Minitest::Test
  AI = DurableWorkflow::Extensions::AI

  def test_message_role_accepts_valid_roles
    %w[system user assistant tool].each do |role|
      msg = AI::Message.new(role: role, content: "test")
      assert_equal role, msg.role
    end
  end

  def test_handoff_def_requires_agent_id
    handoff = AI::HandoffDef.new(agent_id: "agent1", description: "Transfer")
    assert_equal "agent1", handoff.agent_id
    assert_equal "Transfer", handoff.description
  end

  def test_agent_def_can_be_created
    agent = AI::AgentDef.new(
      id: "agent1",
      name: "Test Agent",
      model: "gpt-4",
      instructions: "You are helpful"
    )

    assert_equal "agent1", agent.id
    assert_equal "gpt-4", agent.model
    assert_equal "You are helpful", agent.instructions
  end

  def test_agent_def_tools_defaults_to_empty
    agent = AI::AgentDef.new(id: "a", model: "m")
    assert_equal [], agent.tools
  end

  def test_agent_def_handoffs_defaults_to_empty
    agent = AI::AgentDef.new(id: "a", model: "m")
    assert_equal [], agent.handoffs
  end

  def test_tool_param_can_be_created
    param = AI::ToolParam.new(
      name: "query",
      type: "string",
      required: true,
      description: "Search query"
    )

    assert_equal "query", param.name
    assert_equal "string", param.type
    assert param.required
  end

  def test_tool_param_type_defaults_to_string
    param = AI::ToolParam.new(name: "x")
    assert_equal "string", param.type
  end

  def test_tool_param_required_defaults_to_true
    param = AI::ToolParam.new(name: "x")
    assert param.required
  end

  def test_tool_def_can_be_created
    tool = AI::ToolDef.new(
      id: "search",
      description: "Search the web",
      service: "SearchService",
      method_name: "search"
    )

    assert_equal "search", tool.id
    assert_equal "SearchService", tool.service
  end

  def test_tool_def_to_function_schema
    tool = AI::ToolDef.new(
      id: "lookup",
      description: "Look up data",
      parameters: [
        AI::ToolParam.new(name: "id", type: "string", required: true, description: "Record ID"),
        AI::ToolParam.new(name: "fields", type: "array", required: false)
      ],
      service: "DataService",
      method_name: "lookup"
    )

    schema = tool.to_function_schema

    assert_equal "lookup", schema[:name]
    assert_equal "Look up data", schema[:description]
    assert_equal "object", schema[:parameters][:type]
    assert_equal({ type: "string", description: "Record ID" }, schema[:parameters][:properties]["id"])
    assert_equal ["id"], schema[:parameters][:required]
  end

  def test_tool_call_can_be_created
    tc = AI::ToolCall.new(
      id: "call_123",
      name: "search",
      arguments: { query: "test" }
    )

    assert_equal "call_123", tc.id
    assert_equal "search", tc.name
    assert_equal({ query: "test" }, tc.arguments)
  end

  def test_message_system_factory
    msg = AI::Message.system("You are helpful")
    assert_equal "system", msg.role
    assert_equal "You are helpful", msg.content
  end

  def test_message_user_factory
    msg = AI::Message.user("Hello")
    assert_equal "user", msg.role
    assert_equal "Hello", msg.content
  end

  def test_message_assistant_factory
    msg = AI::Message.assistant("Hi there")
    assert_equal "assistant", msg.role
    assert_equal "Hi there", msg.content
  end

  def test_message_tool_factory
    msg = AI::Message.tool("result", tool_call_id: "tc_1", name: "search")
    assert_equal "tool", msg.role
    assert_equal "result", msg.content
    assert_equal "tc_1", msg.tool_call_id
  end

  def test_message_tool_calls_predicate
    msg_with = AI::Message.assistant("", tool_calls: [AI::ToolCall.new(id: "1", name: "t")])
    msg_without = AI::Message.assistant("hello")

    assert msg_with.tool_calls?
    refute msg_without.tool_calls?
  end

  def test_response_stores_content_and_tool_calls
    response = AI::Response.new(
      content: "Hello",
      tool_calls: [AI::ToolCall.new(id: "1", name: "search")],
      finish_reason: "stop"
    )

    assert_equal "Hello", response.content
    assert_equal 1, response.tool_calls.size
    assert_equal "stop", response.finish_reason
  end

  def test_response_tool_calls_predicate
    with_calls = AI::Response.new(tool_calls: [AI::ToolCall.new(id: "1", name: "t")])
    without_calls = AI::Response.new(content: "done")

    assert with_calls.tool_calls?
    refute without_calls.tool_calls?
  end

  def test_moderation_result_stores_flagged
    result = AI::ModerationResult.new(flagged: true, categories: { hate: true })
    assert result.flagged
    assert_equal({ hate: true }, result.categories)
  end

  def test_guardrail_check_stores_fields
    check = AI::GuardrailCheck.new(
      type: "regex",
      pattern: "bad.*word",
      block_on_match: true,
      max: 1000
    )

    assert_equal "regex", check.type
    assert_equal "bad.*word", check.pattern
    assert check.block_on_match
    assert_equal 1000, check.max
  end

  def test_guardrail_result_stores_fields
    result = AI::GuardrailResult.new(
      passed: false,
      check_type: "pii",
      reason: "SSN detected"
    )

    refute result.passed
    assert_equal "pii", result.check_type
    assert_equal "SSN detected", result.reason
  end
end

class AIConfigsTest < Minitest::Test
  AI = DurableWorkflow::Extensions::AI

  def test_agent_config_requires_fields
    config = AI::AgentConfig.new(
      agent_id: "agent1",
      prompt: "$input.message",
      output: :response
    )

    assert_equal "agent1", config.agent_id
    assert_equal "$input.message", config.prompt
    assert_equal :response, config.output
  end

  def test_guardrail_config_accepts_fields
    config = AI::GuardrailConfig.new(
      content: "$message",
      checks: [{ type: "pii" }],
      on_fail: "reject"
    )

    assert_equal "$message", config.content
    assert_equal "reject", config.on_fail
  end

  def test_handoff_config_accepts_fields
    config = AI::HandoffConfig.new(
      to: "billing_agent",
      from: "triage_agent",
      reason: "Billing inquiry"
    )

    assert_equal "billing_agent", config.to
    assert_equal "triage_agent", config.from
  end

  def test_file_search_config_requires_query
    config = AI::FileSearchConfig.new(
      query: "search term",
      files: ["doc.pdf"],
      max_results: 5,
      output: :results
    )

    assert_equal "search term", config.query
    assert_equal ["doc.pdf"], config.files
    assert_equal 5, config.max_results
  end

  def test_mcp_config_requires_server_and_tool
    config = AI::MCPConfig.new(
      server: "filesystem",
      tool: "read_file",
      arguments: { path: "/tmp/test.txt" },
      output: :content
    )

    assert_equal "filesystem", config.server
    assert_equal "read_file", config.tool
  end
end
