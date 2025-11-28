# frozen_string_literal: true

require "test_helper"

class ApprovalExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def build_approval_step(prompt: "Please approve", context: nil, approvers: nil, timeout: nil, on_reject: nil, on_timeout: nil, next_step: "approved_next")
    config = { prompt: prompt }
    config[:context] = context if context
    config[:approvers] = approvers if approvers
    config[:timeout] = timeout if timeout
    config[:on_reject] = on_reject if on_reject
    config[:on_timeout] = on_timeout if on_timeout

    DurableWorkflow::Core::StepDef.new(
      id: "approval_step",
      type: "approval",
      config: DurableWorkflow::Core::ApprovalConfig.new(config),
      next_step: next_step
    )
  end

  def test_approval_halts_with_approval_data
    step = build_approval_step(prompt: "Approve this?")
    executor = DurableWorkflow::Core::Executors::Approval.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_instance_of DurableWorkflow::Core::HaltResult, outcome.result
    assert_equal :approval, outcome.result.data[:type]
    assert_equal "Approve this?", outcome.result.data[:prompt]
  end

  def test_approval_sets_resume_step_to_self
    step = build_approval_step
    executor = DurableWorkflow::Core::Executors::Approval.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal "approval_step", outcome.result.resume_step
  end

  def test_approval_includes_approvers_list
    step = build_approval_step(approvers: ["admin", "manager"])
    executor = DurableWorkflow::Core::Executors::Approval.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal ["admin", "manager"], outcome.result.data[:approvers]
  end

  def test_approval_continues_when_approved
    step = build_approval_step(next_step: "after_approval")
    executor = DurableWorkflow::Core::Executors::Approval.new(step)
    state = build_state(ctx: { approved: true })

    outcome = executor.call(state)

    assert_instance_of DurableWorkflow::Core::ContinueResult, outcome.result
    assert_equal "after_approval", outcome.result.next_step
  end

  def test_approval_removes_approved_flag_from_ctx
    step = build_approval_step
    executor = DurableWorkflow::Core::Executors::Approval.new(step)
    state = build_state(ctx: { approved: true, other_data: "keep" })

    outcome = executor.call(state)

    refute outcome.state.ctx.key?(:approved)
    assert_equal "keep", outcome.state.ctx[:other_data]
  end

  def test_approval_goes_to_on_reject_when_rejected
    step = build_approval_step(on_reject: "rejection_handler")
    executor = DurableWorkflow::Core::Executors::Approval.new(step)
    state = build_state(ctx: { approved: false })

    outcome = executor.call(state)

    assert_instance_of DurableWorkflow::Core::ContinueResult, outcome.result
    assert_equal "rejection_handler", outcome.result.next_step
  end

  def test_approval_raises_when_rejected_without_handler
    step = build_approval_step(on_reject: nil)
    executor = DurableWorkflow::Core::Executors::Approval.new(step)
    state = build_state(ctx: { approved: false })

    assert_raises(DurableWorkflow::ExecutionError) do
      executor.call(state)
    end
  end

  def test_approval_resolves_prompt_reference
    step = build_approval_step(prompt: "$message")
    executor = DurableWorkflow::Core::Executors::Approval.new(step)
    state = build_state(ctx: { message: "Dynamic prompt" })

    outcome = executor.call(state)

    assert_equal "Dynamic prompt", outcome.result.data[:prompt]
  end
end
