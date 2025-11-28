# frozen_string_literal: true

require "test_helper"

class StartExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def build_start_step(next_step: "step1", config: {})
    DurableWorkflow::Core::StepDef.new(
      id: "start",
      type: "start",
      config: DurableWorkflow::Core::StartConfig.new(config),
      next_step: next_step
    )
  end

  def test_start_stores_input_in_ctx
    step = build_start_step
    executor = DurableWorkflow::Core::Executors::Start.new(step)
    state = build_state(input: { name: "test" })

    outcome = executor.call(state)

    assert_equal({ name: "test" }, outcome.state.ctx[:input])
    assert_equal "step1", outcome.result.next_step
  end

  def test_start_continues_to_next_step
    step = build_start_step(next_step: "process")
    executor = DurableWorkflow::Core::Executors::Start.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_instance_of DurableWorkflow::Core::ContinueResult, outcome.result
    assert_equal "process", outcome.result.next_step
  end

  def test_start_with_empty_input
    step = build_start_step
    executor = DurableWorkflow::Core::Executors::Start.new(step)
    state = build_state(input: {})

    outcome = executor.call(state)

    assert_equal({}, outcome.state.ctx[:input])
  end
end
