# frozen_string_literal: true

require "test_helper"
require "active_record"
require "durable_workflow/storage/active_record"

# Set up in-memory SQLite database
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

# Create tables
ActiveRecord::Schema.define do
  create_table :workflow_executions, id: false do |t|
    t.string :id, primary_key: true
    t.string :workflow_id
    t.string :status
    t.text :input
    t.text :ctx
    t.string :current_step
    t.text :result
    t.string :recover_to
    t.text :halt_data
    t.text :error
    t.timestamps
  end

  create_table :workflow_entries, id: false do |t|
    t.string :id, primary_key: true
    t.string :execution_id
    t.string :step_id
    t.string :step_type
    t.string :action
    t.integer :duration_ms
    t.text :input
    t.text :output
    t.text :error
    t.datetime :timestamp
  end

  add_index :workflow_executions, :workflow_id
  add_index :workflow_executions, :status
  add_index :workflow_entries, :execution_id
end

# Define AR models
class WorkflowExecution < ActiveRecord::Base
  self.table_name = "workflow_executions"
end

class WorkflowEntry < ActiveRecord::Base
  self.table_name = "workflow_entries"
end

class ActiveRecordStorageTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def setup
    @store = DurableWorkflow::Storage::ActiveRecord.new(
      execution_class: WorkflowExecution,
      entry_class: WorkflowEntry
    )
    WorkflowExecution.delete_all
    WorkflowEntry.delete_all
  end

  def teardown
    WorkflowExecution.delete_all
    WorkflowEntry.delete_all
  end

  # save / load

  def test_save_and_load_execution
    execution = build_execution(id: "exec-1", workflow_id: "wf-1", ctx: { x: 1 })

    @store.save(execution)
    loaded = @store.load("exec-1")

    assert_equal "exec-1", loaded.id
    assert_equal "wf-1", loaded.workflow_id
    assert_equal 1, loaded.ctx[:x]
  end

  def test_load_returns_nil_for_missing
    assert_nil @store.load("nonexistent")
  end

  def test_save_updates_existing_execution
    exec1 = build_execution(id: "exec-1", ctx: { v: 1 })
    exec2 = build_execution(id: "exec-1", ctx: { v: 2 })

    @store.save(exec1)
    @store.save(exec2)
    loaded = @store.load("exec-1")

    assert_equal 2, loaded.ctx[:v]
  end

  def test_save_preserves_input
    execution = build_execution(id: "exec-1", input: { name: "test", count: 42 })

    @store.save(execution)
    loaded = @store.load("exec-1")

    assert_equal({ name: "test", count: 42 }, loaded.input)
  end

  def test_save_preserves_current_step
    execution = build_execution(id: "exec-1", current_step: "step_2")

    @store.save(execution)
    loaded = @store.load("exec-1")

    assert_equal "step_2", loaded.current_step
  end

  # record / entries

  def test_record_and_retrieve_entries
    entry1 = DurableWorkflow::Core::Entry.new(
      id: "e1",
      execution_id: "exec-1",
      step_id: "step1",
      step_type: "assign",
      action: :completed,
      duration_ms: 10,
      timestamp: Time.now
    )
    entry2 = DurableWorkflow::Core::Entry.new(
      id: "e2",
      execution_id: "exec-1",
      step_id: "step2",
      step_type: "call",
      action: :completed,
      duration_ms: 20,
      timestamp: Time.now + 1
    )

    @store.record(entry1)
    @store.record(entry2)
    entries = @store.entries("exec-1")

    assert_equal 2, entries.size
    assert_equal "step1", entries[0].step_id
    assert_equal "step2", entries[1].step_id
  end

  def test_entries_returns_empty_for_missing
    assert_equal [], @store.entries("nonexistent")
  end

  def test_entry_preserves_all_fields
    entry = DurableWorkflow::Core::Entry.new(
      id: "e1",
      execution_id: "exec-1",
      step_id: "my_step",
      step_type: "call",
      action: :failed,
      duration_ms: 123,
      input: { a: 1 },
      output: { b: 2 },
      error: "Something failed",
      timestamp: Time.now
    )

    @store.record(entry)
    loaded = @store.entries("exec-1").first

    assert_equal "e1", loaded.id
    assert_equal "my_step", loaded.step_id
    assert_equal "call", loaded.step_type
    assert_equal :failed, loaded.action
    assert_equal 123, loaded.duration_ms
    assert_equal({ a: 1 }, loaded.input)
    assert_equal({ b: 2 }, loaded.output)
    assert_equal "Something failed", loaded.error
  end

  def test_entries_isolated_by_execution_id
    entry1 = DurableWorkflow::Core::Entry.new(
      id: "e1", execution_id: "exec-1", step_id: "s1",
      step_type: "assign", action: :completed, timestamp: Time.now
    )
    entry2 = DurableWorkflow::Core::Entry.new(
      id: "e2", execution_id: "exec-2", step_id: "s1",
      step_type: "assign", action: :completed, timestamp: Time.now
    )

    @store.record(entry1)
    @store.record(entry2)

    assert_equal 1, @store.entries("exec-1").size
    assert_equal 1, @store.entries("exec-2").size
  end

  # find

  def test_find_by_workflow_id
    exec1 = build_execution(id: "exec-1", workflow_id: "wf-a")
    exec2 = build_execution(id: "exec-2", workflow_id: "wf-a")
    exec3 = build_execution(id: "exec-3", workflow_id: "wf-b")

    @store.save(exec1)
    @store.save(exec2)
    @store.save(exec3)

    results = @store.find(workflow_id: "wf-a")

    assert_equal 2, results.size
    assert results.all? { _1.workflow_id == "wf-a" }
  end

  def test_find_by_status
    exec1 = build_execution(id: "exec-1", status: :completed)
    exec2 = build_execution(id: "exec-2", status: :halted)
    exec3 = build_execution(id: "exec-3", status: :completed)

    @store.save(exec1)
    @store.save(exec2)
    @store.save(exec3)

    results = @store.find(status: :completed)

    assert_equal 2, results.size
    assert results.all? { _1.status == :completed }
  end

  def test_find_respects_limit
    5.times do |i|
      @store.save(build_execution(id: "exec-#{i}"))
    end

    results = @store.find(limit: 3)

    assert_equal 3, results.size
  end

  # delete

  def test_delete_removes_execution_and_entries
    execution = build_execution(id: "exec-1")
    entry = DurableWorkflow::Core::Entry.new(
      id: "e1", execution_id: "exec-1", step_id: "s1",
      step_type: "assign", action: :completed, timestamp: Time.now
    )

    @store.save(execution)
    @store.record(entry)

    assert @store.delete("exec-1")
    assert_nil @store.load("exec-1")
    assert_equal [], @store.entries("exec-1")
  end

  def test_delete_returns_false_for_missing
    refute @store.delete("nonexistent")
  end

  # execution_ids

  def test_execution_ids_returns_all_ids
    @store.save(build_execution(id: "exec-1"))
    @store.save(build_execution(id: "exec-2"))
    @store.save(build_execution(id: "exec-3"))

    ids = @store.execution_ids

    assert_equal 3, ids.size
    assert_includes ids, "exec-1"
    assert_includes ids, "exec-2"
    assert_includes ids, "exec-3"
  end

  def test_execution_ids_filters_by_workflow_id
    @store.save(build_execution(id: "exec-1", workflow_id: "wf-a"))
    @store.save(build_execution(id: "exec-2", workflow_id: "wf-b"))

    ids = @store.execution_ids(workflow_id: "wf-a")

    assert_equal 1, ids.size
    assert_includes ids, "exec-1"
  end

  def test_execution_ids_respects_limit
    5.times { |i| @store.save(build_execution(id: "exec-#{i}")) }

    ids = @store.execution_ids(limit: 2)

    assert_equal 2, ids.size
  end
end
