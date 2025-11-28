# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module MCP
        class Client
          @connections = {}

          class << self
            # Get or create client for server config
            def for(server_config)
              cache_key = server_config.url || server_config.command.to_s
              @connections[cache_key] ||= build_client(server_config)
            end

            # List tools from server
            def tools(server_config)
              client = self.for(server_config)
              client.tools
            end

            # Call tool on server
            def call_tool(server_config, tool_name, arguments)
              client = self.for(server_config)
              tool = client.tools.find { |t| t.name == tool_name }
              raise DurableWorkflow::ExecutionError, "MCP tool not found: #{tool_name}" unless tool

              client.call_tool(tool: tool, arguments: arguments)
            end

            # Clear connection cache
            def reset!
              @connections = {}
            end

            private

            def build_client(server_config)
              transport = build_transport(server_config)
              ::MCP::Client.new(transport: transport)
            end

            def build_transport(server_config)
              case server_config.transport&.to_sym
              when :stdio
                build_stdio_transport(server_config)
              else
                build_http_transport(server_config)
              end
            end

            def build_http_transport(config)
              ::MCP::Client::HTTP.new(
                url: config.url,
                headers: interpolate_env(config.headers || {})
              )
            end

            def build_stdio_transport(config)
              # Stdio transport for command-line MCP servers
              # This would require implementing or using a stdio transport
              raise NotImplementedError, "Stdio transport not yet implemented"
            end

            # Replace ${ENV_VAR} with actual values
            def interpolate_env(headers)
              headers.transform_values do |v|
                v.to_s.gsub(/\$\{(\w+)\}/) { ENV.fetch(::Regexp.last_match(1), "") }
              end
            end
          end
        end
      end
    end
  end
end
