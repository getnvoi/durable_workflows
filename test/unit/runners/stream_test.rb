# frozen_string_literal: true

require "test_helper"

class StreamRunnerTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def setup
    @store = TestStore.new
    @events = []
  end

  def teardown
    @store.clear!
  end

  def build_simple_workflow
    DurableWorkflow::Core::WorkflowDef.new(
      id: "stream_test_workflow",
      name: "Stream Test",
      version: "1.0",
      steps: [
        DurableWorkflow::Core::StepDef.new(
          id: "start",
          type: "start",
          config: DurableWorkflow::Core::StartConfig.new,
          next_step: "assign"
        ),
        DurableWorkflow::Core::StepDef.new(
          id: "assign",
          type: "assign",
          config: DurableWorkflow::Core::AssignConfig.new(set: { x: 1 }),
          next_step: "end"
        ),
        DurableWorkflow::Core::StepDef.new(
          id: "end",
          type: "end",
          config: DurableWorkflow::Core::EndConfig.new(result: { done: true }),
          next_step: nil
        )
      ]
    )
  end

  def test_requires_store
    workflow = build_simple_workflow

    assert_raises(DurableWorkflow::ConfigError) do
      DurableWorkflow::Runners::Stream.new(workflow)
    end
  end

  def test_subscribe_returns_self_for_chaining
    workflow = build_simple_workflow
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)

    result = runner.subscribe { |e| @events << e }

    assert_equal runner, result
  end

  def test_run_emits_workflow_started_event
    workflow = build_simple_workflow
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)
    runner.subscribe { |e| @events << e }

    runner.run

    started_event = @events.find { _1.type == "workflow.started" }
    assert started_event
    assert_equal workflow.id, started_event.data[:workflow_id]
  end

  def test_run_emits_workflow_completed_event
    workflow = build_simple_workflow
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)
    runner.subscribe { |e| @events << e }

    runner.run

    completed_event = @events.find { _1.type == "workflow.completed" }
    assert completed_event
    assert_equal({ done: true }, completed_event.data[:output])
  end

  def test_run_emits_step_events
    workflow = build_simple_workflow
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)
    runner.subscribe { |e| @events << e }

    runner.run

    step_started = @events.select { _1.type == "step.started" }
    step_completed = @events.select { _1.type == "step.completed" }

    # start, assign, end = 3 steps
    assert_equal 3, step_started.size
    assert_equal 3, step_completed.size
  end

  def test_subscribe_filters_by_event_type
    workflow = build_simple_workflow
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)
    runner.subscribe(events: ["workflow.completed"]) { |e| @events << e }

    runner.run

    # Only workflow.completed events should be captured
    assert @events.all? { _1.type == "workflow.completed" }
    assert_equal 1, @events.size
  end

  def test_event_to_sse_format
    workflow = build_simple_workflow
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)
    runner.subscribe { |e| @events << e }

    runner.run

    event = @events.first
    sse = event.to_sse

    assert_match(/^event: workflow\.started\n/, sse)
    assert_match(/^data: \{/, sse)
    assert_match(/\n\n$/, sse)
  end

  def test_event_to_json
    workflow = build_simple_workflow
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)
    runner.subscribe { |e| @events << e }

    runner.run

    event = @events.first
    json = event.to_json
    parsed = JSON.parse(json)

    assert_equal "workflow.started", parsed["type"]
    assert parsed["data"]
    assert parsed["timestamp"]
  end

  def test_run_returns_result
    workflow = build_simple_workflow
    runner = DurableWorkflow::Runners::Stream.new(workflow, store: @store)
    runner.subscribe { |e| @events << e }

    result = runner.run

    assert_equal :completed, result.status
  end
end
