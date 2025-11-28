# frozen_string_literal: true

require "test_helper"

class HaltExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def build_halt_step(reason: "Halted", data: nil, resume_step: nil, next_step: "next")
    config = { reason: reason }
    config[:data] = data if data
    config[:resume_step] = resume_step if resume_step

    DurableWorkflow::Core::StepDef.new(
      id: "halt_step",
      type: "halt",
      config: DurableWorkflow::Core::HaltConfig.new(config),
      next_step: next_step
    )
  end

  def test_halt_returns_halt_result
    step = build_halt_step(reason: "Manual stop")
    executor = DurableWorkflow::Core::Executors::Halt.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_instance_of DurableWorkflow::Core::HaltResult, outcome.result
    assert_equal "Manual stop", outcome.result.data[:reason]
  end

  def test_halt_includes_halted_at_timestamp
    step = build_halt_step
    executor = DurableWorkflow::Core::Executors::Halt.new(step)
    state = build_state

    outcome = executor.call(state)

    assert outcome.result.data.key?(:halted_at)
  end

  def test_halt_resolves_reason_reference
    step = build_halt_step(reason: "$message")
    executor = DurableWorkflow::Core::Executors::Halt.new(step)
    state = build_state(ctx: { message: "Waiting for approval" })

    outcome = executor.call(state)

    assert_equal "Waiting for approval", outcome.result.data[:reason]
  end

  def test_halt_includes_extra_data
    step = build_halt_step(data: { user_id: 123 })
    executor = DurableWorkflow::Core::Executors::Halt.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal 123, outcome.result.data[:user_id]
  end

  def test_halt_sets_resume_step
    step = build_halt_step(resume_step: "resume_here")
    executor = DurableWorkflow::Core::Executors::Halt.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal "resume_here", outcome.result.resume_step
  end

  def test_halt_defaults_resume_to_next_step
    step = build_halt_step(next_step: "default_next")
    executor = DurableWorkflow::Core::Executors::Halt.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal "default_next", outcome.result.resume_step
  end
end
