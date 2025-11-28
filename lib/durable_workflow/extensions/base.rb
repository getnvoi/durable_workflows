# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    # Base class for extensions
    # Extensions inherit from this and call register! to set up
    class Base
      class << self
        # Extension name (used as key in workflow.extensions)
        def extension_name
          @extension_name ||= (name ? name.split("::").last.downcase : "anonymous")
        end

        def extension_name=(name)
          @extension_name = name
        end

        # Register all components of the extension
        def register!
          register_configs
          register_executors
          register_parser_hooks
        end

        # Override in subclass to register config classes
        def register_configs
          # Example:
          # DurableWorkflow::Core.register_config("agent", AgentConfig)
        end

        # Override in subclass to register executors
        def register_executors
          # Example:
          # DurableWorkflow::Core::Executors::Registry.register("agent", AgentExecutor)
        end

        # Override in subclass to register parser hooks
        def register_parser_hooks
          # Example:
          # DurableWorkflow::Core::Parser.after_parse { |wf| ... }
        end

        # Helper to get extension data from workflow
        def data_from(workflow)
          workflow.extensions[extension_name.to_sym] || {}
        end

        # Helper to store extension data in workflow
        def store_in(workflow, data)
          workflow.with(extensions: workflow.extensions.merge(extension_name.to_sym => data))
        end
      end
    end

    # Registry of loaded extensions
    @extensions = {}

    class << self
      attr_reader :extensions

      def register(name, extension_class)
        @extensions[name.to_sym] = extension_class
        extension_class.register!
      end

      def [](name)
        @extensions[name.to_sym]
      end

      def loaded?(name)
        @extensions.key?(name.to_sym)
      end

      def reset!
        @extensions = {}
      end
    end
  end
end
