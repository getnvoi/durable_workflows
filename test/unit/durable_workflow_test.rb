# frozen_string_literal: true

require "test_helper"

class DurableWorkflowTest < Minitest::Test
  def teardown
    DurableWorkflow.config = nil
    DurableWorkflow.instance_variable_set(:@registry, nil)
  end

  def test_version_is_0_1_0
    assert_equal "0.1.0", DurableWorkflow::VERSION
  end

  def test_error_is_standard_error
    assert DurableWorkflow::Error < StandardError
  end

  def test_config_error_exists
    assert DurableWorkflow::ConfigError < DurableWorkflow::Error
  end

  def test_validation_error_exists
    assert DurableWorkflow::ValidationError < DurableWorkflow::Error
  end

  def test_execution_error_exists
    assert DurableWorkflow::ExecutionError < DurableWorkflow::Error
  end

  def test_configure_yields_config
    yielded = nil
    DurableWorkflow.configure { |c| yielded = c }

    assert_instance_of DurableWorkflow::Config, yielded
  end

  def test_config_returns_configured_values
    store = Object.new
    DurableWorkflow.configure { |c| c.store = store }

    assert_equal store, DurableWorkflow.config.store
  end

  def test_registry_returns_hash
    assert_instance_of Hash, DurableWorkflow.registry
  end

  def test_register_adds_to_registry
    workflow = Struct.new(:id).new("test-wf")
    DurableWorkflow.register(workflow)

    assert_equal workflow, DurableWorkflow.registry["test-wf"]
  end
end
