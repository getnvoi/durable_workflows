# frozen_string_literal: true

require "test_helper"

class SyncRunnerTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def setup
    @store = TestStore.new
  end

  def teardown
    @store.clear!
  end

  def build_simple_workflow
    DurableWorkflow::Core::WorkflowDef.new(
      id: "test_workflow",
      name: "Test",
      version: "1.0",
      steps: [
        DurableWorkflow::Core::StepDef.new(
          id: "start",
          type: "start",
          config: DurableWorkflow::Core::StartConfig.new,
          next_step: "end"
        ),
        DurableWorkflow::Core::StepDef.new(
          id: "end",
          type: "end",
          config: DurableWorkflow::Core::EndConfig.new(result: "$input"),
          next_step: nil
        )
      ]
    )
  end

  def build_halt_workflow
    DurableWorkflow::Core::WorkflowDef.new(
      id: "halt_workflow",
      name: "Halt Test",
      version: "1.0",
      steps: [
        DurableWorkflow::Core::StepDef.new(
          id: "start",
          type: "start",
          config: DurableWorkflow::Core::StartConfig.new,
          next_step: "halt"
        ),
        DurableWorkflow::Core::StepDef.new(
          id: "halt",
          type: "halt",
          config: DurableWorkflow::Core::HaltConfig.new(reason: "Waiting"),
          next_step: "end"
        ),
        DurableWorkflow::Core::StepDef.new(
          id: "end",
          type: "end",
          config: DurableWorkflow::Core::EndConfig.new(result: { response: "$response" }),
          next_step: nil
        )
      ]
    )
  end

  def test_requires_store
    workflow = build_simple_workflow

    assert_raises(DurableWorkflow::ConfigError) do
      DurableWorkflow::Runners::Sync.new(workflow)
    end
  end

  def test_run_returns_completed_result
    workflow = build_simple_workflow
    runner = DurableWorkflow::Runners::Sync.new(workflow, store: @store)

    result = runner.run(input: { name: "test" })

    assert_equal :completed, result.status
    assert_equal({ name: "test" }, result.output)
  end

  def test_run_with_custom_execution_id
    workflow = build_simple_workflow
    runner = DurableWorkflow::Runners::Sync.new(workflow, store: @store)

    result = runner.run(execution_id: "custom-123")

    assert_equal "custom-123", result.execution_id
  end

  def test_run_halts_when_halt_step_encountered
    workflow = build_halt_workflow
    runner = DurableWorkflow::Runners::Sync.new(workflow, store: @store)

    result = runner.run

    assert_equal :halted, result.status
    assert_equal "Waiting", result.halt.data[:reason]
  end

  def test_resume_continues_halted_workflow
    workflow = build_halt_workflow
    runner = DurableWorkflow::Runners::Sync.new(workflow, store: @store)

    halted = runner.run
    result = runner.resume(halted.execution_id, response: "user input")

    assert_equal :completed, result.status
    assert_equal({ response: "user input" }, result.output)
  end

  def test_run_until_complete_without_block
    workflow = build_halt_workflow
    runner = DurableWorkflow::Runners::Sync.new(workflow, store: @store)

    result = runner.run_until_complete

    # Without block, halts when halt encountered
    assert_equal :halted, result.status
  end

  def test_run_until_complete_with_block
    workflow = build_halt_workflow
    runner = DurableWorkflow::Runners::Sync.new(workflow, store: @store)

    result = runner.run_until_complete do |halt|
      assert_equal "Waiting", halt.data[:reason]
      "auto response"
    end

    assert_equal :completed, result.status
    assert_equal({ response: "auto response" }, result.output)
  end
end
