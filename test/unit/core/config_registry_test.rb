# frozen_string_literal: true

require "test_helper"

class ConfigRegistryTest < Minitest::Test
  def teardown
    # Remove test config if added
    DurableWorkflow::Core::CONFIG_REGISTRY.delete("test_step")
  end

  def test_register_config_adds_to_registry
    custom_config = Class.new(DurableWorkflow::Core::StepConfig)
    DurableWorkflow::Core.register_config("test_step", custom_config)

    assert_equal custom_config, DurableWorkflow::Core::CONFIG_REGISTRY["test_step"]
  end

  def test_config_registered_returns_true_for_registered
    assert DurableWorkflow::Core.config_registered?("start")
    assert DurableWorkflow::Core.config_registered?("end")
    assert DurableWorkflow::Core.config_registered?("call")
  end

  def test_config_registered_returns_false_for_unregistered
    refute DurableWorkflow::Core.config_registered?("unknown_type")
  end

  def test_config_registered_accepts_symbol
    assert DurableWorkflow::Core.config_registered?(:start)
  end
end
