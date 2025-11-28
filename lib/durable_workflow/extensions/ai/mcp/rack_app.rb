# frozen_string_literal: true

require 'json'
require 'rack'

module DurableWorkflow
  module Extensions
    module AI
      module MCP
        class RackApp
          def initialize(server)
            @server = server
          end

          def call(env)
            request = Rack::Request.new(env)

            case request.request_method
            when 'POST'
              handle_post(request)
            when 'GET'
              handle_sse(request)
            when 'DELETE'
              handle_delete(request)
            else
              [405, { 'Content-Type' => 'text/plain' }, ['Method not allowed']]
            end
          end

          private

          def handle_post(request)
            body = request.body.read
            result = @server.handle_json(body)

            [200, { 'Content-Type' => 'application/json' }, [result]]
          rescue JSON::ParserError => e
            error_response(-32_700, "Parse error: #{e.message}")
          rescue StandardError
            error_response(-32_603, 'Internal error')
          end

          def handle_sse(_request)
            # SSE for notifications (optional)
            [501, { 'Content-Type' => 'text/plain' }, ['SSE not implemented']]
          end

          def handle_delete(_request)
            # Session cleanup
            [200, {}, ['']]
          end

          def error_response(code, message)
            [400, { 'Content-Type' => 'application/json' }, [
              JSON.generate({
                              jsonrpc: '2.0',
                              error: { code: code, message: message },
                              id: nil
                            })
            ]]
          end
        end
      end
    end
  end
end
