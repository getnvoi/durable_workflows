#!/usr/bin/env ruby
# frozen_string_literal: true

# Calculator Workflow - Routing based on input
#
# Demonstrates: Router step, conditional branching, service calls
#
# Run: ruby examples/calculator.rb
# Requires: Redis running on localhost:6379

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"

# Calculator service for arithmetic operations (must be globally accessible)
module Calculator
  def self.add(a:, b:)
    { result: a + b, operation: "addition" }
  end

  def self.subtract(a:, b:)
    { result: a - b, operation: "subtraction" }
  end

  def self.multiply(a:, b:)
    { result: a * b, operation: "multiplication" }
  end

  def self.divide(a:, b:)
    { result: a.to_f / b, operation: "division" }
  end
end

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

workflow = DurableWorkflow::Core::Parser.parse(<<~YAML)
  id: calculator
  name: Calculator
  version: "1.0"

  inputs:
    operation:
      type: string
      required: true
    a:
      type: number
      required: true
    b:
      type: number
      required: true

  steps:
    - id: start
      type: start
      next: route

    - id: route
      type: router
      routes:
        - when:
            field: input.operation
            op: eq
            value: "add"
          then: add
        - when:
            field: input.operation
            op: eq
            value: "subtract"
          then: subtract
        - when:
            field: input.operation
            op: eq
            value: "multiply"
          then: multiply
        - when:
            field: input.operation
            op: eq
            value: "divide"
          then: divide
      default: error

    - id: add
      type: call
      service: Calculator
      method: add
      input:
        a: "$input.a"
        b: "$input.b"
      output: calc_result
      next: end

    - id: subtract
      type: call
      service: Calculator
      method: subtract
      input:
        a: "$input.a"
        b: "$input.b"
      output: calc_result
      next: end

    - id: multiply
      type: call
      service: Calculator
      method: multiply
      input:
        a: "$input.a"
        b: "$input.b"
      output: calc_result
      next: end

    - id: divide
      type: call
      service: Calculator
      method: divide
      input:
        a: "$input.a"
        b: "$input.b"
      output: calc_result
      next: end

    - id: error
      type: assign
      set:
        calc_result:
          error: "Unknown operation"
      next: end

    - id: end
      type: end
      result:
        result: "$calc_result.result"
        operation: "$calc_result.operation"
        error: "$calc_result.error"
YAML

runner = DurableWorkflow::Runners::Sync.new(workflow)

# Test all operations
[
  { operation: "add", a: 10, b: 5 },
  { operation: "subtract", a: 10, b: 5 },
  { operation: "multiply", a: 10, b: 5 },
  { operation: "divide", a: 10, b: 5 }
].each do |calc_input|
  result = runner.run(input: calc_input)
  puts "#{calc_input[:a]} #{calc_input[:operation]} #{calc_input[:b]} = #{result.output[:result]}"
end
# => 10 add 5 = 15
# => 10 subtract 5 = 5
# => 10 multiply 5 = 50
# => 10 divide 5 = 2.0
