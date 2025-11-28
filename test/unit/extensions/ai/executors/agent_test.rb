# frozen_string_literal: true

require "test_helper"
require "durable_workflow/extensions/ai"
require_relative "../../../../support/mock_provider"

class AgentExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers
  AI = DurableWorkflow::Extensions::AI

  def setup
    @workflow = build_ai_workflow
    DurableWorkflow.register(@workflow)
    AI::ToolRegistry.reset!
    AI::GeneratedTools.constants.each { |c| AI::GeneratedTools.send(:remove_const, c) }
  end

  def teardown
    DurableWorkflow.registry.delete(@workflow.id)
    AI::ToolRegistry.reset!
  end

  def test_registered_as_agent
    assert DurableWorkflow::Core::Executors::Registry.registered?("agent")
  end

  def test_raises_when_agent_not_found
    step = build_agent_step(agent_id: "unknown")
    executor = AI::Executors::Agent.new(step)
    state = build_state(workflow_id: @workflow.id)

    error = assert_raises(DurableWorkflow::ExecutionError) do
      executor.call(state)
    end

    assert_match(/Agent not found/, error.message)
  end

  def test_resolves_prompt_from_state
    mock_chat = AI::MockChat.new
    mock_chat.queue_response(content: "Hello!")

    step = build_agent_step(agent_id: "test_agent", prompt: "$message")
    executor = AI::Executors::Agent.new(step)
    state = build_state(workflow_id: @workflow.id, ctx: { message: "Hi there" })

    AI.stub :chat, mock_chat do
      executor.call(state)
    end

    assert_equal 1, mock_chat.call_count
  end

  def test_stores_response_in_output
    mock_chat = AI::MockChat.new
    mock_chat.queue_response(content: "Agent response here")

    step = build_agent_step(agent_id: "test_agent", output: :agent_response)
    executor = AI::Executors::Agent.new(step)
    state = build_state(workflow_id: @workflow.id)

    outcome = nil
    AI.stub :chat, mock_chat do
      outcome = executor.call(state)
    end

    assert_equal "Agent response here", outcome.state.ctx[:agent_response]
  end

  def test_calls_chat_ask
    mock_chat = AI::MockChat.new
    mock_chat.queue_response(content: "Response")

    step = build_agent_step(agent_id: "test_agent")
    executor = AI::Executors::Agent.new(step)
    state = build_state(workflow_id: @workflow.id)

    AI.stub :chat, mock_chat do
      executor.call(state)
    end

    assert_equal 1, mock_chat.call_count
  end

  def test_handles_tool_calls
    # Register the tool first
    tool_def = AI::ToolDef.new(
      id: "test_tool",
      description: "Test tool",
      parameters: [AI::ToolParam.new(name: "query", required: true)],
      service: "MockToolService",
      method_name: "test_tool"
    )
    AI::ToolRegistry.register_from_def(tool_def)

    mock_chat = AI::MockChat.new
    # Queue tool call response, then final response
    mock_chat.queue_tool_call(id: "tc_1", name: "test_tool", arguments: { query: "test" })
    mock_chat.queue_response(content: "Final answer")

    step = build_agent_step(agent_id: "agent_with_tools")
    executor = AI::Executors::Agent.new(step)
    state = build_state(workflow_id: @workflow.id)

    outcome = nil
    AI.stub :chat, mock_chat do
      outcome = executor.call(state)
    end

    assert_equal "Final answer", outcome.state.ctx[:response]
    assert_equal 2, mock_chat.call_count
  end

  def test_respects_max_iterations
    # Register the tool first
    tool_def = AI::ToolDef.new(
      id: "test_tool",
      description: "Test tool",
      parameters: [],
      service: "MockToolService",
      method_name: "test_tool"
    )
    AI::ToolRegistry.register_from_def(tool_def)

    mock_chat = AI::MockChat.new
    # Queue endless tool calls
    11.times do
      mock_chat.queue_tool_call(id: "tc", name: "test_tool", arguments: {})
    end

    step = build_agent_step(agent_id: "agent_with_tools")
    executor = AI::Executors::Agent.new(step)
    state = build_state(workflow_id: @workflow.id)

    error = assert_raises(DurableWorkflow::ExecutionError) do
      AI.stub :chat, mock_chat do
        executor.call(state)
      end
    end

    assert_match(/exceeded max iterations/, error.message)
  end

  def test_handles_handoff_tool_call
    mock_chat = AI::MockChat.new
    mock_chat.queue_tool_call(id: "tc_1", name: "transfer_to_billing", arguments: {})
    mock_chat.queue_response(content: "Transferred")

    step = build_agent_step(agent_id: "agent_with_handoffs")
    executor = AI::Executors::Agent.new(step)
    state = build_state(workflow_id: @workflow.id)

    outcome = nil
    AI.stub :chat, mock_chat do
      outcome = executor.call(state)
    end

    assert_equal "billing", outcome.state.ctx[:_handoff_to]
  end

  private

    def build_ai_workflow
      # Create a mock tool service
      Object.const_set(:MockToolService, Class.new do
        def self.test_tool(query: nil)
          "Tool result for: #{query}"
        end
      end) unless defined?(::MockToolService)

      DurableWorkflow::Core::WorkflowDef.new(
        id: "agent_test_wf",
        name: "Agent Test",
        steps: [
          DurableWorkflow::Core::StepDef.new(
            id: "start",
            type: "start",
            config: DurableWorkflow::Core::StartConfig.new
          )
        ],
        extensions: {
          ai: {
            agents: {
              "test_agent" => AI::AgentDef.new(
                id: "test_agent",
                model: "gpt-4",
                instructions: "You are helpful"
              ),
              "agent_with_tools" => AI::AgentDef.new(
                id: "agent_with_tools",
                model: "gpt-4",
                tools: ["test_tool"]
              ),
              "agent_with_handoffs" => AI::AgentDef.new(
                id: "agent_with_handoffs",
                model: "gpt-4",
                handoffs: [
                  AI::HandoffDef.new(agent_id: "billing", description: "Transfer to billing")
                ]
              )
            },
            tools: {
              "test_tool" => AI::ToolDef.new(
                id: "test_tool",
                description: "Test tool",
                parameters: [AI::ToolParam.new(name: "query", required: true)],
                service: "MockToolService",
                method_name: "test_tool"
              )
            }
          }
        }
      )
    end

    def build_agent_step(agent_id:, prompt: "Hello", output: :response)
      DurableWorkflow::Core::StepDef.new(
        id: "agent",
        type: "agent",
        config: AI::AgentConfig.new(
          agent_id: agent_id,
          prompt: prompt,
          output: output
        ),
        next_step: "next"
      )
    end
end
