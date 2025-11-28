#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "dotenv/load" if File.exist?(File.expand_path("../../.env", __dir__))
require "securerandom"
require "durable_workflow"
require "durable_workflow/storage/redis"
require_relative "services"

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

# Services are auto-resolved via Object.const_get

workflow = DurableWorkflow.load(File.join(__dir__, "workflow.yml"))
runner = DurableWorkflow::Runners::Stream.new(workflow)

# Progress tracking
runner.subscribe do |event|
  case event.type
  when "step.started"
    puts "  [#{Time.now.strftime('%H:%M:%S')}] Starting: #{event.data[:step_id]}"
  when "step.completed"
    puts "  [#{Time.now.strftime('%H:%M:%S')}] Completed: #{event.data[:step_id]}"
  when "workflow.completed"
    puts "\n[DONE] Order processing completed"
  when "workflow.failed"
    puts "\n[FAILED] #{event.data[:error]}"
  end
end

puts "=" * 60
puts "Order Fulfillment Demo"
puts "=" * 60

# Sample order
order = {
  order_id: "ORD-#{SecureRandom.hex(4).upcase}",
  customer: {
    id: "CUST-001",
    email: "alice@example.com",
    name: "Alice Smith",
    address: {
      street: "123 Main St",
      city: "San Francisco",
      state: "CA",
      zip: "94105",
      country: "US"
    }
  },
  items: [
    { product_id: "PROD-001", quantity: 2, price: 29.99 },
    { product_id: "PROD-002", quantity: 1, price: 49.99 }
  ],
  payment: {
    method: "credit_card",
    token: "tok_visa_4242"
  },
  options: {
    expedited: false,
    gift_wrap: false
  }
}

puts "\nProcessing order: #{order[:order_id]}"
puts "Customer: #{order[:customer][:name]}"
puts "Items: #{order[:items].size}"
puts "-" * 40

result = runner.run(input: order)

puts "\n" + "=" * 60
puts "Order Result"
puts "=" * 60
puts "Order ID: #{result.output[:order_id]}"
puts "Status: #{result.output[:status]}"
puts "Total: $#{result.output.dig(:totals, :total)}" if result.output[:totals]
puts "Payment ID: #{result.output[:payment_id]}" if result.output[:payment_id]
puts "Tracking: #{result.output[:tracking_number]}" if result.output[:tracking_number]

if result.output[:error]
  puts "\nError: #{result.output[:error]}"
end
