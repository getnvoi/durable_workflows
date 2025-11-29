# frozen_string_literal: true

require "test_helper"

class ValidatorTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def build_workflow(id: "test_workflow", steps: [], inputs: [])
    DurableWorkflow::Core::WorkflowDef.new(
      id: id,
      name: "Test Workflow",
      version: "1.0",
      steps: steps,
      inputs: inputs
    )
  end

  def build_step(id:, type:, config: nil, next_step: nil)
    config ||= case type
    when "start" then DurableWorkflow::Core::StartConfig.new
    when "end" then DurableWorkflow::Core::EndConfig.new
    when "assign" then DurableWorkflow::Core::AssignConfig.new(set: {})
    else DurableWorkflow::Core::AssignConfig.new(set: {})
    end

    DurableWorkflow::Core::StepDef.new(
      id: id,
      type: type,
      config: config,
      next_step: next_step
    )
  end

  # Test: Unique IDs

  def test_validates_unique_step_ids
    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "dup"),
      build_step(id: "dup", type: "assign", next_step: "end"),
      build_step(id: "dup", type: "assign", next_step: "end"),
      build_step(id: "end", type: "end")
    ])

    error = assert_raises(DurableWorkflow::ValidationError) do
      DurableWorkflow::Core::Validator.validate!(workflow)
    end

    assert_match(/Duplicate step IDs.*dup/, error.message)
  end

  # Test: Step Types Registered

  def test_validates_step_types_are_registered
    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "unknown"),
      build_step(id: "unknown", type: "nonexistent_type", next_step: "end"),
      build_step(id: "end", type: "end")
    ])

    error = assert_raises(DurableWorkflow::ValidationError) do
      DurableWorkflow::Core::Validator.validate!(workflow)
    end

    assert_match(/Unknown step type 'nonexistent_type'/, error.message)
  end

  # Test: References Exist

  def test_validates_next_step_references_exist
    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "missing"),
      build_step(id: "end", type: "end")
    ])

    error = assert_raises(DurableWorkflow::ValidationError) do
      DurableWorkflow::Core::Validator.validate!(workflow)
    end

    assert_match(/references unknown step 'missing'/, error.message)
  end

  def test_allows_finished_as_next_step
    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "end"),
      build_step(id: "end", type: "end", next_step: "__FINISHED__")
    ])

    # Should not raise
    assert DurableWorkflow::Core::Validator.validate!(workflow)
  end

  # Test: Reachability

  def test_detects_unreachable_steps
    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "end"),
      build_step(id: "orphan", type: "assign", next_step: "end"),
      build_step(id: "end", type: "end")
    ])

    error = assert_raises(DurableWorkflow::ValidationError) do
      DurableWorkflow::Core::Validator.validate!(workflow)
    end

    assert_match(/Unreachable steps.*orphan/, error.message)
  end

  # Test: Valid Workflow

  def test_valid_simple_workflow
    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "process"),
      build_step(id: "process", type: "assign", next_step: "end"),
      build_step(id: "end", type: "end")
    ])

    assert DurableWorkflow::Core::Validator.validate!(workflow)
  end

  def test_valid_predicate
    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "end"),
      build_step(id: "end", type: "end")
    ])

    assert DurableWorkflow::Core::Validator.new(workflow).valid?
  end

  def test_valid_predicate_returns_false_for_invalid
    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "missing")
    ])

    refute DurableWorkflow::Core::Validator.new(workflow).valid?
  end

  # Test: Router References

  def test_validates_router_route_targets
    routes = [
      DurableWorkflow::Core::Route.new(field: "x", op: "eq", value: 1, target: "missing")
    ]
    router_config = DurableWorkflow::Core::RouterConfig.new(routes: routes, default: "end")

    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "router"),
      DurableWorkflow::Core::StepDef.new(id: "router", type: "router", config: router_config, next_step: nil),
      build_step(id: "end", type: "end")
    ])

    error = assert_raises(DurableWorkflow::ValidationError) do
      DurableWorkflow::Core::Validator.validate!(workflow)
    end

    assert_match(/references unknown step 'missing'/, error.message)
  end

  def test_validates_router_default
    routes = [
      DurableWorkflow::Core::Route.new(field: "x", op: "eq", value: 1, target: "end")
    ]
    router_config = DurableWorkflow::Core::RouterConfig.new(routes: routes, default: "missing_default")

    workflow = build_workflow(steps: [
      build_step(id: "start", type: "start", next_step: "router"),
      DurableWorkflow::Core::StepDef.new(id: "router", type: "router", config: router_config, next_step: nil),
      build_step(id: "end", type: "end")
    ])

    error = assert_raises(DurableWorkflow::ValidationError) do
      DurableWorkflow::Core::Validator.validate!(workflow)
    end

    assert_match(/references unknown step 'missing_default'/, error.message)
  end

  # Test: Empty Workflow

  def test_handles_empty_workflow
    workflow = build_workflow(steps: [])

    # Empty workflow should be valid (no steps to validate)
    assert DurableWorkflow::Core::Validator.validate!(workflow)
  end

  # Test: Loop Body Variable Scope

  def test_loop_as_variable_is_available_inside_loop_body
    # The `as: recipient` declares $recipient inside the loop's do: block
    inner_call = DurableWorkflow::Core::StepDef.new(
      id: "create_invite",
      type: "call",
      config: DurableWorkflow::Core::CallConfig.new(
        service: "InviteService",
        method_name: "create",
        input: { invitee_id: "$recipient.id" }  # References loop variable
      )
    )

    loop_config = DurableWorkflow::Core::LoopConfig.new(
      over: "$input.recipients",
      as: :recipient,
      do: [inner_call],
      output: :invites
    )

    workflow = build_workflow(
      steps: [
        build_step(id: "start", type: "start", next_step: "loop"),
        DurableWorkflow::Core::StepDef.new(id: "loop", type: "loop", config: loop_config, next_step: "end"),
        build_step(id: "end", type: "end")
      ],
      inputs: [DurableWorkflow::Core::InputDef.new(name: "recipients", type: "array")]
    )

    # Should not raise - $recipient is valid inside the loop body
    assert DurableWorkflow::Core::Validator.validate!(workflow)
  end

  def test_loop_index_variable_is_available_inside_loop_body
    # The `index_as: idx` declares $idx inside the loop's do: block
    inner_assign = DurableWorkflow::Core::StepDef.new(
      id: "log_index",
      type: "assign",
      config: DurableWorkflow::Core::AssignConfig.new(
        set: { current_index: "$idx" }  # References index variable
      )
    )

    loop_config = DurableWorkflow::Core::LoopConfig.new(
      over: "$input.items",
      as: :item,
      index_as: :idx,
      do: [inner_assign],
      output: :results
    )

    workflow = build_workflow(
      steps: [
        build_step(id: "start", type: "start", next_step: "loop"),
        DurableWorkflow::Core::StepDef.new(id: "loop", type: "loop", config: loop_config, next_step: "end"),
        build_step(id: "end", type: "end")
      ],
      inputs: [DurableWorkflow::Core::InputDef.new(name: "items", type: "array")]
    )

    # Should not raise - $idx is valid inside the loop body
    assert DurableWorkflow::Core::Validator.validate!(workflow)
  end

  def test_loop_variable_not_available_outside_loop
    # $recipient should NOT be available after the loop
    loop_config = DurableWorkflow::Core::LoopConfig.new(
      over: "$input.recipients",
      as: :recipient,
      do: [],
      output: :invites
    )

    end_config = DurableWorkflow::Core::EndConfig.new(
      result: { last_recipient: "$recipient.id" }  # Invalid - $recipient out of scope
    )

    workflow = build_workflow(
      steps: [
        build_step(id: "start", type: "start", next_step: "loop"),
        DurableWorkflow::Core::StepDef.new(id: "loop", type: "loop", config: loop_config, next_step: "end"),
        DurableWorkflow::Core::StepDef.new(id: "end", type: "end", config: end_config)
      ],
      inputs: [DurableWorkflow::Core::InputDef.new(name: "recipients", type: "array")]
    )

    error = assert_raises(DurableWorkflow::ValidationError) do
      DurableWorkflow::Core::Validator.validate!(workflow)
    end

    assert_match(/references '\$recipient.id' but 'recipient' not set/, error.message)
  end

  def test_loop_output_is_available_after_loop
    # $invites (the loop output) should be available after the loop
    loop_config = DurableWorkflow::Core::LoopConfig.new(
      over: "$input.recipients",
      as: :recipient,
      do: [],
      output: :invites
    )

    end_config = DurableWorkflow::Core::EndConfig.new(
      result: { all_invites: "$invites" }  # Valid - $invites set by loop output
    )

    workflow = build_workflow(
      steps: [
        build_step(id: "start", type: "start", next_step: "loop"),
        DurableWorkflow::Core::StepDef.new(id: "loop", type: "loop", config: loop_config, next_step: "end"),
        DurableWorkflow::Core::StepDef.new(id: "end", type: "end", config: end_config)
      ],
      inputs: [DurableWorkflow::Core::InputDef.new(name: "recipients", type: "array")]
    )

    # Should not raise - $invites is set by the loop's output
    assert DurableWorkflow::Core::Validator.validate!(workflow)
  end
end
