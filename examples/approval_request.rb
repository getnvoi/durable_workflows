#!/usr/bin/env ruby
# frozen_string_literal: true

# Approval Request - Workflow that halts for human input
#
# Demonstrates: Halt step, resume, human-in-the-loop
#
# Run: ruby examples/approval_request.rb
# Requires: Redis running on localhost:6379

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

workflow = DurableWorkflow::Core::Parser.parse(<<~YAML)
  id: expense_approval
  name: Expense Approval
  version: "1.0"

  inputs:
    requester:
      type: string
      required: true
    amount:
      type: number
      required: true
    description:
      type: string
      required: true

  steps:
    - id: start
      type: start
      next: check_amount

    - id: check_amount
      type: router
      routes:
        - when:
            field: input.amount
            op: gt
            value: 100
          then: require_approval
      default: auto_approve

    - id: auto_approve
      type: assign
      set:
        approved: true
        approved_by: system
        reason: "Amount under threshold"
      next: end

    - id: require_approval
      type: approval
      prompt: "Please approve expense request"
      context:
        requester: "$input.requester"
        amount: "$input.amount"
        description: "$input.description"
      on_reject: rejected
      next: approved

    - id: approved
      type: assign
      set:
        approved: true
        approved_by: manager
      next: end

    - id: rejected
      type: assign
      set:
        approved: false
        approved_by: manager
        reason: "Request rejected"
      next: end

    - id: end
      type: end
      result:
        approved: "$approved"
        approved_by: "$approved_by"
        reason: "$reason"
YAML

runner = DurableWorkflow::Runners::Sync.new(workflow)

# Small expense - auto-approved
result = runner.run(input: { requester: "Alice", amount: 50, description: "Office supplies" })
puts "Small expense: #{result.output}"
# => Small expense: {:approved=>true, :approved_by=>"system", :reason=>"Amount under threshold"}

# Large expense - requires approval
result = runner.run(input: { requester: "Bob", amount: 500, description: "Conference ticket" })
puts "\nLarge expense halted: #{result.status}"
puts "Halt data: #{result.halt&.data}"

# Simulate manager approval
if result.status == :halted
  puts "Workflow halted for approval - would resume with approved: true/false"
end
