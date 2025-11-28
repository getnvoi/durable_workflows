# frozen_string_literal: true

require "test_helper"

class TypesStepDefTest < Minitest::Test
  def test_step_def_can_be_created
    step = DurableWorkflow::Core::StepDef.new(
      id: "step1",
      type: "assign",
      config: { set: { x: 1 } }
    )

    assert_equal "step1", step.id
    assert_equal "assign", step.type
  end

  def test_step_def_type_is_string
    step = DurableWorkflow::Core::StepDef.new(
      id: "s",
      type: "custom_type",
      config: {}
    )

    assert_instance_of String, step.type
    assert_equal "custom_type", step.type
  end

  def test_terminal_returns_true_for_end
    step = DurableWorkflow::Core::StepDef.new(
      id: "s",
      type: "end",
      config: {}
    )

    assert step.terminal?
  end

  def test_terminal_returns_false_for_other_types
    step = DurableWorkflow::Core::StepDef.new(
      id: "s",
      type: "assign",
      config: {}
    )

    refute step.terminal?
  end
end
