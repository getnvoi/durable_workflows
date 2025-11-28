#!/usr/bin/env ruby
# frozen_string_literal: true

# Item Processor - Loop through collection and aggregate
#
# Demonstrates: Loop step, service calls for computation
#
# Run: ruby examples/item_processor.rb
# Requires: Redis running on localhost:6379

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"

# Service for item processing (must be globally accessible)
module ItemProcessor
  def self.process(items:)
    total = 0
    processed = []

    items.each do |item|
      line_total = item[:quantity] * item[:price]
      total += line_total
      processed << { name: item[:name], subtotal: line_total }
    end

    {
      count: items.size,
      total: total,
      average: items.empty? ? 0 : total.to_f / items.size,
      items: processed
    }
  end
end

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

workflow = DurableWorkflow::Core::Parser.parse(<<~YAML)
  id: item_processor
  name: Item Processor
  version: "1.0"

  inputs:
    items:
      type: array
      required: true

  steps:
    - id: start
      type: start
      next: process

    - id: process
      type: call
      service: ItemProcessor
      method: process
      input:
        items: "$input.items"
      output: result
      next: end

    - id: end
      type: end
      result:
        item_count: "$result.count"
        total: "$result.total"
        average: "$result.average"
        items: "$result.items"
YAML

runner = DurableWorkflow::Runners::Sync.new(workflow)

result = runner.run(input: {
  items: [
    { name: "Widget", quantity: 3, price: 10.00 },
    { name: "Gadget", quantity: 2, price: 25.00 },
    { name: "Gizmo", quantity: 5, price: 5.00 }
  ]
})

puts "Processed #{result.output[:item_count]} items"
puts "Total: $#{result.output[:total]}"
puts "Average: $#{result.output[:average].round(2)}"
puts "Breakdown:"
result.output[:items].each do |item|
  puts "  #{item[:name]}: $#{item[:subtotal]}"
end
# => Processed 3 items
# => Total: $105.0
# => Average: $35.0
# => Breakdown:
# =>   Widget: $30.0
# =>   Gadget: $50.0
# =>   Gizmo: $25.0
