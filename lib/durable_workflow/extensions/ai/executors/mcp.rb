# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module Executors
        class MCP < Core::Executors::Base
          def call(state)
            server_config = resolve_server(state, config.server)
            tool_name = config.tool
            arguments = resolve(state, config.arguments)

            result = AI::MCP::Client.call_tool(server_config, tool_name, arguments)

            # Extract text content from MCP response
            output = extract_output(result)

            state = store(state, config.output, output) if config.output
            continue(state, output: output)
          end

          private

            def resolve_server(state, server_id)
              servers = Extension.mcp_servers(workflow(state))
              server_config = Utils.fetch(servers, server_id)
              raise ExecutionError, "MCP server not found: #{server_id}" unless server_config
              server_config
            end

            def workflow(state)
              DurableWorkflow.registry[state.workflow_id]
            end

            def extract_output(result)
              if result.respond_to?(:content)
                result.content.map { |c| Utils.fetch(c, :text) }.compact.join("\n")
              else
                result.to_s
              end
            end
        end
      end
    end
  end
end
