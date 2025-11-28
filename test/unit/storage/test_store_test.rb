# frozen_string_literal: true

require "test_helper"

class TestStoreTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def setup
    @store = TestStore.new
  end

  def teardown
    @store.clear!
  end

  def test_save_and_load_execution
    execution = build_execution(id: "exec-1")

    @store.save(execution)
    loaded = @store.load("exec-1")

    assert_equal execution.id, loaded.id
    assert_equal execution.workflow_id, loaded.workflow_id
  end

  def test_load_returns_nil_for_unknown_execution
    loaded = @store.load("nonexistent")

    assert_nil loaded
  end

  def test_save_overwrites_existing_execution
    exec1 = build_execution(id: "exec-1", ctx: { v: 1 })
    exec2 = build_execution(id: "exec-1", ctx: { v: 2 })

    @store.save(exec1)
    @store.save(exec2)
    loaded = @store.load("exec-1")

    assert_equal 2, loaded.ctx[:v]
  end

  def test_record_and_retrieve_entries
    entry1 = DurableWorkflow::Core::Entry.new(
      id: "entry-1",
      execution_id: "exec-1",
      step_id: "step1",
      step_type: "assign",
      action: :completed,
      timestamp: Time.now
    )
    entry2 = DurableWorkflow::Core::Entry.new(
      id: "entry-2",
      execution_id: "exec-1",
      step_id: "step2",
      step_type: "assign",
      action: :completed,
      timestamp: Time.now
    )

    @store.record(entry1)
    @store.record(entry2)
    entries = @store.entries("exec-1")

    assert_equal 2, entries.size
    assert_equal "step1", entries[0].step_id
    assert_equal "step2", entries[1].step_id
  end

  def test_entries_returns_empty_array_for_unknown_execution
    entries = @store.entries("nonexistent")

    assert_equal [], entries
  end

  def test_clear_removes_all_data
    execution = build_execution(id: "exec-1")
    entry = DurableWorkflow::Core::Entry.new(
      id: "entry-1",
      execution_id: "exec-1",
      step_id: "step1",
      step_type: "assign",
      action: :completed,
      timestamp: Time.now
    )

    @store.save(execution)
    @store.record(entry)
    @store.clear!

    assert_nil @store.load("exec-1")
    assert_equal [], @store.entries("exec-1")
  end

  def test_entries_isolated_by_execution_id
    entry1 = DurableWorkflow::Core::Entry.new(
      id: "entry-1",
      execution_id: "exec-1",
      step_id: "step1",
      step_type: "assign",
      action: :completed,
      timestamp: Time.now
    )
    entry2 = DurableWorkflow::Core::Entry.new(
      id: "entry-2",
      execution_id: "exec-2",
      step_id: "step1",
      step_type: "assign",
      action: :completed,
      timestamp: Time.now
    )

    @store.record(entry1)
    @store.record(entry2)

    assert_equal 1, @store.entries("exec-1").size
    assert_equal 1, @store.entries("exec-2").size
  end
end
