#!/usr/bin/env ruby
# frozen_string_literal: true

# MCP Server for Claude Desktop integration
#
# Add to ~/.config/claude/claude_desktop_config.json:
# {
#   "mcpServers": {
#     "support_agent": {
#       "command": "ruby",
#       "args": ["examples/support_agent/mcp_server.rb"],
#       "cwd": "/path/to/durable_workflow"
#     }
#   }
# }

require "bundler/setup"
require "dotenv/load" if File.exist?(File.expand_path("../../.env", __dir__))
require "durable_workflow"
require "durable_workflow/extensions/ai"
require "durable_workflow/storage/redis"
require_relative "services"

# Suppress stdout logging (corrupts MCP protocol)
$stderr = File.open("/tmp/support_agent_mcp.log", "a")

# Configure
DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
  c.logger = Logger.new("/dev/null")
end

DurableWorkflow::Extensions::AI.configure do |c|
  c.api_keys[:openai] = ENV["OPENAI_API_KEY"]
  c.api_keys[:anthropic] = ENV["ANTHROPIC_API_KEY"]
end

# Services auto-resolved via Object.const_get

# Load and register workflow
workflow = DurableWorkflow.load(File.join(__dir__, "workflow.yml"))
DurableWorkflow.register(workflow)

# Run MCP server with workflow tools + workflow itself exposed
DurableWorkflow::Extensions::AI::MCP::Server.stdio(
  workflow,
  name: "support_agent",
  expose_workflow: true  # Makes "run_support_agent" available as a tool
)
