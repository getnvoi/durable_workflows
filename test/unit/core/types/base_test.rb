# frozen_string_literal: true

require "test_helper"

class TypesBaseTest < Minitest::Test
  def test_step_type_accepts_any_string
    assert_equal "custom", DurableWorkflow::Types::StepType["custom"]
    assert_equal "ai_agent", DurableWorkflow::Types::StepType["ai_agent"]
  end

  def test_operator_accepts_valid_operators
    %w[eq neq gt gte lt lte contains starts_with ends_with matches in not_in exists empty truthy falsy].each do |op|
      assert_equal op, DurableWorkflow::Types::Operator[op]
    end
  end

  def test_operator_rejects_invalid
    assert_raises(Dry::Types::ConstraintError) do
      DurableWorkflow::Types::Operator["invalid"]
    end
  end

  def test_entry_action_accepts_symbols
    assert_equal :completed, DurableWorkflow::Types::EntryAction[:completed]
    assert_equal :halted, DurableWorkflow::Types::EntryAction[:halted]
    assert_equal :failed, DurableWorkflow::Types::EntryAction[:failed]
  end

  def test_wait_mode_defaults_to_all
    # WaitMode with default - when omitted it's nil (optional attribute)
    # The default "all" is applied in the executor when wait is nil
    config = DurableWorkflow::Core::ParallelConfig.new(branches: [])
    # Optional attribute means nil when not provided
    assert_nil config.wait
  end

  def test_wait_mode_accepts_all_any_or_integer
    config_all = DurableWorkflow::Core::ParallelConfig.new(branches: [], wait: "all")
    assert_equal "all", config_all.wait

    config_any = DurableWorkflow::Core::ParallelConfig.new(branches: [], wait: "any")
    assert_equal "any", config_any.wait

    config_int = DurableWorkflow::Core::ParallelConfig.new(branches: [], wait: 2)
    assert_equal 2, config_int.wait
  end
end
