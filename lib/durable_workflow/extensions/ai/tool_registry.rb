# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      class ToolRegistry
        class << self
          def registry
            @registry ||= {}
          end

          # Register a RubyLLM::Tool class directly
          def register(tool_class)
            name = tool_name(tool_class)
            registry[name] = tool_class
          end

          # Register from ToolDef (YAML-defined)
          def register_from_def(tool_def)
            tool_class = tool_def.to_ruby_llm_tool
            registry[tool_def.id] = tool_class
          end

          # Get tool class by name
          def [](name)
            registry[name.to_s]
          end

          # Get all tool classes
          def all
            registry.values
          end

          # Get tools for a workflow
          def for_workflow(workflow)
            tool_ids = Extension.data_from(workflow)[:tools]&.keys || []
            for_tool_ids(tool_ids)
          end

          # Get tool instances by IDs
          def for_tool_ids(tool_ids)
            tool_ids.map { |id| registry[id.to_s]&.new }.compact
          end

          # Clear registry (for testing)
          def reset!
            @registry = {}
          end

          private

          def tool_name(tool_class)
            if tool_class.respond_to?(:tool_def) && tool_class.tool_def
              tool_class.tool_def.id
            else
              tool_class.name&.split("::")&.last&.gsub(/([A-Z])/, '_\1')&.downcase&.sub(/^_/, "") || "unknown"
            end
          end
        end
      end
    end
  end
end
