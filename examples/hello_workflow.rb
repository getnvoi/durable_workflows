#!/usr/bin/env ruby
# frozen_string_literal: true

# Hello Workflow - Simplest possible durable workflow
#
# Demonstrates: Basic workflow structure, assign step, input/output
#
# Run: ruby examples/hello_workflow.rb
# Requires: Redis running on localhost:6379

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"

# Configure storage
DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

# Define workflow inline
workflow = DurableWorkflow::Core::Parser.parse(<<~YAML)
  id: hello_world
  name: Hello World
  version: "1.0"

  inputs:
    name:
      type: string
      required: true

  steps:
    - id: start
      type: start
      next: greet

    - id: greet
      type: assign
      set:
        greeting: "Hello, $input.name!"
        timestamp: "$now"
      next: end

    - id: end
      type: end
      result:
        message: "$greeting"
        generated_at: "$timestamp"
YAML

# Run it
runner = DurableWorkflow::Runners::Sync.new(workflow)
result = runner.run(input: { name: "World" })

puts "Status: #{result.status}"
puts "Output: #{result.output}"
# => Status: completed
# => Output: {:message=>"Hello, World!", :generated_at=>"2024-..."}
