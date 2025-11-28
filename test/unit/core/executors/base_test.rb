# frozen_string_literal: true

require "test_helper"

class BaseExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  class TestExecutor < DurableWorkflow::Core::Executors::Base
    def call(state)
      continue(state, output: { done: true })
    end
  end

  class TestExecutorWithStore < DurableWorkflow::Core::Executors::Base
    def call(state)
      new_state = store(state, "result", { value: 42 })
      continue(new_state, output: { stored: true })
    end
  end

  def build_step(id: "test_step", type: "assign", config: {}, next_step: "next")
    DurableWorkflow::Core::StepDef.new(
      id: id,
      type: type,
      config: DurableWorkflow::Core::AssignConfig.new(config),
      next_step: next_step
    )
  end

  def test_initialize_sets_step_and_config
    step = build_step
    executor = TestExecutor.new(step)

    assert_equal step, executor.step
    assert_equal step.config, executor.config
  end

  def test_call_raises_not_implemented_on_base
    step = build_step
    executor = DurableWorkflow::Core::Executors::Base.new(step)

    assert_raises(NotImplementedError) { executor.call(build_state) }
  end

  def test_continue_returns_step_outcome_with_continue_result
    step = build_step(next_step: "next_step")
    executor = TestExecutor.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_instance_of DurableWorkflow::Core::StepOutcome, outcome
    assert_instance_of DurableWorkflow::Core::ContinueResult, outcome.result
    assert_equal "next_step", outcome.result.next_step
    assert_equal({ done: true }, outcome.result.output)
  end

  def test_resolve_delegates_to_resolver
    step = build_step
    executor = TestExecutor.new(step)
    state = build_state(ctx: { name: "test" })

    result = executor.send(:resolve, state, "$name")
    assert_equal "test", result
  end

  def test_store_returns_new_state_with_updated_ctx
    step = build_step
    executor = TestExecutorWithStore.new(step)
    state = build_state

    outcome = executor.call(state)

    # Original state unchanged
    assert_nil state.ctx[:result]
    # New state has the stored value
    assert_equal({ value: 42 }, outcome.state.ctx[:result])
  end

  def test_store_with_nil_key_returns_unchanged_state
    step = build_step
    executor = TestExecutor.new(step)
    state = build_state

    new_state = executor.send(:store, state, nil, "value")
    assert_equal state, new_state
  end

  def test_halt_returns_step_outcome_with_halt_result
    step = build_step(next_step: "resume_step")
    executor = TestExecutor.new(step)
    state = build_state

    outcome = executor.send(:halt, state, data: { reason: "waiting" })

    assert_instance_of DurableWorkflow::Core::StepOutcome, outcome
    assert_instance_of DurableWorkflow::Core::HaltResult, outcome.result
    assert_equal({ reason: "waiting" }, outcome.result.data)
    assert_equal "resume_step", outcome.result.resume_step
  end

  def test_halt_with_custom_resume_step
    step = build_step(next_step: "default_next")
    executor = TestExecutor.new(step)
    state = build_state

    outcome = executor.send(:halt, state, data: {}, resume_step: "custom_resume")

    assert_equal "custom_resume", outcome.result.resume_step
  end
end
