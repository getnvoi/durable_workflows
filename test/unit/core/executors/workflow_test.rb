# frozen_string_literal: true

require "test_helper"

class SubWorkflowExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def build_workflow_step(workflow_id:, input: nil, output: nil, timeout: nil)
    config = { workflow_id: workflow_id }
    config[:input] = input if input
    config[:output] = output if output
    config[:timeout] = timeout if timeout

    DurableWorkflow::Core::StepDef.new(
      id: "workflow_step",
      type: "workflow",
      config: DurableWorkflow::Core::WorkflowConfig.new(config),
      next_step: "next"
    )
  end

  def test_workflow_raises_when_child_workflow_not_found
    step = build_workflow_step(workflow_id: "nonexistent")
    executor = DurableWorkflow::Core::Executors::SubWorkflow.new(step)
    state = build_state

    assert_raises(DurableWorkflow::ExecutionError) do
      executor.call(state)
    end
  end

  def test_workflow_resolves_input_references
    # Create a minimal child workflow
    child_workflow = DurableWorkflow::Core::WorkflowDef.new(
      id: "child_workflow",
      name: "Child",
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

    # Register the child workflow
    DurableWorkflow.register(child_workflow)
    # Configure store for Engine
    store = TestStore.new
    DurableWorkflow.configure { |c| c.store = store }

    step = build_workflow_step(
      workflow_id: "child_workflow",
      input: "$data",
      output: "child_result"
    )
    executor = DurableWorkflow::Core::Executors::SubWorkflow.new(step)
    state = build_state(ctx: { data: { key: "value" } })

    outcome = executor.call(state)

    assert_instance_of DurableWorkflow::Core::ContinueResult, outcome.result
    # The child workflow returns its input as result
    assert_equal({ key: "value" }, outcome.state.ctx[:child_result])
  ensure
    # Cleanup
    DurableWorkflow.registry.delete("child_workflow")
    DurableWorkflow.configure { |c| c.store = nil }
  end
end
