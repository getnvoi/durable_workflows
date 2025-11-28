# frozen_string_literal: true

require "test_helper"

class TypesConditionTest < Minitest::Test
  def test_condition_can_be_created
    cond = DurableWorkflow::Core::Condition.new(
      field: "status",
      op: "eq",
      value: "active"
    )

    assert_equal "status", cond.field
    assert_equal "eq", cond.op
    assert_equal "active", cond.value
  end

  def test_condition_op_defaults_to_eq
    cond = DurableWorkflow::Core::Condition.new(
      field: "status",
      value: "active"
    )

    assert_equal "eq", cond.op
  end

  def test_route_can_be_created
    route = DurableWorkflow::Core::Route.new(
      field: "amount",
      op: "gt",
      value: 100,
      target: "high_value"
    )

    assert_equal "amount", route.field
    assert_equal "gt", route.op
    assert_equal 100, route.value
    assert_equal "high_value", route.target
  end
end
