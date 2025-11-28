# frozen_string_literal: true

require "test_helper"

class InlineAdapterTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def setup
    @store = TestStore.new
    @workflow = build_workflow
    DurableWorkflow.register(@workflow)
  end

  def teardown
    @store.clear!
    DurableWorkflow.registry.delete(@workflow.id)
  end

  def build_workflow
    DurableWorkflow::Core::WorkflowDef.new(
      id: "inline_test_workflow",
      name: "Inline Test",
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
          config: DurableWorkflow::Core::EndConfig.new(result: { success: true }),
          next_step: nil
        )
      ]
    )
  end

  def test_enqueue_executes_immediately
    adapter = DurableWorkflow::Runners::Adapters::Inline.new(store: @store)

    result = adapter.enqueue(
      workflow_id: @workflow.id,
      workflow_data: {},
      execution_id: "exec-1",
      action: :start,
      input: {}
    )

    assert_equal :completed, result.status
  end

  def test_perform_runs_workflow
    adapter = DurableWorkflow::Runners::Adapters::Inline.new(store: @store)

    result = adapter.perform(
      workflow_id: @workflow.id,
      workflow_data: {},
      execution_id: "exec-1",
      action: :start,
      input: {}
    )

    assert_equal :completed, result.status
    assert_equal({ success: true }, result.output)
  end

  def test_perform_updates_status_in_store
    adapter = DurableWorkflow::Runners::Adapters::Inline.new(store: @store)

    adapter.perform(
      workflow_id: @workflow.id,
      workflow_data: {},
      execution_id: "exec-1",
      action: :start,
      input: {}
    )

    execution = @store.load("exec-1")
    assert_equal :completed, execution.status
  end

  def test_perform_raises_for_unknown_workflow
    adapter = DurableWorkflow::Runners::Adapters::Inline.new(store: @store)

    assert_raises(DurableWorkflow::ExecutionError) do
      adapter.perform(
        workflow_id: "nonexistent",
        workflow_data: {},
        execution_id: "exec-1",
        action: :start
      )
    end
  end

  def test_perform_resume_action
    # First run a workflow that halts
    halt_workflow = DurableWorkflow::Core::WorkflowDef.new(
      id: "halt_inline_workflow",
      name: "Halt",
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
          config: DurableWorkflow::Core::HaltConfig.new(reason: "Wait"),
          next_step: "end"
        ),
        DurableWorkflow::Core::StepDef.new(
          id: "end",
          type: "end",
          config: DurableWorkflow::Core::EndConfig.new(result: { resumed: true }),
          next_step: nil
        )
      ]
    )
    DurableWorkflow.register(halt_workflow)

    adapter = DurableWorkflow::Runners::Adapters::Inline.new(store: @store)

    # Start workflow (halts)
    adapter.perform(
      workflow_id: halt_workflow.id,
      workflow_data: {},
      execution_id: "exec-halt",
      action: :start
    )

    # Resume workflow
    result = adapter.perform(
      workflow_id: halt_workflow.id,
      workflow_data: {},
      execution_id: "exec-halt",
      action: :resume
    )

    assert_equal :completed, result.status
    assert_equal({ resumed: true }, result.output)
  ensure
    DurableWorkflow.registry.delete("halt_inline_workflow")
  end
end
