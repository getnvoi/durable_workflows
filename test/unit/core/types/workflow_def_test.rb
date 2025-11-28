# frozen_string_literal: true

require "test_helper"

class TypesWorkflowDefTest < Minitest::Test
  def test_input_def_can_be_created
    input = DurableWorkflow::Core::InputDef.new(name: "user_id")
    assert_equal "user_id", input.name
  end

  def test_input_def_type_defaults_to_string
    input = DurableWorkflow::Core::InputDef.new(name: "x")
    assert_equal "string", input.type
  end

  def test_input_def_required_defaults_to_true
    input = DurableWorkflow::Core::InputDef.new(name: "x")
    assert_equal true, input.required
  end

  def test_workflow_def_can_be_created
    step = DurableWorkflow::Core::StepDef.new(
      id: "start",
      type: "start",
      config: DurableWorkflow::Core::StartConfig.new
    )

    wf = DurableWorkflow::Core::WorkflowDef.new(
      id: "wf1",
      name: "Test Workflow",
      steps: [step]
    )

    assert_equal "wf1", wf.id
    assert_equal "Test Workflow", wf.name
    assert_equal 1, wf.steps.size
  end

  def test_workflow_def_version_defaults_to_1_0
    wf = DurableWorkflow::Core::WorkflowDef.new(
      id: "wf",
      name: "WF"
    )

    assert_equal "1.0", wf.version
  end

  def test_find_step_returns_correct_step
    step1 = DurableWorkflow::Core::StepDef.new(id: "s1", type: "start", config: {})
    step2 = DurableWorkflow::Core::StepDef.new(id: "s2", type: "end", config: {})

    wf = DurableWorkflow::Core::WorkflowDef.new(
      id: "wf",
      name: "WF",
      steps: [step1, step2]
    )

    assert_equal step2, wf.find_step("s2")
  end

  def test_first_step_returns_first
    step1 = DurableWorkflow::Core::StepDef.new(id: "s1", type: "start", config: {})
    step2 = DurableWorkflow::Core::StepDef.new(id: "s2", type: "end", config: {})

    wf = DurableWorkflow::Core::WorkflowDef.new(
      id: "wf",
      name: "WF",
      steps: [step1, step2]
    )

    assert_equal step1, wf.first_step
  end

  def test_step_ids_returns_array_of_ids
    step1 = DurableWorkflow::Core::StepDef.new(id: "s1", type: "start", config: {})
    step2 = DurableWorkflow::Core::StepDef.new(id: "s2", type: "end", config: {})

    wf = DurableWorkflow::Core::WorkflowDef.new(
      id: "wf",
      name: "WF",
      steps: [step1, step2]
    )

    assert_equal %w[s1 s2], wf.step_ids
  end

  def test_extensions_defaults_to_empty_hash
    wf = DurableWorkflow::Core::WorkflowDef.new(id: "wf", name: "WF")
    assert_equal({}, wf.extensions)
  end
end
