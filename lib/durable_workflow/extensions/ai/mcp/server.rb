# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module MCP
        class Server
          attr_reader :workflow, :options

          def initialize(workflow, **options)
            @workflow = workflow
            @options = options
          end

          # Build MCP::Server with workflow tools
          def build(server_context: {})
            ::MCP::Server.new(
              name: server_name,
              version: server_version,
              tools: build_tools,
              server_context: server_context
            )
          end

          # Run as stdio transport (for Claude Desktop)
          def stdio(server_context: {})
            require "mcp/server/transports/stdio_transport"
            server = build(server_context: server_context)
            transport = ::MCP::Server::Transports::StdioTransport.new(server)
            transport.open
          end

          # Build Rack app for HTTP transport
          def rack_app(server_context: {})
            server = build(server_context: server_context)
            RackApp.new(server)
          end

          class << self
            def build(workflow, **options)
              new(workflow, **options).build
            end

            def stdio(workflow, **options)
              new(workflow, **options).stdio
            end

            def rack_app(workflow, **options)
              new(workflow, **options).rack_app
            end
          end

          private

          def server_name
            options[:name] || "durable_workflow_#{workflow.id}"
          end

          def server_version
            options[:version] || DurableWorkflow::VERSION
          end

          def build_tools
            mcp_tools = []

            # Convert workflow tools to MCP tools
            # for_workflow returns instances, not classes
            ToolRegistry.for_workflow(workflow).each do |tool_instance|
              mcp_tools << Adapter.to_mcp_tool(tool_instance)
            end

            # Optionally expose workflow itself as a tool
            if options[:expose_workflow]
              mcp_tools << build_workflow_tool
            end

            mcp_tools
          end

          def build_workflow_tool
            wf = workflow
            store = DurableWorkflow.config&.store

            ::MCP::Tool.define(
              name: "run_#{workflow.id}",
              description: workflow.description || "Run #{workflow.name} workflow",
              input_schema: workflow_input_schema
            ) do |server_context:, **params|
              begin
                runner = DurableWorkflow::Runners::Sync.new(wf, store: store)
                result = runner.run(params)

                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: JSON.pretty_generate({
                    status: result.status,
                    output: result.output
                  })
                }])
              rescue StandardError => e
                $stderr.puts "Workflow error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
                ::MCP::Tool::Response.new([{
                  type: "text",
                  text: "Error: #{e.message}"
                }], is_error: true)
              end
            end
          end

          def workflow_input_schema
            props = {}
            required = []

            (workflow.inputs || []).each do |input_def|
              props[input_def.name] = {
                type: input_def.type,
                description: input_def.description
              }.compact
              required << input_def.name if input_def.required
            end

            { properties: props, required: required }
          end
        end
      end
    end
  end
end
