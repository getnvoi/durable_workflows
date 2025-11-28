# frozen_string_literal: true

require "test_helper"

class ParserHooksTest < Minitest::Test
  def setup
    DurableWorkflow::Core::Parser.reset_hooks!
  end

  def teardown
    DurableWorkflow::Core::Parser.reset_hooks!
  end

  def test_before_parse_hooks_run_before_parsing
    order = []

    DurableWorkflow::Core::Parser.before_parse do |yaml|
      order << :before
      yaml
    end

    DurableWorkflow::Core::Parser.parse({
      id: "test",
      name: "Test",
      steps: [{ id: "start", type: "start" }]
    })

    assert_equal [:before], order
  end

  def test_before_parse_hooks_can_modify_yaml
    DurableWorkflow::Core::Parser.before_parse do |yaml|
      yaml.merge(name: "Modified Name")
    end

    workflow = DurableWorkflow::Core::Parser.parse({
      id: "test",
      name: "Original",
      steps: [{ id: "start", type: "start" }]
    })

    assert_equal "Modified Name", workflow.name
  end

  def test_after_parse_hooks_run_after_parsing
    order = []

    DurableWorkflow::Core::Parser.after_parse do |workflow|
      order << :after
      workflow
    end

    DurableWorkflow::Core::Parser.parse({
      id: "test",
      name: "Test",
      steps: [{ id: "start", type: "start" }]
    })

    assert_equal [:after], order
  end

  def test_after_parse_hooks_receive_workflow_def
    received = nil

    DurableWorkflow::Core::Parser.after_parse do |workflow|
      received = workflow
      workflow
    end

    DurableWorkflow::Core::Parser.parse({
      id: "test",
      name: "Test",
      steps: [{ id: "start", type: "start" }]
    })

    assert_kind_of DurableWorkflow::Core::WorkflowDef, received
  end

  def test_after_parse_hooks_can_return_modified_workflow
    DurableWorkflow::Core::Parser.after_parse do |workflow|
      workflow.with(extensions: { custom: { data: 123 } })
    end

    workflow = DurableWorkflow::Core::Parser.parse({
      id: "test",
      name: "Test",
      steps: [{ id: "start", type: "start" }]
    })

    assert_equal({ data: 123 }, workflow.extensions[:custom])
  end

  def test_transform_config_transforms_specific_type
    DurableWorkflow::Core::Parser.transform_config("assign") do |config|
      config.merge(set: { transformed: true })
    end

    workflow = DurableWorkflow::Core::Parser.parse({
      id: "test",
      name: "Test",
      steps: [
        { id: "start", type: "start", next: "assign1" },
        { id: "assign1", type: "assign", set: { original: true } }
      ]
    })

    assign_step = workflow.find_step("assign1")
    assert assign_step.config.set[:transformed]
  end

  def test_multiple_hooks_run_in_order
    order = []

    DurableWorkflow::Core::Parser.before_parse { |y| order << :before1; y }
    DurableWorkflow::Core::Parser.before_parse { |y| order << :before2; y }
    DurableWorkflow::Core::Parser.after_parse { |w| order << :after1; w }
    DurableWorkflow::Core::Parser.after_parse { |w| order << :after2; w }

    DurableWorkflow::Core::Parser.parse({
      id: "test",
      name: "Test",
      steps: [{ id: "start", type: "start" }]
    })

    assert_equal [:before1, :before2, :after1, :after2], order
  end

  def test_reset_hooks_clears_all_hooks
    DurableWorkflow::Core::Parser.before_parse { |y| y }
    DurableWorkflow::Core::Parser.after_parse { |w| w }
    DurableWorkflow::Core::Parser.transform_config("test") { |c| c }

    DurableWorkflow::Core::Parser.reset_hooks!

    assert_empty DurableWorkflow::Core::Parser.before_hooks
    assert_empty DurableWorkflow::Core::Parser.after_hooks
    assert_empty DurableWorkflow::Core::Parser.config_transformers
  end
end
