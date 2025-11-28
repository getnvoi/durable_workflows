# frozen_string_literal: true

require "test_helper"

# Test service class
class TestService
  def self.greet(name)
    "Hello, #{name}!"
  end

  def self.add(a:, b:)
    a + b
  end

  def self.constant_result
    42
  end
end

class CallExecutorTest < Minitest::Test
  include DurableWorkflow::TestHelpers

  def build_call_step(service:, method_name:, input: nil, output: nil, next_step: "next")
    config = {
      service: service,
      method_name: method_name
    }
    config[:input] = input if input
    config[:output] = output if output

    DurableWorkflow::Core::StepDef.new(
      id: "call_step",
      type: "call",
      config: DurableWorkflow::Core::CallConfig.new(config),
      next_step: next_step
    )
  end

  def test_call_invokes_service_method_with_positional_arg
    step = build_call_step(
      service: "TestService",
      method_name: "greet",
      input: "$name",
      output: "greeting"
    )
    executor = DurableWorkflow::Core::Executors::Call.new(step)
    state = build_state(ctx: { name: "World" })

    outcome = executor.call(state)

    assert_equal "Hello, World!", outcome.state.ctx[:greeting]
    assert_equal "Hello, World!", outcome.result.output
  end

  def test_call_invokes_service_method_with_keyword_args
    step = build_call_step(
      service: "TestService",
      method_name: "add",
      input: { a: 1, b: 2 },
      output: "sum"
    )
    executor = DurableWorkflow::Core::Executors::Call.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal 3, outcome.state.ctx[:sum]
  end

  def test_call_invokes_zero_arity_method
    step = build_call_step(
      service: "TestService",
      method_name: "constant_result",
      output: "value"
    )
    executor = DurableWorkflow::Core::Executors::Call.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal 42, outcome.state.ctx[:value]
  end

  def test_call_continues_to_next_step
    step = build_call_step(
      service: "TestService",
      method_name: "constant_result",
      output: "value",
      next_step: "process_result"
    )
    executor = DurableWorkflow::Core::Executors::Call.new(step)
    state = build_state

    outcome = executor.call(state)

    assert_equal "process_result", outcome.result.next_step
  end

  def test_call_resolves_input_references
    step = build_call_step(
      service: "TestService",
      method_name: "add",
      input: { a: "$x", b: "$y" },
      output: "result"
    )
    executor = DurableWorkflow::Core::Executors::Call.new(step)
    state = build_state(ctx: { x: 10, y: 5 })

    outcome = executor.call(state)

    assert_equal 15, outcome.state.ctx[:result]
  end
end
