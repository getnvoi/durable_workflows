# frozen_string_literal: true

require "test_helper"

class WorkflowIntegrationTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def setup
    @store = TestStore.new
  end

  def teardown
    @store.clear!
  end

  def test_complete_workflow_from_yaml
    yaml = <<~YAML
      id: order_processing
      name: Order Processing
      version: "1.0"
      inputs:
        order_id:
          type: string
          required: true
        amount:
          type: number
          required: true
      steps:
        - id: start
          type: start
          next: validate
        - id: validate
          type: assign
          set:
            validated: true
            order_id: "$input.order_id"
            total: "$input.amount"
            requires_approval: false
          next: check_amount
        - id: check_amount
          type: router
          routes:
            - when:
                field: total
                op: gt
                value: 100
              then: high_value
            - when:
                field: total
                op: lte
                value: 100
              then: end
          default: end
        - id: high_value
          type: assign
          set:
            requires_approval: true
          next: end
        - id: end
          type: end
          result:
            order_id: "$order_id"
            validated: "$validated"
            requires_approval: "$requires_approval"
    YAML

    workflow = DurableWorkflow::Core::Parser.parse(yaml)
    DurableWorkflow::Core::Validator.validate!(workflow)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    # Test with high value order
    result = engine.run(input: { order_id: "ORD-001", amount: 150 })

    assert_equal :completed, result.status
    assert_equal "ORD-001", result.output[:order_id]
    assert result.output[:validated]
    assert result.output[:requires_approval]

    # Test with normal order
    result2 = engine.run(input: { order_id: "ORD-002", amount: 50 })

    assert_equal :completed, result2.status
    assert_equal "ORD-002", result2.output[:order_id]
    assert result2.output[:validated]
    refute result2.output[:requires_approval]
  end

  def test_workflow_with_halt_and_resume
    yaml = {
      id: "approval_workflow",
      name: "Approval Workflow",
      steps: [
        { id: "start", type: "start", next: "request" },
        { id: "request", type: "halt", reason: "Waiting for approval", next: "process" },
        {
          id: "process",
          type: "assign",
          set: { processed: true, approved_value: "$response" },
          next: "end"
        },
        {
          id: "end",
          type: "end",
          result: { processed: "$processed", value: "$approved_value" }
        }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    # First run halts
    halted = engine.run
    assert_equal :halted, halted.status
    assert_equal "Waiting for approval", halted.halt.data[:reason]

    # Resume with response
    completed = engine.resume(halted.execution_id, response: "approved_data")
    assert_equal :completed, completed.status
    assert completed.output[:processed]
    assert_equal "approved_data", completed.output[:value]
  end

  def test_workflow_with_transform
    yaml = {
      id: "transform_workflow",
      name: "Transform Workflow",
      steps: [
        { id: "start", type: "start", next: "setup" },
        {
          id: "setup",
          type: "assign",
          set: {
            users: [
              { name: "Alice", active: true },
              { name: "Bob", active: false },
              { name: "Charlie", active: true }
            ]
          },
          next: "filter"
        },
        {
          id: "filter",
          type: "transform",
          input: "users",
          expression: { select: { active: true }, pluck: "name" },
          output: "active_names",
          next: "end"
        },
        {
          id: "end",
          type: "end",
          result: { active_users: "$active_names" }
        }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run

    assert_equal :completed, result.status
    assert_equal ["Alice", "Charlie"], result.output[:active_users]
  end

  def test_workflow_with_loop
    yaml = {
      id: "loop_workflow",
      name: "Loop Workflow",
      steps: [
        { id: "start", type: "start", next: "setup" },
        {
          id: "setup",
          type: "assign",
          set: { items: [1, 2, 3] },
          next: "loop"
        },
        {
          id: "loop",
          type: "loop",
          over: "$items",
          as: "item",
          do: [
            { id: "double", type: "assign", set: { doubled: "$item" } }
          ],
          output: "results",
          next: "end"
        },
        {
          id: "end",
          type: "end",
          result: { loop_results: "$results" }
        }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run

    assert_equal :completed, result.status
    assert_instance_of Array, result.output[:loop_results]
    assert_equal 3, result.output[:loop_results].size
  end

  def test_workflow_with_error_handling
    # Mock a service that fails
    Object.const_set(:FailingService, Class.new do
      def self.fail!
        raise "Intentional failure"
      end
    end) unless defined?(::FailingService)

    yaml = {
      id: "error_workflow",
      name: "Error Workflow",
      steps: [
        { id: "start", type: "start", next: "risky" },
        {
          id: "risky",
          type: "call",
          service: "FailingService",
          method: "fail!",
          output: "result",
          next: "success",
          on_error: "error_handler"
        },
        {
          id: "success",
          type: "end",
          result: { status: "success" }
        },
        {
          id: "error_handler",
          type: "end",
          result: { status: "error", error: "$_last_error" }
        }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run

    assert_equal :completed, result.status
    assert_equal "error", result.output[:status]
    assert result.output[:error]
  end

  def test_workflow_execution_entries_recorded
    yaml = {
      id: "simple",
      name: "Simple",
      steps: [
        { id: "start", type: "start", next: "step1" },
        { id: "step1", type: "assign", set: { x: 1 }, next: "step2" },
        { id: "step2", type: "assign", set: { y: 2 }, next: "end" },
        { id: "end", type: "end" }
      ]
    }

    workflow = DurableWorkflow::Core::Parser.parse(yaml)
    engine = DurableWorkflow::Core::Engine.new(workflow, store: @store)

    result = engine.run

    entries = @store.entries(result.execution_id)
    assert_equal 4, entries.size

    step_ids = entries.map(&:step_id)
    assert_equal ["start", "step1", "step2", "end"], step_ids
  end
end
