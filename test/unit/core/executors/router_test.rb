# frozen_string_literal: true

require "test_helper"

class RouterExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def build_router_step(routes:, default: nil)
    DurableWorkflow::Core::StepDef.new(
      id: "router_step",
      type: "router",
      config: DurableWorkflow::Core::RouterConfig.new(routes: routes, default: default),
      next_step: nil
    )
  end

  def build_route(field:, op:, value:, target:)
    DurableWorkflow::Core::Route.new(field: field, op: op, value: value, target: target)
  end

  def test_router_selects_first_matching_route
    routes = [
      build_route(field: "status", op: "eq", value: "approved", target: "process_approved"),
      build_route(field: "status", op: "eq", value: "rejected", target: "process_rejected")
    ]
    step = build_router_step(routes: routes)
    executor = DurableWorkflow::Core::Executors::Router.new(step)
    state = build_state(ctx: { status: "approved" })

    outcome = executor.call(state)

    assert_equal "process_approved", outcome.result.next_step
  end

  def test_router_selects_second_route_when_first_doesnt_match
    routes = [
      build_route(field: "count", op: "gt", value: 100, target: "high"),
      build_route(field: "count", op: "gt", value: 50, target: "medium"),
      build_route(field: "count", op: "gt", value: 0, target: "low")
    ]
    step = build_router_step(routes: routes)
    executor = DurableWorkflow::Core::Executors::Router.new(step)
    state = build_state(ctx: { count: 75 })

    outcome = executor.call(state)

    assert_equal "medium", outcome.result.next_step
  end

  def test_router_uses_default_when_no_route_matches
    routes = [
      build_route(field: "status", op: "eq", value: "special", target: "special_handler")
    ]
    step = build_router_step(routes: routes, default: "default_handler")
    executor = DurableWorkflow::Core::Executors::Router.new(step)
    state = build_state(ctx: { status: "normal" })

    outcome = executor.call(state)

    assert_equal "default_handler", outcome.result.next_step
  end

  def test_router_raises_when_no_match_and_no_default
    routes = [
      build_route(field: "status", op: "eq", value: "special", target: "special_handler")
    ]
    step = build_router_step(routes: routes, default: nil)
    executor = DurableWorkflow::Core::Executors::Router.new(step)
    state = build_state(ctx: { status: "normal" })

    assert_raises(DurableWorkflow::ExecutionError) do
      executor.call(state)
    end
  end

  def test_router_with_gt_condition
    routes = [
      build_route(field: "score", op: "gt", value: 90, target: "excellent"),
      build_route(field: "score", op: "gt", value: 70, target: "good")
    ]
    step = build_router_step(routes: routes, default: "needs_improvement")
    executor = DurableWorkflow::Core::Executors::Router.new(step)
    state = build_state(ctx: { score: 95 })

    outcome = executor.call(state)

    assert_equal "excellent", outcome.result.next_step
  end

  def test_router_with_in_condition
    routes = [
      build_route(field: "type", op: "in", value: %w[premium vip], target: "priority_queue")
    ]
    step = build_router_step(routes: routes, default: "standard_queue")
    executor = DurableWorkflow::Core::Executors::Router.new(step)
    state = build_state(ctx: { type: "vip" })

    outcome = executor.call(state)

    assert_equal "priority_queue", outcome.result.next_step
  end
end
