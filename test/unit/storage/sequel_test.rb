# frozen_string_literal: true

require "test_helper"
require "sequel"
require "json"
require "durable_workflow/storage/sequel"

# Set up in-memory SQLite database
DB = Sequel.sqlite

# Create tables
DB.create_table :workflow_executions do
  String :id, primary_key: true
  String :workflow_id
  String :status
  String :input, text: true  # JSON stored as text for SQLite
  String :ctx, text: true    # JSON stored as text for SQLite
  String :current_step
  DateTime :created_at
  DateTime :updated_at
end

DB.create_table :workflow_entries do
  String :id, primary_key: true
  String :execution_id
  String :step_id
  String :step_type
  String :action
  Integer :duration_ms
  String :input, text: true   # JSON stored as text for SQLite
  String :output, text: true  # JSON stored as text for SQLite
  String :error, text: true
  DateTime :timestamp
end

# Custom SQLite-compatible Sequel storage adapter for testing
module DurableWorkflow
  module Storage
    class SequelSQLite < Store
      def initialize(db:, executions_table: :workflow_executions, entries_table: :workflow_entries)
        @db = db
        @executions = db[executions_table]
        @entries = db[entries_table]
      end

      def save(state)
        now = Time.now
        data = {
          workflow_id: state.workflow_id,
          status: (state.ctx[:_status] || :running).to_s,
          input: state.input.to_json,
          ctx: state.ctx.to_json,
          current_step: state.current_step,
          updated_at: now
        }

        if @executions.where(id: state.execution_id).count > 0
          @executions.where(id: state.execution_id).update(data)
        else
          @executions.insert(data.merge(id: state.execution_id, created_at: now))
        end

        state
      end

      def load(execution_id)
        row = @executions.where(id: execution_id).first
        return nil unless row

        Core::State.new(
          execution_id: row[:id],
          workflow_id: row[:workflow_id],
          input: parse_json(row[:input]),
          ctx: parse_json(row[:ctx]),
          current_step: row[:current_step],
          history: []
        )
      end

      def record(entry)
        @entries.insert(
          id: entry.id,
          execution_id: entry.execution_id,
          step_id: entry.step_id,
          step_type: entry.step_type,
          action: entry.action.to_s,
          duration_ms: entry.duration_ms,
          input: entry.input&.to_json,
          output: entry.output&.to_json,
          error: entry.error,
          timestamp: entry.timestamp
        )
        entry
      end

      def entries(execution_id)
        @entries.where(execution_id:).order(:timestamp).map do |row|
          Core::Entry.new(
            id: row[:id],
            execution_id: row[:execution_id],
            step_id: row[:step_id],
            step_type: row[:step_type],
            action: row[:action].to_sym,
            duration_ms: row[:duration_ms],
            input: parse_json(row[:input]),
            output: parse_json(row[:output]),
            error: row[:error],
            timestamp: row[:timestamp]
          )
        end
      end

      def find(workflow_id: nil, status: nil, limit: 100)
        scope = @executions
        scope = scope.where(workflow_id:) if workflow_id
        scope = scope.where(status: status.to_s) if status
        scope.order(::Sequel.desc(:created_at)).limit(limit).map do |row|
          Core::State.new(
            execution_id: row[:id],
            workflow_id: row[:workflow_id],
            input: parse_json(row[:input]),
            ctx: parse_json(row[:ctx]),
            current_step: row[:current_step],
            history: []
          )
        end
      end

      def delete(execution_id)
        count = @executions.where(id: execution_id).delete
        @entries.where(execution_id:).delete
        count > 0
      end

      def execution_ids(workflow_id: nil, limit: 1000)
        scope = @executions
        scope = scope.where(workflow_id:) if workflow_id
        scope.limit(limit).select_map(:id)
      end

      private

        def parse_json(str)
          return {} if str.nil? || str.empty?
          DurableWorkflow::Utils.deep_symbolize(JSON.parse(str))
        rescue JSON::ParserError
          {}
        end
    end
  end
end

class SequelStorageTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def setup
    @store = DurableWorkflow::Storage::SequelSQLite.new(db: DB)
    DB[:workflow_executions].delete
    DB[:workflow_entries].delete
  end

  def teardown
    DB[:workflow_executions].delete
    DB[:workflow_entries].delete
  end

  # save / load

  def test_save_and_load_state
    state = build_state(execution_id: "exec-1", workflow_id: "wf-1", ctx: { x: 1 })

    @store.save(state)
    loaded = @store.load("exec-1")

    assert_equal "exec-1", loaded.execution_id
    assert_equal "wf-1", loaded.workflow_id
    assert_equal 1, loaded.ctx[:x]
  end

  def test_load_returns_nil_for_missing
    assert_nil @store.load("nonexistent")
  end

  def test_save_updates_existing_state
    state1 = build_state(execution_id: "exec-1", ctx: { v: 1 })
    state2 = build_state(execution_id: "exec-1", ctx: { v: 2 })

    @store.save(state1)
    @store.save(state2)
    loaded = @store.load("exec-1")

    assert_equal 2, loaded.ctx[:v]
  end

  def test_save_preserves_input
    state = build_state(execution_id: "exec-1", input: { name: "test", count: 42 })

    @store.save(state)
    loaded = @store.load("exec-1")

    assert_equal({ name: "test", count: 42 }, loaded.input)
  end

  def test_save_preserves_current_step
    state = build_state(execution_id: "exec-1")
    state = state.with_current_step("step_2")

    @store.save(state)
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
    state1 = build_state(execution_id: "exec-1", workflow_id: "wf-a")
    state2 = build_state(execution_id: "exec-2", workflow_id: "wf-a")
    state3 = build_state(execution_id: "exec-3", workflow_id: "wf-b")

    @store.save(state1)
    @store.save(state2)
    @store.save(state3)

    results = @store.find(workflow_id: "wf-a")

    assert_equal 2, results.size
    assert results.all? { _1.workflow_id == "wf-a" }
  end

  def test_find_by_status
    state1 = build_state(execution_id: "exec-1", ctx: { _status: :completed })
    state2 = build_state(execution_id: "exec-2", ctx: { _status: :halted })
    state3 = build_state(execution_id: "exec-3", ctx: { _status: :completed })

    @store.save(state1)
    @store.save(state2)
    @store.save(state3)

    results = @store.find(status: :completed)

    assert_equal 2, results.size
    assert results.all? { _1.ctx[:_status].to_s == "completed" }
  end

  def test_find_respects_limit
    5.times do |i|
      @store.save(build_state(execution_id: "exec-#{i}"))
    end

    results = @store.find(limit: 3)

    assert_equal 3, results.size
  end

  # delete

  def test_delete_removes_state_and_entries
    state = build_state(execution_id: "exec-1")
    entry = DurableWorkflow::Core::Entry.new(
      id: "e1", execution_id: "exec-1", step_id: "s1",
      step_type: "assign", action: :completed, timestamp: Time.now
    )

    @store.save(state)
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
    @store.save(build_state(execution_id: "exec-1"))
    @store.save(build_state(execution_id: "exec-2"))
    @store.save(build_state(execution_id: "exec-3"))

    ids = @store.execution_ids

    assert_equal 3, ids.size
    assert_includes ids, "exec-1"
    assert_includes ids, "exec-2"
    assert_includes ids, "exec-3"
  end

  def test_execution_ids_filters_by_workflow_id
    @store.save(build_state(execution_id: "exec-1", workflow_id: "wf-a"))
    @store.save(build_state(execution_id: "exec-2", workflow_id: "wf-b"))

    ids = @store.execution_ids(workflow_id: "wf-a")

    assert_equal 1, ids.size
    assert_includes ids, "exec-1"
  end

  def test_execution_ids_respects_limit
    5.times { |i| @store.save(build_state(execution_id: "exec-#{i}")) }

    ids = @store.execution_ids(limit: 2)

    assert_equal 2, ids.size
  end
end
