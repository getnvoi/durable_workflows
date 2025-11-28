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
            when "guardrail"
              check_ref(step.id, "on_fail", cfg.on_fail, valid_ids) if cfg.respond_to?(:on_fail)
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
          # Handle assign step's `set` hash
          if step.config.respond_to?(:set) && step.config.set.is_a?(Hash)
            step.config.set.keys.each { |k| available << k.to_sym }
          end

          # Handle output attribute
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
          when "guardrail"
            steps << step.config.on_fail if step.config.respond_to?(:on_fail) && step.config.on_fail
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
            props = Utils.fetch(current, :properties)
            unless props
              @errors << "Step '#{step_id}': '$#{full_ref}' — schema has no properties"
              return
            end

            prop = Utils.fetch(props, segment)
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
            when "guardrail"
              queue << cfg.on_fail if cfg.respond_to?(:on_fail) && cfg.on_fail
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
