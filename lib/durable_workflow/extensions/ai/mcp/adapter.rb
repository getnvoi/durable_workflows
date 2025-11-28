# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module MCP
        class Adapter
          class << self
            # Convert RubyLLM::Tool instance to MCP::Tool
            def to_mcp_tool(ruby_llm_tool)
              tool_name = extract_name(ruby_llm_tool)
              tool_description = ruby_llm_tool.description
              tool_schema = ruby_llm_tool.class.respond_to?(:params_schema) ? ruby_llm_tool.class.params_schema : {}

              captured_tool = ruby_llm_tool
              adapter = self # Capture Adapter class for use in block

              ::MCP::Tool.define(
                name: tool_name,
                description: tool_description,
                input_schema: normalize_schema(tool_schema)
              ) do |server_context:, **params|
                adapter.execute_tool(captured_tool, params, server_context)
              end
            end

            def execute_tool(tool, params, server_context)
              result = tool.call(**params.transform_keys(&:to_sym))
              formatted = format_result(result)

              ::MCP::Tool::Response.new([
                { type: "text", text: formatted }
              ])
            rescue StandardError => e
              ::MCP::Tool::Response.new([
                { type: "text", text: "Error: #{e.message}" }
              ], is_error: true)
            end

            private

            def extract_name(tool)
              if tool.class.respond_to?(:tool_def) && tool.class.tool_def
                tool.class.tool_def.id
              elsif tool.respond_to?(:name)
                tool.name
              else
                tool.class.name&.split("::")&.last&.gsub(/([A-Z])/, '_\1')&.downcase&.sub(/^_/, "") || "unknown"
              end
            end

            def normalize_schema(schema)
              return { properties: {}, required: [] } if schema.nil? || schema.empty?
              {
                properties: Utils.fetch(schema, :properties, {}),
                required: Utils.fetch(schema, :required, [])
              }
            end

            def format_result(result)
              case result
              when String then result
              when Hash, Array then JSON.pretty_generate(result)
              else result.to_s
              end
            end
          end
        end
      end
    end
  end
end
