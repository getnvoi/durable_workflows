# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      # Module to hold dynamically generated RubyLLM::Tool classes
      module GeneratedTools
      end

      # Message role enum (AI-specific, not in core)
      module Types
        MessageRole = DurableWorkflow::Types::Strict::String.enum("system", "user", "assistant", "tool")
      end

      # Handoff definition
      class HandoffDef < BaseStruct
        attribute :agent_id, DurableWorkflow::Types::Strict::String
        attribute? :description, DurableWorkflow::Types::Strict::String.optional
      end

      # Agent definition
      class AgentDef < BaseStruct
        attribute :id, DurableWorkflow::Types::Strict::String
        attribute? :name, DurableWorkflow::Types::Strict::String.optional
        attribute :model, DurableWorkflow::Types::Strict::String
        attribute? :instructions, DurableWorkflow::Types::Strict::String.optional
        attribute :tools, DurableWorkflow::Types::Strict::Array.of(DurableWorkflow::Types::Strict::String).default([].freeze)
        attribute :handoffs, DurableWorkflow::Types::Strict::Array.of(HandoffDef).default([].freeze)
      end

      # Tool parameter
      class ToolParam < BaseStruct
        attribute :name, DurableWorkflow::Types::Strict::String
        attribute? :type, DurableWorkflow::Types::Strict::String.optional.default("string")
        attribute? :required, DurableWorkflow::Types::Strict::Bool.default(true)
        attribute? :description, DurableWorkflow::Types::Strict::String.optional
      end

      # Tool definition
      class ToolDef < BaseStruct
        attribute :id, DurableWorkflow::Types::Strict::String
        attribute :description, DurableWorkflow::Types::Strict::String
        attribute :parameters, DurableWorkflow::Types::Strict::Array.of(ToolParam).default([].freeze)
        attribute :service, DurableWorkflow::Types::Strict::String
        attribute :method_name, DurableWorkflow::Types::Strict::String

        def to_function_schema
          {
            name: id,
            description:,
            parameters: {
              type: "object",
              properties: parameters.each_with_object({}) do |p, h|
                h[p.name] = { type: p.type, description: p.description }.compact
              end,
              required: parameters.select(&:required).map(&:name)
            }
          }
        end

        # Convert to RubyLLM::Tool class
        def to_ruby_llm_tool
          tool_def = self
          class_name = id.split("_").map(&:capitalize).join
          short_name = id  # Use the tool id as the name (e.g., "classify_request")

          # Create named class under GeneratedTools module
          AI::GeneratedTools.const_set(class_name, Class.new(RubyLLM::Tool) do
            # Store reference to original definition
            @tool_def = tool_def

            # Set description
            description tool_def.description

            # Override name to avoid long namespace in tool name
            define_method(:name) { short_name }

            # Define parameters
            tool_def.parameters.each do |p|
              param p.name.to_sym,
                    type: p.type.to_sym,
                    desc: p.description,
                    required: p.required
            end

            # Execute calls the service method
            define_method(:execute) do |**args|
              svc = Object.const_get(tool_def.service)
              svc.public_send(tool_def.method_name, **args)
            end

            class << self
              attr_reader :tool_def
            end
          end)
        end
      end

      # Tool call from LLM
      class ToolCall < BaseStruct
        attribute :id, DurableWorkflow::Types::Strict::String
        attribute :name, DurableWorkflow::Types::Strict::String
        attribute :arguments, DurableWorkflow::Types::Hash.default({}.freeze)
      end

      # Message in conversation
      class Message < BaseStruct
        attribute :role, Types::MessageRole
        attribute? :content, DurableWorkflow::Types::Strict::String.optional
        attribute? :tool_calls, DurableWorkflow::Types::Strict::Array.of(ToolCall).optional
        attribute? :tool_call_id, DurableWorkflow::Types::Strict::String.optional
        attribute? :name, DurableWorkflow::Types::Strict::String.optional

        def self.system(content)
          new(role: "system", content:)
        end

        def self.user(content)
          new(role: "user", content:)
        end

        def self.assistant(content, tool_calls: nil)
          new(role: "assistant", content:, tool_calls:)
        end

        def self.tool(content, tool_call_id:, name: nil)
          new(role: "tool", content:, tool_call_id:, name:)
        end

        def system? = role == "system"
        def user? = role == "user"
        def assistant? = role == "assistant"
        def tool? = role == "tool"
        def tool_calls? = tool_calls&.any?
      end

      # LLM response
      class Response < BaseStruct
        attribute? :content, DurableWorkflow::Types::Strict::String.optional
        attribute :tool_calls, DurableWorkflow::Types::Strict::Array.of(ToolCall).default([].freeze)
        attribute? :finish_reason, DurableWorkflow::Types::Strict::String.optional
        attribute? :usage, DurableWorkflow::Types::Hash.optional

        def tool_calls? = tool_calls.any?
      end

      # Moderation result
      class ModerationResult < BaseStruct
        attribute :flagged, DurableWorkflow::Types::Strict::Bool
        attribute? :categories, DurableWorkflow::Types::Hash.optional
        attribute? :scores, DurableWorkflow::Types::Hash.optional
      end

      # Guardrail check
      class GuardrailCheck < BaseStruct
        attribute :type, DurableWorkflow::Types::Strict::String
        attribute? :pattern, DurableWorkflow::Types::Strict::String.optional
        attribute? :block_on_match, DurableWorkflow::Types::Strict::Bool.default(true)
        attribute? :max, DurableWorkflow::Types::Strict::Integer.optional
        attribute? :min, DurableWorkflow::Types::Strict::Integer.optional
      end

      # Guardrail result
      class GuardrailResult < BaseStruct
        attribute :passed, DurableWorkflow::Types::Strict::Bool
        attribute :check_type, DurableWorkflow::Types::Strict::String
        attribute? :reason, DurableWorkflow::Types::Strict::String.optional
      end

      # AI Step Configs
      class AgentConfig < Core::StepConfig
        attribute :agent_id, DurableWorkflow::Types::Strict::String
        attribute :prompt, DurableWorkflow::Types::Strict::String
        attribute :output, DurableWorkflow::Types::Coercible::Symbol
      end

      class GuardrailConfig < Core::StepConfig
        attribute? :content, DurableWorkflow::Types::Strict::String.optional
        attribute? :input, DurableWorkflow::Types::Strict::String.optional
        attribute :checks, DurableWorkflow::Types::Strict::Array.default([].freeze)
        attribute? :on_fail, DurableWorkflow::Types::Strict::String.optional
      end

      class HandoffConfig < Core::StepConfig
        attribute? :to, DurableWorkflow::Types::Strict::String.optional
        attribute? :from, DurableWorkflow::Types::Strict::String.optional
        attribute? :reason, DurableWorkflow::Types::Strict::String.optional
      end

      class FileSearchConfig < Core::StepConfig
        attribute :query, DurableWorkflow::Types::Strict::String
        attribute :files, DurableWorkflow::Types::Strict::Array.of(DurableWorkflow::Types::Strict::String).default([].freeze)
        attribute? :max_results, DurableWorkflow::Types::Strict::Integer.optional.default(10)
        attribute? :output, DurableWorkflow::Types::Coercible::Symbol.optional
      end

      class MCPConfig < Core::StepConfig
        attribute :server, DurableWorkflow::Types::Strict::String
        attribute :tool, DurableWorkflow::Types::Strict::String
        attribute? :arguments, DurableWorkflow::Types::Hash.default({}.freeze)
        attribute? :output, DurableWorkflow::Types::Coercible::Symbol.optional
      end

      # MCP Server configuration for consuming external MCP servers
      class MCPServerConfig < BaseStruct
        attribute? :url, DurableWorkflow::Types::Strict::String.optional
        attribute? :headers, DurableWorkflow::Types::Hash.default({}.freeze)
        attribute? :transport, DurableWorkflow::Types::Coercible::Symbol.default(:http)
        attribute? :command, DurableWorkflow::Types::Strict::Array.of(DurableWorkflow::Types::Strict::String).optional
      end
    end
  end
end
