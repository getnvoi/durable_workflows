# frozen_string_literal: true

require "test_helper"

class ExtensionsBaseTest < Minitest::Test
  def setup
    DurableWorkflow::Extensions.reset!
  end

  def teardown
    DurableWorkflow::Extensions.reset!
  end

  def test_extension_name_derived_from_class
    klass = Class.new(DurableWorkflow::Extensions::Base)
    # When class has no name, uses generated name
    assert_kind_of String, klass.extension_name
  end

  def test_extension_name_can_be_set
    klass = Class.new(DurableWorkflow::Extensions::Base) do
      self.extension_name = "custom_name"
    end

    assert_equal "custom_name", klass.extension_name
  end

  def test_register_calls_register_methods
    calls = []
    klass = Class.new(DurableWorkflow::Extensions::Base) do
      self.extension_name = "test_ext"

      define_singleton_method(:register_configs) { calls << :configs }
      define_singleton_method(:register_executors) { calls << :executors }
      define_singleton_method(:register_parser_hooks) { calls << :hooks }
    end

    klass.register!

    assert_includes calls, :configs
    assert_includes calls, :executors
    assert_includes calls, :hooks
  end

  def test_data_from_returns_extension_data
    klass = Class.new(DurableWorkflow::Extensions::Base) do
      self.extension_name = "my_ext"
    end

    workflow = DurableWorkflow::Core::WorkflowDef.new(
      id: "test",
      name: "Test",
      steps: [],
      extensions: { my_ext: { foo: "bar" } }
    )

    assert_equal({ foo: "bar" }, klass.data_from(workflow))
  end

  def test_data_from_returns_empty_hash_when_no_data
    klass = Class.new(DurableWorkflow::Extensions::Base) do
      self.extension_name = "missing"
    end

    workflow = DurableWorkflow::Core::WorkflowDef.new(
      id: "test",
      name: "Test",
      steps: [],
      extensions: {}
    )

    assert_equal({}, klass.data_from(workflow))
  end

  def test_store_in_merges_extension_data
    klass = Class.new(DurableWorkflow::Extensions::Base) do
      self.extension_name = "my_ext"
    end

    workflow = DurableWorkflow::Core::WorkflowDef.new(
      id: "test",
      name: "Test",
      steps: [],
      extensions: { other: { x: 1 } }
    )

    updated = klass.store_in(workflow, { foo: "bar" })

    assert_equal({ x: 1 }, updated.extensions[:other])
    assert_equal({ foo: "bar" }, updated.extensions[:my_ext])
  end
end

class ExtensionsRegistryTest < Minitest::Test
  def setup
    DurableWorkflow::Extensions.reset!
  end

  def teardown
    DurableWorkflow::Extensions.reset!
  end

  def test_register_stores_extension
    klass = Class.new(DurableWorkflow::Extensions::Base) do
      self.extension_name = "test_ext"
    end

    DurableWorkflow::Extensions.register(:test_ext, klass)

    assert_equal klass, DurableWorkflow::Extensions[:test_ext]
  end

  def test_register_calls_register_on_class
    registered = false
    klass = Class.new(DurableWorkflow::Extensions::Base) do
      self.extension_name = "test_ext"
      define_singleton_method(:register!) { registered = true }
    end

    DurableWorkflow::Extensions.register(:test_ext, klass)

    assert registered
  end

  def test_loaded_returns_true_for_registered
    klass = Class.new(DurableWorkflow::Extensions::Base) do
      self.extension_name = "test_ext"
    end

    DurableWorkflow::Extensions.register(:test_ext, klass)

    assert DurableWorkflow::Extensions.loaded?(:test_ext)
  end

  def test_loaded_returns_false_for_unregistered
    refute DurableWorkflow::Extensions.loaded?(:unknown)
  end

  def test_bracket_returns_nil_for_unknown
    assert_nil DurableWorkflow::Extensions[:unknown]
  end
end
