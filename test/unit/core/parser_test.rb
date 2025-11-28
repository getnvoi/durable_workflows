# frozen_string_literal: true

require "test_helper"

class ParserTest < Minitest::Test
  def test_parse_from_hash
    yaml = {
      id: "test_workflow",
      name: "Test Workflow",
      version: "1.0",
      steps: [
        { id: "start", type: "start", next: "end" },
        { id: "end", type: "end" }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)

    assert_instance_of DurableWorkflow::Core::WorkflowDef, workflow
    assert_equal "test_workflow", workflow.id
    assert_equal "Test Workflow", workflow.name
    assert_equal 2, workflow.steps.size
  end

  def test_parse_from_yaml_string
    yaml_string = <<~YAML
      id: yaml_workflow
      name: YAML Workflow
      version: "1.0"
      steps:
        - id: start
          type: start
          next: end
        - id: end
          type: end
    YAML

    workflow = DurableWorkflow::Core::Parser.parse(yaml_string)

    assert_equal "yaml_workflow", workflow.id
    assert_equal "YAML Workflow", workflow.name
  end

  def test_parse_with_inputs
    yaml = {
      id: "with_inputs",
      name: "With Inputs",
      inputs: {
        name: { type: "string", required: true },
        count: { type: "integer", required: false, default: 0 }
      },
      steps: [
        { id: "start", type: "start", next: "end" },
        { id: "end", type: "end" }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)

    assert_equal 2, workflow.inputs.size

    name_input = workflow.inputs.find { _1.name == "name" }
    assert_equal "string", name_input.type
    assert name_input.required

    count_input = workflow.inputs.find { _1.name == "count" }
    assert_equal "integer", count_input.type
    refute count_input.required
    assert_equal 0, count_input.default
  end

  def test_parse_assign_step
    yaml = {
      id: "assign_test",
      name: "Assign Test",
      steps: [
        { id: "start", type: "start", next: "assign" },
        { id: "assign", type: "assign", set: { counter: 0, name: "test" }, next: "end" },
        { id: "end", type: "end" }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)

    assign_step = workflow.find_step("assign")
    assert_equal({ counter: 0, name: "test" }, assign_step.config.set)
  end

  def test_parse_call_step
    yaml = {
      id: "call_test",
      name: "Call Test",
      steps: [
        { id: "start", type: "start", next: "call" },
        {
          id: "call",
          type: "call",
          service: "MyService",
          method: "process",
          input: "$data",
          output: "result",
          next: "end"
        },
        { id: "end", type: "end" }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)

    call_step = workflow.find_step("call")
    assert_equal "MyService", call_step.config.service
    assert_equal "process", call_step.config.method_name
    assert_equal "$data", call_step.config.input
    assert_equal :result, call_step.config.output
  end

  def test_parse_router_step
    yaml = {
      id: "router_test",
      name: "Router Test",
      steps: [
        { id: "start", type: "start", next: "router" },
        {
          id: "router",
          type: "router",
          routes: [
            { when: { field: "status", op: "eq", value: "approved" }, then: "approve" },
            { when: { field: "status", op: "eq", value: "rejected" }, then: "reject" }
          ],
          default: "unknown"
        },
        { id: "approve", type: "end" },
        { id: "reject", type: "end" },
        { id: "unknown", type: "end" }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)

    router_step = workflow.find_step("router")
    assert_equal 2, router_step.config.routes.size
    assert_equal "status", router_step.config.routes[0].field
    assert_equal "eq", router_step.config.routes[0].op
    assert_equal "approved", router_step.config.routes[0].value
    assert_equal "approve", router_step.config.routes[0].target
    assert_equal "unknown", router_step.config.default
  end

  def test_parse_loop_step_with_over
    yaml = {
      id: "loop_test",
      name: "Loop Test",
      steps: [
        { id: "start", type: "start", next: "loop" },
        {
          id: "loop",
          type: "loop",
          over: "$items",
          as: "item",
          do: [
            { id: "process", type: "assign", set: { x: "$item" } }
          ],
          output: "results",
          next: "end"
        },
        { id: "end", type: "end" }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)

    loop_step = workflow.find_step("loop")
    assert_equal "$items", loop_step.config.over
    assert_equal :item, loop_step.config.as
    assert_equal 1, loop_step.config.do.size
    assert_equal "process", loop_step.config.do.first.id
  end

  def test_parse_loop_step_with_while
    yaml = {
      id: "while_test",
      name: "While Test",
      steps: [
        { id: "start", type: "start", next: "loop" },
        {
          id: "loop",
          type: "loop",
          while: { field: "counter", op: "lt", value: 10 },
          do: [
            { id: "increment", type: "assign", set: { counter: 1 } }
          ],
          output: "results",
          next: "end"
        },
        { id: "end", type: "end" }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)

    loop_step = workflow.find_step("loop")
    assert_instance_of DurableWorkflow::Core::Condition, loop_step.config.while
    assert_equal "counter", loop_step.config.while.field
    assert_equal "lt", loop_step.config.while.op
    assert_equal 10, loop_step.config.while.value
  end

  def test_parse_parallel_step
    yaml = {
      id: "parallel_test",
      name: "Parallel Test",
      steps: [
        { id: "start", type: "start", next: "parallel" },
        {
          id: "parallel",
          type: "parallel",
          branches: [
            { id: "branch1", type: "assign", set: { a: 1 } },
            { id: "branch2", type: "assign", set: { b: 2 } }
          ],
          wait: "all",
          output: "results",
          next: "end"
        },
        { id: "end", type: "end" }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)

    parallel_step = workflow.find_step("parallel")
    assert_equal 2, parallel_step.config.branches.size
    assert_equal "branch1", parallel_step.config.branches[0].id
    assert_equal "all", parallel_step.config.wait
  end

  def test_parse_halt_step
    yaml = {
      id: "halt_test",
      name: "Halt Test",
      steps: [
        { id: "start", type: "start", next: "halt" },
        {
          id: "halt",
          type: "halt",
          reason: "Waiting for input",
          next: "resume"
        },
        { id: "resume", type: "end" }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)

    halt_step = workflow.find_step("halt")
    assert_equal "Waiting for input", halt_step.config.reason
  end

  def test_parse_approval_step
    yaml = {
      id: "approval_test",
      name: "Approval Test",
      steps: [
        { id: "start", type: "start", next: "approve" },
        {
          id: "approve",
          type: "approval",
          prompt: "Please approve",
          approvers: ["admin"],
          on_reject: "rejected",
          next: "approved"
        },
        { id: "approved", type: "end" },
        { id: "rejected", type: "end" }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)

    approval_step = workflow.find_step("approve")
    assert_equal "Please approve", approval_step.config.prompt
    assert_equal ["admin"], approval_step.config.approvers
  end

  def test_parse_with_on_error
    yaml = {
      id: "error_test",
      name: "Error Test",
      steps: [
        { id: "start", type: "start", next: "risky" },
        { id: "risky", type: "assign", set: {}, next: "end", on_error: "error_handler" },
        { id: "end", type: "end" },
        { id: "error_handler", type: "end" }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)

    risky_step = workflow.find_step("risky")
    assert_equal "error_handler", risky_step.on_error
  end

  def test_parse_end_step_with_result
    yaml = {
      id: "end_result",
      name: "End Result",
      steps: [
        { id: "start", type: "start", next: "end" },
        { id: "end", type: "end", result: { status: "done", value: "$data" } }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)

    end_step = workflow.find_step("end")
    assert_equal({ status: "done", value: "$data" }, end_step.config.result)
  end

  def test_parse_invalid_hash_raises_error
    assert_raises(DurableWorkflow::Error) do
      DurableWorkflow::Core::Parser.parse(123)
    end
  end

  # Hook tests

  def test_before_parse_hook
    original_hooks = DurableWorkflow::Core::Parser.before_hooks.dup

    yaml = { id: "hook_test", name: "Hook", steps: [] }

    called = false
    DurableWorkflow::Core::Parser.before_parse do |y|
      called = true
      y[:name] = "Modified"
      y
    end

    workflow = DurableWorkflow::Core::Parser.parse(yaml)

    assert called
    assert_equal "Modified", workflow.name
  ensure
    # Clean up hook
    DurableWorkflow::Core::Parser.instance_variable_set(:@before_hooks, original_hooks)
  end

  def test_after_parse_hook
    original_hooks = DurableWorkflow::Core::Parser.after_hooks.dup

    yaml = { id: "hook_test", name: "Hook", steps: [] }

    called = false
    DurableWorkflow::Core::Parser.after_parse do |wf|
      called = true
      wf
    end

    DurableWorkflow::Core::Parser.parse(yaml)

    assert called
  ensure
    # Clean up hook
    DurableWorkflow::Core::Parser.instance_variable_set(:@after_hooks, original_hooks)
  end
end
