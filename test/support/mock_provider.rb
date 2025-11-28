# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      # Mock for testing AI executors - simulates RubyLLM chat interface
      class MockChat
        attr_accessor :responses, :call_count, :last_messages, :last_tools

        def initialize
          @responses = []
          @call_count = 0
          @last_messages = nil
          @last_tools = nil
        end

        # Simulates RubyLLM chat.ask
        def ask(message, tools: nil, &block)
          @call_count += 1
          @last_messages = message
          @last_tools = tools

          response = @responses.shift || MockResponse.new(content: "Mock response")

          # Simulate streaming if block given
          yield response.content if block && response.content

          response
        end

        # Add tool to chat (chainable)
        def with_tool(tool_class)
          @tools ||= []
          @tools << tool_class
          self
        end

        def with_tools(*tool_classes)
          tool_classes.each { |tc| with_tool(tc) }
          self
        end

        def queue_response(content: nil, tool_calls: [])
          @responses << MockResponse.new(content: content, tool_calls: tool_calls)
        end

        def queue_tool_call(id:, name:, arguments: {})
          @responses << MockResponse.new(
            content: nil,
            tool_calls: [{ id: id, name: name, arguments: arguments }]
          )
        end
      end

      # Mock response that mimics RubyLLM response structure
      class MockResponse
        attr_reader :content, :tool_calls

        def initialize(content: nil, tool_calls: [])
          @content = content
          @tool_calls = tool_calls
        end

        def tool_calls?
          tool_calls&.any?
        end

        # RubyLLM uses tool_call? (singular)
        alias tool_call? tool_calls?
      end

      # Mock MCP response
      MockMCPResponse = Struct.new(:content, keyword_init: true) do
        def initialize(content)
          super(content: content)
        end
      end

      # Mock moderation result
      MockModerationResult = Struct.new(:flagged, keyword_init: true)
    end
  end
end
