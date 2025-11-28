#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "dotenv/load" if File.exist?(File.expand_path("../../.env", __dir__))
require "durable_workflow"
require "durable_workflow/extensions/ai"
require "durable_workflow/storage/redis"
require_relative "services"

# Configure
DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

DurableWorkflow::Extensions::AI.configure do |c|
  c.api_keys[:openai] = ENV["OPENAI_API_KEY"]
  c.api_keys[:anthropic] = ENV["ANTHROPIC_API_KEY"]
  c.default_model = "gpt-4o-mini"
end

# Services are auto-resolved via Object.const_get (SupportServices is a global module)

# Load and register workflow
workflow = DurableWorkflow.load(File.join(__dir__, "workflow.yml"))
DurableWorkflow.register(workflow)
runner = DurableWorkflow::Runners::Stream.new(workflow)

# Subscribe to events for visibility
runner.subscribe do |event|
  case event.type
  when "step.started"
    puts "  [#{event.data[:step_id]}]" if ENV["DEBUG"]
  when "agent.tool_use"
    puts "  -> Tool: #{event.data[:tool]} #{event.data[:arguments]}"
  end
end

puts "=" * 60
puts "Customer Support Agent"
puts "=" * 60
puts "Type 'quit' to exit"
puts

loop do
  print "\nYou: "
  input = gets&.chomp
  break if input.nil? || input.downcase == "quit"
  next if input.empty?

  begin
    result = runner.run(input: {
      message: input,
      customer_id: "CUST-001"
    })

    puts "\nAgent: #{result.output[:response]}"
    if result.output[:triage].is_a?(Hash)
      puts "  [Category: #{result.output[:triage][:category]}, Urgency: #{result.output[:triage][:urgency]}]"
    end
  rescue => e
    puts "\nError: #{e.message}"
    puts e.backtrace.first(3).join("\n") if ENV["DEBUG"]
  end
end

puts "\nGoodbye!"
