# frozen_string_literal: true

require "test_helper"

class TypesConfigsTest < Minitest::Test
  def test_start_config_validate_input_defaults_false
    config = DurableWorkflow::Core::StartConfig.new
    assert_equal false, config.validate_input
  end

  def test_end_config_can_have_result
    config = DurableWorkflow::Core::EndConfig.new(result: { status: "done" })
    assert_equal({ status: "done" }, config.result)
  end

  def test_call_config_requires_service_and_method_name
    config = DurableWorkflow::Core::CallConfig.new(
      service: "OrderService",
      method_name: "create"
    )

    assert_equal "OrderService", config.service
    assert_equal "create", config.method_name
  end

  def test_call_config_retries_defaults_to_0
    config = DurableWorkflow::Core::CallConfig.new(
      service: "Svc",
      method_name: "call"
    )
    assert_equal 0, config.retries
  end

  def test_call_config_retry_delay_defaults_to_1
    config = DurableWorkflow::Core::CallConfig.new(
      service: "Svc",
      method_name: "call"
    )
    assert_equal 1.0, config.retry_delay
  end

  def test_call_config_retry_backoff_defaults_to_2
    config = DurableWorkflow::Core::CallConfig.new(
      service: "Svc",
      method_name: "call"
    )
    assert_equal 2.0, config.retry_backoff
  end

  def test_assign_config_set_defaults_to_empty_hash
    config = DurableWorkflow::Core::AssignConfig.new
    assert_equal({}, config.set)
  end

  def test_router_config_routes_defaults_to_empty_array
    config = DurableWorkflow::Core::RouterConfig.new
    assert_equal [], config.routes
  end

  def test_loop_config_as_defaults_to_item
    config = DurableWorkflow::Core::LoopConfig.new
    assert_equal :item, config.as
  end

  def test_loop_config_index_as_defaults_to_index
    config = DurableWorkflow::Core::LoopConfig.new
    assert_equal :index, config.index_as
  end

  def test_loop_config_max_defaults_to_100
    config = DurableWorkflow::Core::LoopConfig.new
    assert_equal 100, config.max
  end

  def test_halt_config_data_defaults_to_empty_hash
    config = DurableWorkflow::Core::HaltConfig.new
    assert_equal({}, config.data)
  end

  def test_approval_config_requires_prompt
    config = DurableWorkflow::Core::ApprovalConfig.new(prompt: "Approve?")
    assert_equal "Approve?", config.prompt
  end

  def test_transform_config_requires_expression_and_output
    config = DurableWorkflow::Core::TransformConfig.new(
      expression: { count: nil },
      output: :count
    )

    assert_equal({ count: nil }, config.expression)
    assert_equal :count, config.output
  end

  def test_parallel_config_branches_defaults_to_empty_array
    config = DurableWorkflow::Core::ParallelConfig.new
    assert_equal [], config.branches
  end

  def test_workflow_config_requires_workflow_id
    config = DurableWorkflow::Core::WorkflowConfig.new(workflow_id: "sub-wf")
    assert_equal "sub-wf", config.workflow_id
  end

  def test_config_registry_contains_all_core_types
    registry = DurableWorkflow::Core.config_registry
    expected = %w[start end call assign router loop halt approval transform parallel workflow]

    expected.each do |type|
      assert registry.key?(type), "config_registry missing '#{type}'"
    end
  end

  def test_register_config_adds_to_registry
    custom_class = Class.new(DurableWorkflow::Core::StepConfig)
    DurableWorkflow::Core.register_config("custom_test", custom_class)

    assert_equal custom_class, DurableWorkflow::Core.config_registry["custom_test"]
  ensure
    DurableWorkflow::Core.config_registry.delete("custom_test")
  end
end
