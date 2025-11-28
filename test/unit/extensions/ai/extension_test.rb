# frozen_string_literal: true

require "test_helper"
require "durable_workflow/extensions/ai"

class AIExtensionTest < Minitest::Test
  AI = DurableWorkflow::Extensions::AI

  def test_extension_name_is_ai
    assert_equal "ai", AI::Extension.extension_name
  end

  def test_registers_all_configs
    assert DurableWorkflow::Core.config_registered?("agent")
    assert DurableWorkflow::Core.config_registered?("guardrail")
    assert DurableWorkflow::Core.config_registered?("handoff")
    assert DurableWorkflow::Core.config_registered?("file_search")
    assert DurableWorkflow::Core.config_registered?("mcp")
  end

  def test_registers_all_executors
    assert DurableWorkflow::Core::Executors::Registry.registered?("agent")
    assert DurableWorkflow::Core::Executors::Registry.registered?("guardrail")
    assert DurableWorkflow::Core::Executors::Registry.registered?("handoff")
    assert DurableWorkflow::Core::Executors::Registry.registered?("file_search")
    assert DurableWorkflow::Core::Executors::Registry.registered?("mcp")
  end

  def test_parse_agents_parses_agents
    agents_raw = [
      { id: "agent1", name: "Agent 1", model: "gpt-4", instructions: "Be helpful" },
      { id: "agent2", model: "gpt-3.5-turbo" }
    ]

    agents = AI::Extension.parse_agents(agents_raw)

    assert_equal 2, agents.size
    assert_equal "agent1", agents["agent1"].id
    assert_equal "gpt-4", agents["agent1"].model
    assert_equal "Be helpful", agents["agent1"].instructions
    assert_equal "gpt-3.5-turbo", agents["agent2"].model
  end

  def test_parse_agents_parses_handoffs
    agents_raw = [
      {
        id: "triage",
        model: "gpt-4",
        handoffs: [
          { agent_id: "billing", description: "Billing issues" },
          { agent_id: "tech" }
        ]
      }
    ]

    agents = AI::Extension.parse_agents(agents_raw)

    assert_equal 2, agents["triage"].handoffs.size
    assert_equal "billing", agents["triage"].handoffs[0].agent_id
    assert_equal "Billing issues", agents["triage"].handoffs[0].description
  end

  def test_parse_tools_parses_tools
    tools_raw = [
      {
        id: "search",
        description: "Search the web",
        service: "SearchService",
        method: "search",
        parameters: [
          { name: "query", type: "string", required: true }
        ]
      }
    ]

    tools = AI::Extension.parse_tools(tools_raw)

    assert_equal 1, tools.size
    assert_equal "search", tools["search"].id
    assert_equal "SearchService", tools["search"].service
    assert_equal 1, tools["search"].parameters.size
  end

  def test_agents_returns_agents_from_workflow
    workflow = DurableWorkflow::Core::WorkflowDef.new(
      id: "test",
      name: "Test",
      steps: [],
      extensions: {
        ai: {
          agents: { "a1" => AI::AgentDef.new(id: "a1", model: "m") },
          tools: {}
        }
      }
    )

    agents = AI::Extension.agents(workflow)

    assert_equal 1, agents.size
    assert agents.key?("a1")
  end

  def test_tools_returns_tools_from_workflow
    workflow = DurableWorkflow::Core::WorkflowDef.new(
      id: "test",
      name: "Test",
      steps: [],
      extensions: {
        ai: {
          agents: {},
          tools: { "t1" => AI::ToolDef.new(id: "t1", description: "d", service: "S", method_name: "m") }
        }
      }
    )

    tools = AI::Extension.tools(workflow)

    assert_equal 1, tools.size
    assert tools.key?("t1")
  end

  def test_configure_sets_default_model
    AI.configure do |c|
      c.default_model = "test-model"
    end

    assert_equal "test-model", AI.configuration.default_model
  end

  def test_configure_sets_api_keys
    AI.configure do |c|
      c.api_keys[:openai] = "test-key"
    end

    assert_equal "test-key", AI.configuration.api_keys[:openai]
  end

  def test_chat_returns_ruby_llm_chat
    mock_chat = Object.new
    RubyLLM.stub :chat, mock_chat do
      result = AI.chat
      assert_equal mock_chat, result
    end
  end
end

class AIExtensionLoadedTest < Minitest::Test
  AI = DurableWorkflow::Extensions::AI

  def test_ai_extension_registers_when_required
    # Re-register since other tests may have reset the registry
    DurableWorkflow::Extensions.register(:ai, AI::Extension) unless DurableWorkflow::Extensions.loaded?(:ai)

    assert_equal "ai", AI::Extension.extension_name
    assert_equal AI::Extension, DurableWorkflow::Extensions[:ai]
  end
end
