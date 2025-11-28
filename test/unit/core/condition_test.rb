# frozen_string_literal: true

require "test_helper"

class ConditionEvaluatorTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def setup
    @state = build_state(ctx: {
      count: 10,
      name: "hello world",
      status: "active",
      items: [1, 2, 3],
      empty_str: "",
      nil_val: nil,
      flag: true,
      zero: 0
    })
  end

  def build_condition(field:, op:, value:)
    DurableWorkflow::Core::Condition.new(field: field, op: op, value: value)
  end

  def test_eq_operator
    cond = build_condition(field: "status", op: "eq", value: "active")
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)

    cond = build_condition(field: "status", op: "eq", value: "inactive")
    refute DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_neq_operator
    cond = build_condition(field: "status", op: "neq", value: "inactive")
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_gt_operator
    cond = build_condition(field: "count", op: "gt", value: 5)
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)

    cond = build_condition(field: "count", op: "gt", value: 15)
    refute DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_gte_operator
    cond = build_condition(field: "count", op: "gte", value: 10)
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_lt_operator
    cond = build_condition(field: "count", op: "lt", value: 15)
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_lte_operator
    cond = build_condition(field: "count", op: "lte", value: 10)
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_in_operator
    cond = build_condition(field: "status", op: "in", value: ["active", "pending"])
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_not_in_operator
    cond = build_condition(field: "status", op: "not_in", value: ["inactive", "deleted"])
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_contains_operator
    cond = build_condition(field: "name", op: "contains", value: "world")
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_starts_with_operator
    cond = build_condition(field: "name", op: "starts_with", value: "hello")
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_ends_with_operator
    cond = build_condition(field: "name", op: "ends_with", value: "world")
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_matches_operator
    cond = build_condition(field: "name", op: "matches", value: "^hello.*")
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_exists_operator
    cond = build_condition(field: "status", op: "exists", value: nil)
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)

    cond = build_condition(field: "nonexistent", op: "exists", value: nil)
    refute DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_empty_operator
    cond = build_condition(field: "empty_str", op: "empty", value: nil)
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)

    cond = build_condition(field: "nil_val", op: "empty", value: nil)
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_truthy_operator
    cond = build_condition(field: "flag", op: "truthy", value: nil)
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)

    cond = build_condition(field: "nil_val", op: "truthy", value: nil)
    refute DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_falsy_operator
    cond = build_condition(field: "nil_val", op: "falsy", value: nil)
    assert DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)

    cond = build_condition(field: "flag", op: "falsy", value: nil)
    refute DurableWorkflow::Core::ConditionEvaluator.match?(@state, cond)
  end

  def test_find_route_returns_first_match
    routes = [
      DurableWorkflow::Core::Route.new(field: "count", op: "gt", value: 100, target: "high"),
      DurableWorkflow::Core::Route.new(field: "count", op: "gt", value: 5, target: "medium"),
      DurableWorkflow::Core::Route.new(field: "count", op: "gt", value: 0, target: "low")
    ]

    route = DurableWorkflow::Core::ConditionEvaluator.find_route(@state, routes)
    assert_equal "medium", route.target
  end

  def test_find_route_returns_nil_when_no_match
    routes = [
      DurableWorkflow::Core::Route.new(field: "count", op: "gt", value: 100, target: "high")
    ]

    route = DurableWorkflow::Core::ConditionEvaluator.find_route(@state, routes)
    assert_nil route
  end
end
