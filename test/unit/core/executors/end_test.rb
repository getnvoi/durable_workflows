# frozen_string_literal: true

require "test_helper"

class EndExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def build_end_step(config: {})
    DurableWorkflow::Core::StepDef.new(
      id: "end",
      type: "end",
      config: DurableWorkflow::Core::EndConfig.new(config),
      next_step: nil
    )
  end

  def test_end_sets_finished_as_next_step
    step = build_end_step
    executor = DurableWorkflow::Core::Executors::End.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal DurableWorkflow::Core::Executors::End::FINISHED, outcome.result.next_step
  end

  def test_end_stores_result_in_ctx
    step = build_end_step(config: { result: { status: "done" } })
    executor = DurableWorkflow::Core::Executors::End.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal({ status: "done" }, outcome.state.ctx[:result])
    assert_equal({ status: "done" }, outcome.result.output)
  end

  def test_end_without_result_uses_ctx
    step = build_end_step
    executor = DurableWorkflow::Core::Executors::End.new(step)
    state = build_state(ctx: { value: 42 })

    outcome = executor.call(state)

    assert_equal({ value: 42 }, outcome.result.output)
  end

  def test_end_resolves_references_in_result
    step = build_end_step(config: { result: "$data" })
    executor = DurableWorkflow::Core::Executors::End.new(step)
    state = build_state(ctx: { data: { processed: true } })

    outcome = executor.call(state)

    assert_equal({ processed: true }, outcome.result.output)
  end
end
