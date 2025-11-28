#!/usr/bin/env ruby
# frozen_string_literal: true

# File Search Demo
# Demonstrates the file_search step type with dummy results

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/extensions/ai"
require "durable_workflow/storage/redis"

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
  c.logger = Logger.new($stdout, level: Logger::INFO)
end

# Define workflow inline using YAML
workflow_yaml = <<~YAML
  id: file_search_demo
  name: File Search Demo
  version: "1.0"
  description: Search documentation files

  inputs:
    query:
      type: string
      required: true
      description: Search query

  steps:
    - id: start
      type: start
      next: search_docs

    - id: search_docs
      type: file_search
      query: "$input.query"
      files:
        - docs/getting_started.md
        - docs/configuration.md
        - docs/api_reference.md
        - docs/troubleshooting.md
      max_results: 3
      output: search_results
      next: format_results

    - id: format_results
      type: assign
      set:
        summary: "Found results for query"
      next: end

    - id: end
      type: end
      result:
        query: "$input.query"
        results: "$search_results.results"
        total: "$search_results.total"
        summary: "$summary"
YAML

workflow = DurableWorkflow.load(workflow_yaml)
runner = DurableWorkflow::Runners::Sync.new(workflow)

puts "=" * 60
puts "File Search Demo"
puts "=" * 60

result = runner.run(input: { query: "how to configure logging" })

puts "\nSearch Query: #{result.output[:query]}"
puts "Total Results: #{result.output[:total]}"
puts "\nResults:"
result.output[:results].each_with_index do |r, idx|
  puts "  #{idx + 1}. #{r[:file]} (score: #{r[:score]})"
  puts "     #{r[:snippet]}"
end
