# frozen_string_literal: true

require "test_helper"
require "durable_workflow/extensions/ai"

class FileSearchExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers
  AI = DurableWorkflow::Extensions::AI

  def test_registered_as_file_search
    assert DurableWorkflow::Core::Executors::Registry.registered?("file_search")
  end

  def test_resolves_query_from_state
    step = build_file_search_step(query: "$search_query")
    executor = AI::Executors::FileSearch.new(step)
    state = build_state(ctx: { search_query: "test query" })

    outcome = executor.call(state)

    assert_equal "test query", outcome.result.output[:query]
  end

  def test_stores_results_in_output
    step = build_file_search_step(query: "test", output: :search_results)
    executor = AI::Executors::FileSearch.new(step)
    state = build_state

    outcome = executor.call(state)

    assert outcome.state.ctx[:search_results]
    assert_equal "test", outcome.state.ctx[:search_results][:query]
  end

  def test_respects_max_results
    step = build_file_search_step(query: "test", max_results: 5)
    executor = AI::Executors::FileSearch.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal 5, outcome.result.output[:max_results]
  end

  def test_returns_placeholder_results
    step = build_file_search_step(query: "test", files: ["doc1.pdf", "doc2.pdf"])
    executor = AI::Executors::FileSearch.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal 2, outcome.result.output[:searched_files]
    assert_equal 2, outcome.result.output[:results].size
    assert_equal "doc1.pdf", outcome.result.output[:results][0][:file]
  end

  private

    def build_file_search_step(query:, files: [], max_results: 10, output: nil)
      DurableWorkflow::Core::StepDef.new(
        id: "file_search",
        type: "file_search",
        config: AI::FileSearchConfig.new(
          query: query,
          files: files,
          max_results: max_results,
          output: output
        ),
        next_step: "next"
      )
    end
end
