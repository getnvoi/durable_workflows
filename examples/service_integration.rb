#!/usr/bin/env ruby
# frozen_string_literal: true

# Service Integration - Calling external services from workflow
#
# Demonstrates: Call step, service resolution, error handling
#
# Run: ruby examples/service_integration.rb
# Requires: Redis running on localhost:6379

require "bundler/setup"
require "securerandom"
require "durable_workflow"
require "durable_workflow/storage/redis"

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

# Inventory service (must be globally accessible constant)
module InventoryService
  STOCK = {
    "PROD-001" => 50,
    "PROD-002" => 0,
    "PROD-003" => 10
  }

  def self.check_availability(product_id:, quantity:)
    available = STOCK.fetch(product_id, 0)
    {
      product_id: product_id,
      requested: quantity,
      available: available,
      in_stock: available >= quantity
    }
  end

  def self.reserve(product_id:, quantity:)
    current = STOCK.fetch(product_id, 0)
    raise "Insufficient stock" if current < quantity

    STOCK[product_id] = current - quantity
    {
      reservation_id: "RES-#{SecureRandom.hex(4)}",
      product_id: product_id,
      quantity: quantity,
      remaining: STOCK[product_id]
    }
  end
end

workflow = DurableWorkflow::Core::Parser.parse(<<~YAML)
  id: inventory_check
  name: Inventory Check and Reserve
  version: "1.0"

  inputs:
    product_id:
      type: string
      required: true
    quantity:
      type: integer
      required: true

  steps:
    - id: start
      type: start
      next: check

    - id: check
      type: call
      service: InventoryService
      method: check_availability
      input:
        product_id: "$input.product_id"
        quantity: "$input.quantity"
      output: availability
      next: decide

    - id: decide
      type: router
      routes:
        - when:
            field: availability.in_stock
            op: eq
            value: true
          then: reserve
      default: out_of_stock

    - id: reserve
      type: call
      service: InventoryService
      method: reserve
      input:
        product_id: "$input.product_id"
        quantity: "$input.quantity"
      output: reservation
      next: success

    - id: success
      type: assign
      set:
        status: reserved
      next: end

    - id: out_of_stock
      type: assign
      set:
        status: out_of_stock
        error: "Insufficient stock available"
      next: end

    - id: end
      type: end
      result:
        status: "$status"
        availability: "$availability"
        reservation: "$reservation"
        error: "$error"
YAML

runner = DurableWorkflow::Runners::Sync.new(workflow)

# Available product
result = runner.run(input: { product_id: "PROD-001", quantity: 5 })
puts "PROD-001 (qty 5): #{result.output[:status]}"
puts "  Reservation: #{result.output[:reservation][:reservation_id]}" if result.output[:reservation]

# Out of stock
result = runner.run(input: { product_id: "PROD-002", quantity: 1 })
puts "\nPROD-002 (qty 1): #{result.output[:status]}"
puts "  Error: #{result.output[:error]}"

# Partial availability
result = runner.run(input: { product_id: "PROD-003", quantity: 20 })
puts "\nPROD-003 (qty 20): #{result.output[:status]}"
puts "  Error: #{result.output[:error]}"
