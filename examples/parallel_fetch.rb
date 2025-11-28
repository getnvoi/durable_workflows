#!/usr/bin/env ruby
# frozen_string_literal: true

# Parallel Fetch - Execute multiple operations concurrently
#
# Demonstrates: Parallel step, concurrent execution
#
# Run: ruby examples/parallel_fetch.rb
# Requires: Redis running on localhost:6379, async gem

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

# Mock services (must be globally accessible constants)
module UserService
  def self.get_profile(user_id:)
    sleep(0.1) # Simulate latency
    { id: user_id, name: "User #{user_id}", email: "user#{user_id}@example.com" }
  end
end

module OrderService
  def self.get_recent(user_id:, limit:)
    sleep(0.1)
    limit.times.map { |i| { id: "ORD-#{i}", amount: rand(10..100) } }
  end
end

module NotificationService
  def self.get_unread(user_id:)
    sleep(0.1)
    rand(0..5).times.map { |i| { id: "NOTIF-#{i}", message: "Notification #{i}" } }
  end
end

workflow = DurableWorkflow::Core::Parser.parse(<<~YAML)
  id: dashboard_data
  name: Dashboard Data Fetch
  version: "1.0"

  inputs:
    user_id:
      type: string
      required: true

  steps:
    - id: start
      type: start
      next: fetch_all

    - id: fetch_all
      type: parallel
      branches:
        - id: get_profile
          type: call
          service: UserService
          method: get_profile
          input:
            user_id: "$input.user_id"
          output: profile

        - id: get_orders
          type: call
          service: OrderService
          method: get_recent
          input:
            user_id: "$input.user_id"
            limit: 5
          output: orders

        - id: get_notifications
          type: call
          service: NotificationService
          method: get_unread
          input:
            user_id: "$input.user_id"
          output: notifications
      next: end

    - id: end
      type: end
      result:
        user: "$profile"
        recent_orders: "$orders"
        notifications: "$notifications"
YAML

runner = DurableWorkflow::Runners::Sync.new(workflow)

start_time = Time.now
result = runner.run(input: { user_id: "USER-123" })
elapsed = Time.now - start_time

puts "Fetched dashboard data in #{elapsed.round(2)}s (parallel, not sequential 0.3s)"
puts "User: #{result.output[:user][:name]}"
puts "Orders: #{result.output[:recent_orders].size}"
puts "Notifications: #{result.output[:notifications].size}"
