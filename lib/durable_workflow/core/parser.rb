# frozen_string_literal: true

require 'yaml'

module DurableWorkflow
  module Core
    class Parser
      # Hook system for extensions
      @before_hooks = []
      @after_hooks = []
      @config_transformers = {}

      class << self
        attr_reader :before_hooks, :after_hooks, :config_transformers

        def parse(source)
          new.parse(source)
        end

        # Register a before-parse hook (receives raw YAML hash)
        def before_parse(&block)
          @before_hooks << block
        end

        # Register an after-parse hook (receives WorkflowDef, can return modified)
        def after_parse(&block)
          @after_hooks << block
        end

        # Register a config transformer for a step type
        def transform_config(type, &block)
          @config_transformers[type.to_s] = block
        end

        # Reset hooks (for testing)
        def reset_hooks!
          @before_hooks = []
          @after_hooks = []
          @config_transformers = {}
        end
      end

      def parse(source)
        yaml = load_yaml(source)

        # Run before hooks
        self.class.before_hooks.each { |hook| yaml = hook.call(yaml) || yaml }

        workflow = build_workflow(yaml)

        # Run after hooks - pass both workflow and raw yaml for extension data
        self.class.after_hooks.each { |hook| workflow = hook.call(workflow, yaml) || workflow }

        workflow
      end

      private

      def load_yaml(source)
        raw = case source
              when Hash then source
              when String
                source.include?("\n") ? YAML.safe_load(source) : YAML.load_file(source)
              else
                raise Error, "Invalid source: #{source.class}"
              end
        DurableWorkflow::Utils.deep_symbolize(raw)
      end

      def build_workflow(y)
        WorkflowDef.new(
          id: y.fetch(:id),
          name: y.fetch(:name),
          version: y[:version],
          description: y[:description],
          timeout: y[:timeout],
          inputs: parse_inputs(y[:inputs]),
          steps: parse_steps(y.fetch(:steps)),
          extensions: {} # Extensions populate this via after_parse hooks
        )
      end

      def parse_inputs(inputs)
        return [] unless inputs

        inputs.map do |name, cfg|
          cfg ||= {}
          InputDef.new(
            name: name.to_s,
            type: cfg[:type],
            required: cfg.fetch(:required, true),
            default: cfg[:default],
            description: cfg[:description]
          )
        end
      end

      def parse_steps(steps)
        steps.map { parse_step(_1) }
      end

      def parse_step(s)
        type = s.fetch(:type)
        raw_config = extract_config(s)
        config = build_typed_config(type, raw_config)

        StepDef.new(
          id: s.fetch(:id),
          type:,
          config:,
          next_step: s[:next],
          on_error: s[:on_error]
        )
      rescue Dry::Struct::Error => e
        raise ValidationError, "Invalid config for step '#{s[:id]}': #{e.message}"
      end

      def build_typed_config(type, raw_config)
        # Check for extension transformer first
        if (transformer = self.class.config_transformers[type])
          raw_config = transformer.call(raw_config)
        end

        # Find config class from registry
        config_class = Core.config_registry[type]

        config_class ? config_class.new(raw_config) : raw_config
      end

      def extract_config(s)
        base = s.except(:id, :type, :next, :on_error)

        case s[:type]
        when 'call'
          # Rename method -> method_name to avoid collision with Ruby's Object#method
          base[:method_name] = base.delete(:method) if base.key?(:method)
          # Handle output with schema
          base[:output] = parse_output(base[:output]) if base[:output]
        when 'router'
          base[:routes] = parse_routes(base[:routes])
        when 'loop'
          base[:while] = parse_condition(base[:while]) if base[:while]
          base[:do] = base[:do]&.map { parse_step(_1) }
        when 'parallel'
          base[:branches] = base[:branches]&.map { parse_step(_1) }
        end

        base
      end

      def parse_output(output)
        case output
        when Hash
          if output.key?(:key) || output.key?(:schema)
            OutputConfig.new(
              key: output[:key] || output[:name],
              schema: output[:schema]
            )
          else
            output
          end
        when String, Symbol
          output.to_sym
        else
          output
        end
      end

      def parse_routes(routes)
        return [] unless routes

        routes.map do |r|
          Route.new(
            field: r.dig(:when, :field),
            op: r.dig(:when, :op),
            value: r.dig(:when, :value),
            target: r[:then]
          )
        end
      end

      def parse_condition(c)
        return nil unless c

        Condition.new(field: c[:field], op: c[:op], value: c[:value])
      end
    end
  end
end
