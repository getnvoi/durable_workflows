# frozen_string_literal: true

require "test_helper"
require "durable_workflow/extensions/ai"

class HandoffExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers
  AI = DurableWorkflow::Extensions::AI

  def setup
    @workflow = build_ai_workflow
    DurableWorkflow.register(@workflow)
  end

  def teardown
    DurableWorkflow.registry.delete(@workflow.id)
  end

  def test_registered_as_handoff
    assert DurableWorkflow::Core::Executors::Registry.registered?("handoff")
  end

  def test_uses_config_to_as_target
    step = build_handoff_step(to: "billing")
    executor = AI::Executors::Handoff.new(step)
    state = build_state(workflow_id: @workflow.id)

    outcome = executor.call(state)

    assert_equal "billing", outcome.state.ctx[:_current_agent]
  end

  def test_falls_back_to_ctx_handoff_to
    step = build_handoff_step(to: nil)
    executor = AI::Executors::Handoff.new(step)
    state = build_state(workflow_id: @workflow.id, ctx: { _handoff_to: "billing" })

    outcome = executor.call(state)

    assert_equal "billing", outcome.state.ctx[:_current_agent]
  end

  def test_raises_when_no_target
    step = build_handoff_step(to: nil)
    executor = AI::Executors::Handoff.new(step)
    state = build_state(workflow_id: @workflow.id)

    error = assert_raises(DurableWorkflow::ExecutionError) do
      executor.call(state)
    end

    assert_match(/No handoff target/, error.message)
  end

  def test_raises_when_agent_not_found
    step = build_handoff_step(to: "unknown_agent")
    executor = AI::Executors::Handoff.new(step)
    state = build_state(workflow_id: @workflow.id)

    error = assert_raises(DurableWorkflow::ExecutionError) do
      executor.call(state)
    end

    assert_match(/Agent not found/, error.message)
  end

  def test_sets_handoff_context
    step = build_handoff_step(to: "billing", from: "triage", reason: "Billing question")
    executor = AI::Executors::Handoff.new(step)
    state = build_state(workflow_id: @workflow.id)

    outcome = executor.call(state)
    ctx = outcome.state.ctx[:_handoff_context]

    assert_equal "triage", ctx[:from]
    assert_equal "billing", ctx[:to]
    assert_equal "Billing question", ctx[:reason]
    assert ctx[:timestamp]
  end

  def test_removes_handoff_to_from_ctx
    step = build_handoff_step(to: "billing")
    executor = AI::Executors::Handoff.new(step)
    state = build_state(workflow_id: @workflow.id, ctx: { _handoff_to: "billing" })

    outcome = executor.call(state)

    refute outcome.state.ctx.key?(:_handoff_to)
  end

  private

    def build_ai_workflow
      DurableWorkflow::Core::WorkflowDef.new(
        id: "handoff_test_wf",
        name: "Handoff Test",
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
              "triage" => AI::AgentDef.new(id: "triage", model: "gpt-4"),
              "billing" => AI::AgentDef.new(id: "billing", model: "gpt-4")
            },
            tools: {}
          }
        }
      )
    end

    def build_handoff_step(to: nil, from: nil, reason: nil)
      DurableWorkflow::Core::StepDef.new(
        id: "handoff",
        type: "handoff",
        config: AI::HandoffConfig.new(to: to, from: from, reason: reason),
        next_step: "next"
      )
    end
end
