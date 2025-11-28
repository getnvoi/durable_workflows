# 05-PARSER: Parser with Schema Validation Support

## Goal

Implement the YAML parser with:

1. Hook system for extensions to inject parsing logic
2. Schema validation support for outputs
3. Variable reachability checking

## Dependencies

- 01-GEMSPEC completed
- 02-TYPES completed
- 03-EXECUTION completed

## Files to Create

### 1. `lib/durable_workflow/core/types/configs.rb` (Update - add OutputConfig)

Add to the existing configs.rb:

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    # ... existing StepConfig class ...

    # Output with optional schema validation
    class OutputConfig < BaseStruct
      attribute :key, Types::Coercible::Symbol
      attribute? :schema, Types::Hash.optional
    end

    # Update CallConfig to support schema'd output
    class CallConfig < StepConfig
      attribute :service, Types::Strict::String
      attribute :method_name, Types::Strict::String
      attribute? :input, Types::Any
      attribute? :output, Types::Coercible::Symbol.optional | OutputConfig
      attribute? :timeout, Types::Strict::Integer.optional
      attribute? :retries, Types::Strict::Integer.optional.default(0)
      attribute? :retry_delay, Types::Strict::Float.optional.default(1.0)
      attribute? :retry_backoff, Types::Strict::Float.optional.default(2.0)
    end

    # ... rest of existing configs ...
  end
end
```

### 2. `lib/durable_workflow/core/parser.rb`

```ruby
# frozen_string_literal: true

require "yaml"

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
      end

      def parse(source)
        yaml = load_yaml(source)

        # Run before hooks
        self.class.before_hooks.each { |hook| yaml = hook.call(yaml) || yaml }

        workflow = build_workflow(yaml)

        # Run after hooks
        self.class.after_hooks.each { |hook| workflow = hook.call(workflow) || workflow }

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
            extensions: {}  # Extensions populate this via after_parse hooks
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

          # Find config class from core registry
          config_class = CONFIG_REGISTRY[type]

          # If not found, check extension registries
          unless config_class
            # Extensions register their configs via Core.register_config
            config_class = CONFIG_REGISTRY[type]
          end

          config_class ? config_class.new(raw_config) : raw_config
        end

        def extract_config(s)
          base = s.reject { |k, _| %i[id type next on_error].include?(k) }

          case s[:type]
          when "call"
            # Rename method -> method_name to avoid collision with Ruby's Object#method
            base[:method_name] = base.delete(:method) if base.key?(:method)
            # Handle output with schema
            base[:output] = parse_output(base[:output]) if base[:output]
          when "router"
            base[:routes] = parse_routes(base[:routes])
          when "loop"
            base[:while] = parse_condition(base[:while]) if base[:while]
            base[:do] = base[:do]&.map { parse_step(_1) }
          when "parallel"
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
```

### 3. `lib/durable_workflow/core/validator.rb` (Enhanced)

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    class Validator
      FINISHED = "__FINISHED__"

      def self.validate!(workflow)
        new(workflow).validate!
      end

      def initialize(workflow)
        @workflow = workflow
        @errors = []
        @step_index = workflow.steps.to_h { [_1.id, _1] }
        @schemas = {}  # step_id -> output schema
      end

      def validate!
        check_unique_ids!
        check_step_types!
        check_references!
        check_variable_reachability!
        check_schema_compatibility!
        check_reachability!

        raise ValidationError, format_errors if @errors.any?
        true
      end

      def valid?
        validate!
      rescue ValidationError
        false
      end

      private

        # ─────────────────────────────────────────────────────────────
        # 0. Unique IDs
        # ─────────────────────────────────────────────────────────────

        def check_unique_ids!
          ids = @workflow.steps.map(&:id)
          dups = ids.group_by(&:itself).select { |_, v| v.size > 1 }.keys
          @errors << "Duplicate step IDs: #{dups.join(', ')}" if dups.any?
        end

        # ─────────────────────────────────────────────────────────────
        # 1. Step Types Registered
        # ─────────────────────────────────────────────────────────────

        def check_step_types!
          @workflow.steps.each do |step|
            unless Executors::Registry.registered?(step.type)
              @errors << "Unknown step type '#{step.type}' in step '#{step.id}'"
            end
          end
        end

        # ─────────────────────────────────────────────────────────────
        # 2. Step References Exist
        # ─────────────────────────────────────────────────────────────

        def check_references!
          valid_ids = @step_index.keys.to_set << FINISHED

          @workflow.steps.each do |step|
            check_ref(step.id, "next", step.next_step, valid_ids)
            check_ref(step.id, "on_error", step.on_error, valid_ids)

            cfg = step.config
            case step.type
            when "router"
              cfg.routes&.each_with_index { |r, i| check_ref(step.id, "route[#{i}]", r.target, valid_ids) }
              check_ref(step.id, "default", cfg.default, valid_ids)
            when "loop"
              check_ref(step.id, "on_exhausted", cfg.on_exhausted, valid_ids)
              cfg.do&.each { |s| check_ref(step.id, "loop.do", s.next_step, valid_ids) }
            when "parallel"
              cfg.branches&.each { |s| check_ref(step.id, "branch", s.next_step, valid_ids) }
            when "halt"
              check_ref(step.id, "resume_step", cfg.resume_step, valid_ids)
            when "approval"
              check_ref(step.id, "on_reject", cfg.on_reject, valid_ids)
              check_ref(step.id, "on_timeout", cfg.on_timeout, valid_ids) if cfg.respond_to?(:on_timeout)
            end
          end
        end

        def check_ref(step_id, field, target, valid_ids)
          return unless target
          return if valid_ids.include?(target)
          @errors << "Step '#{step_id}' #{field}: references unknown step '#{target}'"
        end

        # ─────────────────────────────────────────────────────────────
        # 3. Variable Reachability
        # ─────────────────────────────────────────────────────────────

        def check_variable_reachability!
          # Start with workflow inputs available
          initial = Set.new(@workflow.inputs.map { _1.name.to_sym })
          initial << :input  # $input always available
          initial << :now    # $now always available
          initial << :history # $history always available

          first = @workflow.first_step
          walk_steps(first, initial, Set.new) if first
        end

        def walk_steps(step, available, visited)
          return if step.nil?

          step_key = step.is_a?(String) ? step : step.id
          step = @step_index[step_key] if step.is_a?(String)
          return unless step
          return if visited.include?(step.id)

          visited = visited.dup << step.id

          # Check references in this step
          check_variable_references(step, available)

          # Collect output schema if present
          collect_schema(step)

          # Add output to available set
          available = available.dup
          add_step_output(step, available)

          # Recurse to all possible next steps
          next_steps_for(step).each do |next_id|
            walk_steps(next_id, available, visited)
          end
        end

        def check_variable_references(step, available)
          refs = extract_refs(step.config)

          refs.each do |ref|
            root = ref.split('.').first.to_sym
            next if available.include?(root)

            @errors << "Step '#{step.id}': references '$#{ref}' but '#{root}' not set by preceding step"
          end
        end

        def add_step_output(step, available)
          return unless step.config.respond_to?(:output) && step.config.output

          key = case step.config.output
          when Symbol, String then step.config.output
          when OutputConfig then step.config.output.key
          when Hash then step.config.output[:key]
          end

          available << key.to_sym if key
        end

        def next_steps_for(step)
          steps = []
          steps << step.next_step if step.next_step
          steps << step.on_error if step.on_error

          case step.type
          when "router"
            steps.concat(step.config.routes.map(&:target))
            steps << step.config.default if step.config.default
          when "loop"
            steps << step.config.on_exhausted if step.config.on_exhausted
          when "approval"
            steps << step.config.on_reject if step.config.on_reject
            steps << step.config.on_timeout if step.config.respond_to?(:on_timeout) && step.config.on_timeout
          end

          steps.compact.uniq
        end

        def extract_refs(obj, refs = [])
          case obj
          when String
            obj.scan(/\$([a-zA-Z_][a-zA-Z0-9_.]*)/).flatten.each { refs << _1 }
          when Hash
            obj.each_value { extract_refs(_1, refs) }
          when Array
            obj.each { extract_refs(_1, refs) }
          when BaseStruct
            obj.to_h.each_value { extract_refs(_1, refs) }
          end
          refs
        end

        # ─────────────────────────────────────────────────────────────
        # 4. Schema Compatibility
        # ─────────────────────────────────────────────────────────────

        def collect_schema(step)
          return unless step.config.respond_to?(:output)

          output = step.config.output
          schema = case output
          when OutputConfig then output.schema
          when Hash then output[:schema]
          end

          return unless schema

          key = case output
          when OutputConfig then output.key
          when Hash then output[:key]
          end

          @schemas[key.to_sym] = schema if key
        end

        def check_schema_compatibility!
          return if @schemas.empty?

          @workflow.steps.each do |step|
            refs = extract_refs(step.config)

            refs.each do |ref|
              parts = ref.split('.')
              root = parts.first.to_sym

              next unless @schemas.key?(root)
              next if parts.size == 1  # Just $foo, not $foo.bar

              validate_path_against_schema(step.id, ref, @schemas[root], parts[1..])
            end
          end
        end

        def validate_path_against_schema(step_id, full_ref, schema, path)
          current = schema

          path.each do |segment|
            props = current[:properties] || current["properties"]
            unless props
              @errors << "Step '#{step_id}': '$#{full_ref}' — schema has no properties"
              return
            end

            prop = props[segment.to_sym] || props[segment.to_s]
            unless prop
              available = props.keys.join(', ')
              @errors << "Step '#{step_id}': '$#{full_ref}' — '#{segment}' not in schema (available: #{available})"
              return
            end

            current = prop
          end
        end

        # ─────────────────────────────────────────────────────────────
        # 5. Reachability
        # ─────────────────────────────────────────────────────────────

        def check_reachability!
          return if @workflow.steps.empty?

          reachable = Set.new
          queue = [@workflow.first_step.id]

          while (id = queue.shift)
            next if reachable.include?(id) || id == FINISHED
            reachable << id
            step = @step_index[id]
            next unless step

            queue << step.next_step if step.next_step
            queue << step.on_error if step.on_error

            cfg = step.config
            case step.type
            when "router"
              cfg.routes&.each { |r| queue << r.target }
              queue << cfg.default if cfg.default
            when "loop"
              cfg.do&.each { |s| queue << s.id }
              queue << cfg.on_exhausted if cfg.on_exhausted
            when "parallel"
              cfg.branches&.each { |s| queue << s.id }
            when "approval"
              queue << cfg.on_reject if cfg.on_reject
              queue << cfg.on_timeout if cfg.respond_to?(:on_timeout) && cfg.on_timeout
            end
          end

          unreachable = @workflow.step_ids - reachable.to_a
          @errors << "Unreachable steps: #{unreachable.join(', ')}" if unreachable.any?
        end

        # ─────────────────────────────────────────────────────────────
        # Error Formatting
        # ─────────────────────────────────────────────────────────────

        def format_errors
          [
            "Workflow '#{@workflow.id}' validation failed:",
            *@errors.map { "  - #{_1}" }
          ].join("\n")
        end
    end
  end
end
```

### 4. `lib/durable_workflow/core/schema_validator.rb` (Runtime)

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    # Runtime JSON Schema validation (optional - requires json_schemer gem)
    class SchemaValidator
      def self.validate!(value, schema, context:)
        return true if schema.nil?

        begin
          require 'json_schemer'
        rescue LoadError
          # If json_schemer not available, skip runtime validation
          DurableWorkflow.log(:debug, "json_schemer not available, skipping runtime schema validation")
          return true
        end

        schemer = JSONSchemer.schema(normalize(schema))
        errors = schemer.validate(jsonify(value)).to_a

        return true if errors.empty?

        messages = errors.map { _1['error'] }.join('; ')
        raise ValidationError, "#{context}: #{messages}"
      end

      def self.normalize(schema)
        deep_stringify(schema)
      end

      def self.jsonify(value)
        JSON.parse(value.to_json)
      end

      def self.deep_stringify(obj)
        case obj
        when Hash
          obj.transform_keys(&:to_s).transform_values { deep_stringify(_1) }
        when Array
          obj.map { deep_stringify(_1) }
        else
          obj
        end
      end
    end
  end
end
```

### 5. Update `lib/durable_workflow/core/executors/call.rb` (Schema validation)

Add schema validation to the Call executor:

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Call < Base
        Registry.register("call", self)

        def call(state)
          svc = resolve_service(config.service)
          method = config.method_name
          input = resolve(state, config.input)

          result = with_retry(
            max_retries: config.retries,
            delay: config.retry_delay,
            backoff: config.retry_backoff
          ) do
            with_timeout { invoke(svc, method, input) }
          end

          # Runtime schema validation (if schema defined)
          validate_output!(result) if output_schema

          state = store(state, output_key, result)
          continue(state, output: result)
        end

        private

          def resolve_service(name)
            DurableWorkflow.config&.service_resolver&.call(name) || Object.const_get(name)
          end

          def invoke(svc, method, input)
            target = svc.respond_to?(method) ? svc : svc.new
            m = target.method(method)

            has_kwargs = m.parameters.any? { |type, _| type == :key || type == :keyreq || type == :keyrest }

            if has_kwargs && input.is_a?(Hash)
              m.call(**input.transform_keys(&:to_sym))
            elsif m.arity == 0
              m.call
            else
              m.call(input)
            end
          end

          def output_key
            case config.output
            when Symbol, String then config.output
            when OutputConfig then config.output.key
            when Hash then config.output[:key]
            end
          end

          def output_schema
            case config.output
            when OutputConfig then config.output.schema
            when Hash then config.output[:schema]
            end
          end

          def validate_output!(result)
            SchemaValidator.validate!(
              result,
              output_schema,
              context: "Step '#{step.id}' output"
            )
          end
      end
    end
  end
end
```

## Key Features

1. **Hook System** - Extensions register via `Parser.before_parse`, `Parser.after_parse`, `Parser.transform_config`
2. **No Monkey Patching** - AI extension uses hooks, not `alias_method`
3. **Schema'd Output** - `output: { key: order, schema: { ... } }` format supported
4. **Variable Reachability** - Validates `$refs` are set by preceding steps
5. **Schema Compatibility** - Validates `$order.name` against `order`'s schema
6. **Runtime Validation** - Optional json_schemer validation at execution time

## Example: Extension Registration

```ruby
# In extensions/ai/ai.rb

DurableWorkflow::Core::Parser.after_parse do |workflow|
  # Parse agents/tools from raw YAML and store in extensions
  # This runs after core parsing, so we modify the WorkflowDef
  workflow.with(extensions: workflow.extensions.merge(
    agents: parsed_agents,
    tools: parsed_tools
  ))
end
```

## Acceptance Criteria

1. `Parser.parse(yaml)` returns WorkflowDef
2. `Parser.after_parse { |wf| ... }` hooks are called
3. Variable references to undefined vars raise ValidationError
4. Schema path validation catches `$order.nonexistent`
5. Runtime schema validation works when json_schemer available
