# frozen_string_literal: true

require "test_helper"

class TypesEntryTest < Minitest::Test
  def test_entry_can_be_created
    entry = DurableWorkflow::Core::Entry.new(
      id: "entry-1",
      execution_id: "exec-1",
      step_id: "step-1",
      step_type: "assign",
      action: :completed,
      timestamp: Time.now
    )

    assert_equal "entry-1", entry.id
    assert_equal "exec-1", entry.execution_id
    assert_equal "step-1", entry.step_id
    assert_equal "assign", entry.step_type
    assert_equal :completed, entry.action
  end

  def test_from_h_parses_action_as_symbol
    hash = {
      id: "e1",
      execution_id: "ex1",
      step_id: "s1",
      step_type: "call",
      action: "completed",
      timestamp: Time.now
    }

    entry = DurableWorkflow::Core::Entry.from_h(hash)
    assert_equal :completed, entry.action
  end

  def test_from_h_parses_timestamp_string
    time_str = "2024-01-15T10:30:00Z"
    hash = {
      id: "e1",
      execution_id: "ex1",
      step_id: "s1",
      step_type: "call",
      action: "completed",
      timestamp: time_str
    }

    entry = DurableWorkflow::Core::Entry.from_h(hash)
    assert_instance_of Time, entry.timestamp
  end
end
