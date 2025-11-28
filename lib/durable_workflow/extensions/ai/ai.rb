# frozen_string_literal: true

require "ruby_llm"
require "mcp"

require_relative "types"
require_relative "configuration"
require_relative "tool_registry"

# MCP components
require_relative "mcp/client"
require_relative "mcp/adapter"
require_relative "mcp/server"
require_relative "mcp/rack_app"

require_relative "executors/agent"
require_relative "executors/guardrail"
require_relative "executors/handoff"
require_relative "executors/file_search"
require_relative "executors/mcp"

module DurableWorkflow
  module Extensions
    module AI
      class Extension < Base
        self.extension_name = "ai"

        def self.register_configs
          Core.register_config("agent", AgentConfig)
          Core.register_config("guardrail", GuardrailConfig)
          Core.register_config("handoff", HandoffConfig)
          Core.register_config("file_search", FileSearchConfig)
          Core.register_config("mcp", MCPConfig)
        end

        def self.register_executors
          Core::Executors::Registry.register("agent", Executors::Agent)
          Core::Executors::Registry.register("guardrail", Executors::Guardrail)
          Core::Executors::Registry.register("handoff", Executors::Handoff)
          Core::Executors::Registry.register("file_search", Executors::FileSearch)
          Core::Executors::Registry.register("mcp", Executors::MCP)
        end

        def self.register_parser_hooks
          Core::Parser.after_parse do |workflow, raw_yaml|
            raw = raw_yaml || workflow.to_h
            ai_data = {
              agents: parse_agents(raw[:agents]),
              tools: parse_tools(raw[:tools]),
              mcp_servers: parse_mcp_servers(raw)
            }

            # Register tools in ToolRegistry
            ai_data[:tools].each_value { |td| ToolRegistry.register_from_def(td) }

            # Return workflow with AI data stored
            store_in(workflow, ai_data)
          end
        end

        def self.parse_agents(agents)
          return {} unless agents

          agents.each_with_object({}) do |a, h|
            agent = AgentDef.new(
              id: a[:id],
              name: a[:name],
              model: a[:model],
              instructions: a[:instructions],
              tools: a[:tools] || [],
              handoffs: parse_handoffs(a[:handoffs])
            )
            h[agent.id] = agent
          end
        end

        def self.parse_handoffs(handoffs)
          return [] unless handoffs

          handoffs.map do |hd|
            HandoffDef.new(
              agent_id: hd[:agent_id],
              description: hd[:description]
            )
          end
        end

        def self.parse_tools(tools)
          return {} unless tools

          tools.each_with_object({}) do |t, h|
            tool = ToolDef.new(
              id: t[:id],
              description: t[:description],
              parameters: parse_tool_params(t[:parameters]),
              service: t[:service],
              method_name: t[:method]
            )
            h[tool.id] = tool
          end
        end

        def self.parse_tool_params(params)
          return [] unless params

          params.map do |p|
            ToolParam.new(
              name: p[:name],
              type: p[:type],
              required: p.fetch(:required, true),
              description: p[:description]
            )
          end
        end

        def self.parse_mcp_servers(raw)
          return {} unless raw[:mcp_servers]

          raw[:mcp_servers].transform_values do |config|
            MCPServerConfig.new(
              url: config[:url],
              headers: config[:headers],
              transport: config[:transport]&.to_sym,
              command: config[:command]
            )
          end
        end

        # Helper to get agents from workflow
        def self.agents(workflow)
          data_from(workflow)[:agents] || {}
        end

        # Helper to get tools from workflow
        def self.tools(workflow)
          data_from(workflow)[:tools] || {}
        end

        # Helper to get mcp_servers from workflow
        def self.mcp_servers(workflow)
          data_from(workflow)[:mcp_servers] || {}
        end
      end
    end
  end
end

# Auto-register
DurableWorkflow::Extensions.register(:ai, DurableWorkflow::Extensions::AI::Extension)
