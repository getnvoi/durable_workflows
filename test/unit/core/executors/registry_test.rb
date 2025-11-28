# frozen_string_literal: true

require "test_helper"

class RegistryTest < Minitest::Test
  def test_register_and_lookup_executor
    # Built-in executors should already be registered
    assert DurableWorkflow::Core::Executors::Registry.registered?("start")
    assert DurableWorkflow::Core::Executors::Registry.registered?("end")
    assert DurableWorkflow::Core::Executors::Registry.registered?("assign")
  end

  def test_lookup_returns_executor_class
    executor_class = DurableWorkflow::Core::Executors::Registry["start"]
    assert_equal DurableWorkflow::Core::Executors::Start, executor_class
  end

  def test_lookup_missing_returns_nil
    assert_nil DurableWorkflow::Core::Executors::Registry["nonexistent"]
  end

  def test_types_returns_registered_types
    types = DurableWorkflow::Core::Executors::Registry.types
    assert_includes types, "start"
    assert_includes types, "end"
    assert_includes types, "assign"
    assert_includes types, "call"
    assert_includes types, "router"
    assert_includes types, "loop"
    assert_includes types, "parallel"
    assert_includes types, "transform"
    assert_includes types, "halt"
    assert_includes types, "approval"
    assert_includes types, "workflow"
  end

  def test_registered_with_string_and_symbol
    assert DurableWorkflow::Core::Executors::Registry.registered?("call")
    assert DurableWorkflow::Core::Executors::Registry.registered?(:call)
  end

  def test_register_convenience_method
    # Test the convenience method returns a proc
    registrar = DurableWorkflow::Core::Executors.register("test_custom")
    assert_instance_of Proc, registrar
  end
end
