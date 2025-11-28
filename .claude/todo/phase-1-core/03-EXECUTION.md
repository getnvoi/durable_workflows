# 03-EXECUTION: Engine, Registry, Resolver, Condition

## Goal

Implement the execution infrastructure: Engine (orchestrates steps), Executor Registry (maps types to executors), Resolver (resolves $references), and ConditionEvaluator (evaluates routing conditions).

## Dependencies

- 01-GEMSPEC completed
- 02-TYPES completed

## Files to Create

### 1. `lib/durable_workflow/core/executors/registry.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Registry
        @executors = {}

        class << self
          def register(type, klass)
            @executors[type.to_s] = klass
          end

          def [](type)
            @executors[type.to_s]
          end

          def types
            @executors.keys
          end

          def registered?(type)
            @executors.key?(type.to_s)
          end
        end
      end

      # Convenience method for registration
      def self.register(type)
        ->(klass) { Registry.register(type, klass) }
      end
    end
  end
end
```

### 2. `lib/durable_workflow/core/executors/base.rb`

```ruby
# frozen_string_literal: true

require "timeout"

module DurableWorkflow
  module Core
    module Executors
      class Base
        attr_reader :step, :config

        def initialize(step)
          @step = step
          @config = step.config
        end

        # Executors receive state and return StepOutcome
        def call(state)
          raise NotImplementedError
        end

        private

          def next_step
            step.next_step
          end

          # Pure resolve - takes state explicitly
          def resolve(state, v)
            Resolver.resolve(state, v)
          end

          # Return StepOutcome with continue result
          def continue(state, next_step: nil, output: nil)
            StepOutcome.new(
              state:,
              result: ContinueResult.new(next_step: next_step || self.next_step, output:)
            )
          end

          # Return StepOutcome with halt result
          def halt(state, data: {}, resume_step: nil, prompt: nil)
            StepOutcome.new(
              state:,
              result: HaltResult.new(data:, resume_step: resume_step || next_step, prompt:)
            )
          end

          # Immutable store - returns new state
          def store(state, key, val)
            return state unless key
            state.with_ctx(key.to_sym => DurableWorkflow::Utils.deep_symbolize(val))
          end

          def with_timeout(seconds = nil, &block)
            timeout = seconds || config_timeout
            return yield unless timeout

            Timeout.timeout(timeout) { yield }
          rescue Timeout::Error
            raise ExecutionError, "Step '#{step.id}' timed out after #{timeout}s"
          end

          def with_retry(max_retries: 0, delay: 1.0, backoff: 2.0, &block)
            attempts = 0
            begin
              attempts += 1
              yield
            rescue => e
              if attempts <= max_retries
                sleep_time = delay * (backoff ** (attempts - 1))
                log(:warn, "Retry #{attempts}/#{max_retries} after #{sleep_time}s", error: e.message)
                sleep(sleep_time)
                retry
              end
              raise
            end
          end

          def config_timeout
            config.respond_to?(:timeout) ? config.timeout : nil
          end

          def log(level, msg, **data)
            DurableWorkflow.log(level, msg, step_id: step.id, step_type: step.type, **data)
          end
      end
    end
  end
end
```

### 3. `lib/durable_workflow/core/resolver.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    # Stateless resolver - all methods take state explicitly
    class Resolver
      PATTERN = /\$([a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)*)/

      class << self
        def resolve(state, value)
          case value
          when String then resolve_string(state, value)
          when Hash then value.transform_values { resolve(state, _1) }
          when Array then value.map { resolve(state, _1) }
          when nil then nil
          else value
          end
        end

        def resolve_ref(state, ref)
          parts = ref.split(".")
          root = parts.shift.to_sym

          base = case root
          when :input then state.input
          when :now then return Time.now
          when :history then return state.history
          else state.ctx[root]
          end

          dig(base, parts)
        end

        private

          def resolve_string(state, str)
            # Whole string is single reference -> return actual value (not stringified)
            return resolve_ref(state, str[1..]) if str.match?(/\A\$[a-zA-Z_][a-zA-Z0-9_.]*\z/)

            # Embedded references -> interpolate as strings
            str.gsub(PATTERN) { resolve_ref(state, _1[1..]).to_s }
          end

          def dig(value, keys)
            return value if keys.empty?
            key = keys.shift

            next_val = case value
            when Hash then value[key.to_sym] || value[key]
            when Array then key.match?(/\A\d+\z/) ? value[key.to_i] : nil
            when Struct then value.respond_to?(key) ? value.send(key) : nil
            else value.respond_to?(key) ? value.send(key) : nil
            end

            dig(next_val, keys)
          end
      end
    end
  end
end
```

### 4. `lib/durable_workflow/core/condition.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    # Stateless condition evaluator
    class ConditionEvaluator
      OPS = {
        "eq"          => ->(v, e) { v == e },
        "neq"         => ->(v, e) { v != e },
        "gt"          => ->(v, e) { v.to_f > e.to_f },
        "lt"          => ->(v, e) { v.to_f < e.to_f },
        "gte"         => ->(v, e) { v.to_f >= e.to_f },
        "lte"         => ->(v, e) { v.to_f <= e.to_f },
        "in"          => ->(v, e) { Array(e).include?(v) },
        "not_in"      => ->(v, e) { !Array(e).include?(v) },
        "contains"    => ->(v, e) { v.to_s.include?(e.to_s) },
        "starts_with" => ->(v, e) { v.to_s.start_with?(e.to_s) },
        "ends_with"   => ->(v, e) { v.to_s.end_with?(e.to_s) },
        "matches"     => ->(v, e) { v.to_s.match?(Regexp.new(e.to_s)) },
        "exists"      => ->(v, _) { !v.nil? },
        "empty"       => ->(v, _) { v.nil? || (v.respond_to?(:empty?) && v.empty?) },
        "truthy"      => ->(v, _) { !!v },
        "falsy"       => ->(v, _) { !v }
      }.freeze

      class << self
        # Evaluate Route or Condition
        def match?(state, cond)
          val = Resolver.resolve(state, "$#{cond.field}")
          exp = Resolver.resolve(state, cond.value)
          op = OPS.fetch(cond.op) { ->(_, _) { false } }
          op.call(val, exp)
        rescue => e
          DurableWorkflow.log(:warn, "Condition failed: #{e.message}", field: cond.field, op: cond.op)
          false
        end

        # Find first matching route
        def find_route(state, routes)
          routes.find { match?(state, _1) }
        end
      end
    end
  end
end
```

### 5. `lib/durable_workflow/core/validator.rb`

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
        @wf = workflow
        @errors = []
      end

      def validate!
        check_unique_ids!
        check_step_types!
        check_references!
        check_reachability!
        raise ValidationError, @errors.join("; ") if @errors.any?
        true
      end

      def valid?
        validate!
      rescue ValidationError
        false
      end

      private

        def check_unique_ids!
          ids = @wf.steps.map(&:id)
          dups = ids.group_by(&:itself).select { |_, v| v.size > 1 }.keys
          @errors << "Duplicate step IDs: #{dups.join(', ')}" if dups.any?
        end

        def check_step_types!
          @wf.steps.each do |step|
            unless Executors::Registry.registered?(step.type)
              @errors << "Unknown step type '#{step.type}' in step '#{step.id}'"
            end
          end
        end

        def check_references!
          valid_ids = @wf.step_ids.to_set << FINISHED

          @wf.steps.each do |step|
            check_ref(step.id, "next", step.next_step, valid_ids)
            check_ref(step.id, "on_error", step.on_error, valid_ids)

            cfg = step.config
            case step.type
            when "router"
              cfg.routes&.each { |r| check_ref(step.id, "route", r.target, valid_ids) }
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
          @errors << "Step '#{step_id}' #{field} references unknown '#{target}'"
        end

        def check_reachability!
          return if @wf.steps.empty?

          reachable = Set.new
          queue = [@wf.first_step.id]

          while (id = queue.shift)
            next if reachable.include?(id) || id == FINISHED
            reachable << id
            step = @wf.find_step(id)
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

          unreachable = @wf.step_ids - reachable.to_a
          @errors << "Unreachable steps: #{unreachable.join(', ')}" if unreachable.any?
        end
    end
  end
end
```

### 6. `lib/durable_workflow/core/engine.rb`

```ruby
# frozen_string_literal: true

require "timeout"

module DurableWorkflow
  module Core
    class Engine
      FINISHED = "__FINISHED__"

      attr_reader :workflow, :store

      def initialize(workflow, store: nil)
        @workflow = workflow
        @store = store || DurableWorkflow.config&.store
        raise ConfigError, "No store configured. Use Redis, ActiveRecord, or Sequel." unless @store
      end

      def run(input, execution_id: nil)
        exec_id = execution_id || SecureRandom.uuid

        state = State.new(
          execution_id: exec_id,
          workflow_id: workflow.id,
          input: DurableWorkflow::Utils.deep_symbolize(input || {})
        )

        # Save initial Execution with :running status
        save_execution(state, ExecutionResult.new(status: :running, execution_id: exec_id))

        if workflow.timeout
          Timeout.timeout(workflow.timeout) do
            execute_from(state, workflow.first_step.id)
          end
        else
          execute_from(state, workflow.first_step.id)
        end
      rescue Timeout::Error
        result = ExecutionResult.new(status: :failed, execution_id: state.execution_id, error: "Workflow timeout after #{workflow.timeout}s")
        save_execution(state, result)
        result
      end

      def resume(execution_id, response: nil, approved: nil)
        execution = @store.load(execution_id)
        raise ExecutionError, "Execution not found: #{execution_id}" unless execution

        state = execution.to_state
        state = state.with_ctx(response:) if response
        state = state.with_ctx(approved:) unless approved.nil?

        # Use recover_to from Execution, or fall back to current_step
        resume_step = execution.recover_to || execution.current_step

        execute_from(state, resume_step)
      end

      private

        def execute_from(state, step_id)
          while step_id && step_id != FINISHED
            state = state.with_current_step(step_id)

            # Save intermediate state as :running
            save_execution(state, ExecutionResult.new(status: :running, execution_id: state.execution_id))

            step = workflow.find_step(step_id)
            raise ExecutionError, "Step not found: #{step_id}" unless step

            outcome = execute_step(state, step)
            state = outcome.state

            case outcome.result
            when HaltResult
              return handle_halt(state, outcome.result)
            when ContinueResult
              step_id = outcome.result.next_step
            else
              raise ExecutionError, "Unknown result: #{outcome.result.class}"
            end
          end

          # Completed
          result = ExecutionResult.new(status: :completed, execution_id: state.execution_id, output: state.ctx[:result])
          save_execution(state, result)
          result
        end

        def execute_step(state, step)
          executor_class = Executors::Registry[step.type]
          raise ExecutionError, "No executor for: #{step.type}" unless executor_class

          start = Time.now
          outcome = executor_class.new(step).call(state)
          duration = ((Time.now - start) * 1000).to_i

          @store.record(Entry.new(
            id: SecureRandom.uuid,
            execution_id: state.execution_id,
            step_id: step.id,
            step_type: step.type,
            action: outcome.result.is_a?(HaltResult) ? :halted : :completed,
            duration_ms: duration,
            output: outcome.result.output,
            timestamp: Time.now
          ))

          outcome
        rescue => e
          @store.record(Entry.new(
            id: SecureRandom.uuid,
            execution_id: state.execution_id,
            step_id: step.id,
            step_type: step.type,
            action: :failed,
            error: "#{e.class}: #{e.message}",
            timestamp: Time.now
          ))

          if step.on_error
            # Store error info in ctx for access by error handler step
            error_state = state.with_ctx(_last_error: { step: step.id, message: e.message, class: e.class.name })
            return StepOutcome.new(state: error_state, result: ContinueResult.new(next_step: step.on_error))
          end

          raise
        end

        def handle_halt(state, halt_result)
          result = ExecutionResult.new(
            status: :halted,
            execution_id: state.execution_id,
            output: state.ctx[:result],
            halt: halt_result
          )
          save_execution(state, result)
          result
        end

        def save_execution(state, result)
          execution = Execution.from_state(state, result)
          @store.save(execution)
        end
    end
  end
end
```

## Key Changes from Original

1. **Validator now checks step types against Registry** - `check_step_types!` method ensures all types are registered
2. **No AI-specific handling in Validator** - removed `guardrail` check in `check_reachability!`
3. **Module namespace is `DurableWorkflow`** - not `Workflow`
4. **Engine saves Execution, not State** - `save_execution(state, result)` converts State + ExecutionResult → Execution
5. **Engine loads Execution, converts to State** - `execution.to_state` for executor use
6. **No `ctx[:_status]`, `ctx[:_halt]`, `ctx[:_resume_step]`** - all in typed Execution fields
7. **`_last_error` in ctx for error handler access** - only temporary, for on_error step to read

## Acceptance Criteria

1. `Executors::Registry.register("custom", MyExecutor)` works
2. `Executors::Registry.registered?("custom")` returns true
3. `Validator.validate!` fails for unknown step types
4. `Engine.new(wf).run(input)` executes steps in sequence
5. `Engine.resume(id, approved: true)` continues halted workflow
6. Store receives `Execution` objects (not State) with typed `status`, `halt_data`, `error`, `recover_to`
7. `ctx` only contains user workflow variables (except transient `_last_error` for error handling)
