# 04-STEPS: Built-in Step Executors

## Goal

Implement all core step executors: start, end, assign, call, router, loop, parallel, transform, halt, approval, workflow (sub-workflow).

## Dependencies

- 01-GEMSPEC completed
- 02-TYPES completed
- 03-EXECUTION completed

## Files to Create

### 1. `lib/durable_workflow/core/executors/start.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Start < Base
        Registry.register("start", self)

        def call(state)
          validate_inputs!(state)
          state = apply_defaults(state)
          state = store(state, :input, state.input)
          continue(state)
        end

        private

          def workflow_inputs(state)
            DurableWorkflow.registry[state.workflow_id]&.inputs || []
          end

          def validate_inputs!(state)
            workflow_inputs(state).each do |input_def|
              value = state.input[input_def.name.to_sym]

              if input_def.required && value.nil?
                raise ValidationError, "Missing required input: #{input_def.name}"
              end

              next if value.nil?
              validate_type!(input_def.name, value, input_def.type)
            end
          end

          def validate_type!(name, value, type)
            valid = case type
            when "string"  then value.is_a?(String)
            when "integer" then value.is_a?(Integer)
            when "number"  then value.is_a?(Numeric)
            when "boolean" then value == true || value == false
            when "array"   then value.is_a?(Array)
            when "object"  then value.is_a?(Hash)
            else true
            end

            raise ValidationError, "Input '#{name}' must be #{type}, got #{value.class}" unless valid
          end

          def apply_defaults(state)
            updates = {}
            workflow_inputs(state).each do |input_def|
              key = input_def.name.to_sym
              if state.input[key].nil? && !input_def.default.nil?
                updates[key] = input_def.default
              end
            end
            return state if updates.empty?
            state.with(input: state.input.merge(updates))
          end
      end
    end
  end
end
```

### 2. `lib/durable_workflow/core/executors/end.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class End < Base
        FINISHED = "__FINISHED__"
        Registry.register("end", self)

        def call(state)
          raw = config.result || state.ctx.dup
          result = resolve(state, raw)
          state = store(state, :result, result)
          continue(state, next_step: FINISHED, output: result)
        end
      end
    end
  end
end
```

### 3. `lib/durable_workflow/core/executors/assign.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Assign < Base
        Registry.register("assign", self)

        def call(state)
          state = config.set.reduce(state) do |s, (k, v)|
            store(s, k, resolve(s, v))
          end
          continue(state)
        end
      end
    end
  end
end
```

### 4. `lib/durable_workflow/core/executors/call.rb`

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

          state = store(state, config.output, result)
          continue(state, output: result)
        end

        private

          def resolve_service(name)
            DurableWorkflow.config&.service_resolver&.call(name) || Object.const_get(name)
          end

          def invoke(svc, method, input)
            target = svc.respond_to?(method) ? svc : svc.new
            m = target.method(method)

            # Check if method takes keyword args
            has_kwargs = m.parameters.any? { |type, _| type == :key || type == :keyreq || type == :keyrest }

            if has_kwargs && input.is_a?(Hash)
              m.call(**input.transform_keys(&:to_sym))
            elsif m.arity == 0
              m.call
            else
              m.call(input)
            end
          end
      end
    end
  end
end
```

### 5. `lib/durable_workflow/core/executors/router.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Router < Base
        Registry.register("router", self)

        def call(state)
          routes = config.routes
          default = config.default

          route = ConditionEvaluator.find_route(state, routes)

          if route
            continue(state, next_step: route.target)
          elsif default
            continue(state, next_step: default)
          else
            raise ExecutionError, "No matching route and no default for '#{step.id}'"
          end
        end
      end
    end
  end
end
```

### 6. `lib/durable_workflow/core/executors/loop.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Loop < Base
        Registry.register("loop", self)
        MAX_ITER = 100

        def call(state)
          config.over ? foreach_loop(state) : while_loop(state)
        end

        private

          def foreach_loop(state)
            collection = resolve(state, config.over)
            raise ExecutionError, "Loop 'over' must be array" unless collection.is_a?(Array)

            item_key = config.as
            index_key = config.index_as
            max = config.max
            raise ExecutionError, "Collection exceeds max (#{max})" if collection.size > max

            results = []
            collection.each_with_index do |item, i|
              state = store(state, item_key, item)
              state = store(state, index_key, i)
              outcome = execute_body(state)

              # Bubble up halts
              return outcome if outcome.result.is_a?(HaltResult)

              state = outcome.state
              results << outcome.result.output
            end

            state = cleanup(state, item_key, index_key)
            state = store(state, config.output, results)
            continue(state)
          end

          def while_loop(state)
            cond = config.while
            max = config.max
            results = []
            i = 0

            while ConditionEvaluator.match?(state, cond)
              i += 1
              if i > max
                return config.on_exhausted ? continue(state, next_step: config.on_exhausted) : raise(ExecutionError, "Loop exceeded max")
              end
              state = store(state, :iteration, i)
              outcome = execute_body(state)

              # Bubble up halts
              return outcome if outcome.result.is_a?(HaltResult)

              state = outcome.state
              results << outcome.result.output
              break if state.ctx[:break_loop]
            end

            state = cleanup(state, :iteration, :break_loop)
            state = store(state, config.output, results)
            continue(state)
          end

          def execute_body(state)
            body = config.do
            result = nil

            body.each do |step_def|
              executor = Registry[step_def.type]
              raise ExecutionError, "Unknown step type: #{step_def.type}" unless executor

              start_time = Time.now
              outcome = executor.new(step_def).call(state)
              duration = ((Time.now - start_time) * 1000).to_i

              record_nested_entry(state, step_def, outcome, duration)

              # Bubble up halts
              return outcome if outcome.result.is_a?(HaltResult)

              state = outcome.state
              result = outcome.result
            end

            StepOutcome.new(state:, result: result || ContinueResult.new)
          end

          def record_nested_entry(state, step_def, outcome, duration)
            wf_store = DurableWorkflow.config&.store
            return unless wf_store

            wf_store.record(Entry.new(
              id: SecureRandom.uuid,
              execution_id: state.execution_id,
              step_id: "#{step.id}:#{step_def.id}",
              step_type: step_def.type,
              action: outcome.result.is_a?(HaltResult) ? :halted : :completed,
              duration_ms: duration,
              output: outcome.result.output,
              timestamp: Time.now
            ))
          end

          def cleanup(state, *keys)
            new_ctx = state.ctx.except(*keys)
            state.with(ctx: new_ctx)
          end
      end
    end
  end
end
```

### 7. `lib/durable_workflow/core/executors/parallel.rb`

```ruby
# frozen_string_literal: true

require "async"
require "async/barrier"

module DurableWorkflow
  module Core
    module Executors
      class Parallel < Base
        Registry.register("parallel", self)

        def call(state)
          branches = config.branches
          return continue(state) if branches.empty?

          wait_mode = config.wait || "all"
          required = case wait_mode
          when "all" then branches.size
          when "any" then 1
          when Integer then [wait_mode, branches.size].min
          else branches.size
          end

          outcomes = Array.new(branches.size)
          errors = []

          Sync do
            barrier = Async::Barrier.new

            begin
              branches.each_with_index do |branch, i|
                barrier.async do
                  executor = Registry[branch.type]
                  raise ExecutionError, "Unknown branch type: #{branch.type}" unless executor
                  outcomes[i] = executor.new(branch).call(state)
                rescue => e
                  errors << { branch: branch.id, error: e.message }
                  outcomes[i] = nil
                end
              end

              if wait_mode == "any"
                barrier.wait { break if outcomes.compact.size >= required }
              else
                barrier.wait
              end
            ensure
              barrier.stop
            end
          end

          raise ExecutionError, "Parallel failed: #{errors.size} errors" if wait_mode == "all" && errors.any?
          raise ExecutionError, "Insufficient completions" if outcomes.compact.size < required

          # Merge contexts from all branches
          # Strategy: last-write-wins (branch processed later overwrites earlier values)
          merged_ctx = outcomes.compact.reduce(state.ctx) do |ctx, outcome|
            ctx.merge(outcome.state.ctx)
          end

          results = outcomes.map { _1&.result&.output }
          final_state = state.with(ctx: merged_ctx)
          final_state = store(final_state, config.output, results)

          continue(final_state, output: results)
        end
      end
    end
  end
end
```

### 8. `lib/durable_workflow/core/executors/transform.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Transform < Base
        Registry.register("transform", self)

        OPS = {
          "map"     => ->(d, a) { d.is_a?(Array) ? d.map { |i| a.is_a?(String) ? Transform.dig(i, a) : i } : d },
          "select"  => ->(d, a) { d.is_a?(Array) ? d.select { |i| Transform.match?(i, a) } : d },
          "reject"  => ->(d, a) { d.is_a?(Array) ? d.reject { |i| Transform.match?(i, a) } : d },
          "pluck"   => ->(d, a) { d.is_a?(Array) ? d.map { |i| Transform.dig(i, a) } : d },
          "first"   => ->(d, a) { d.is_a?(Array) ? d.first(a || 1) : d },
          "last"    => ->(d, a) { d.is_a?(Array) ? d.last(a || 1) : d },
          "flatten" => ->(d, a) { d.is_a?(Array) ? d.flatten(a || 1) : d },
          "compact" => ->(d, _) { d.is_a?(Array) ? d.compact : d },
          "uniq"    => ->(d, _) { d.is_a?(Array) ? d.uniq : d },
          "reverse" => ->(d, _) { d.is_a?(Array) ? d.reverse : d },
          "sort"    => ->(d, a) { d.is_a?(Array) ? (a ? d.sort_by { |i| Transform.dig(i, a) } : d.sort) : d },
          "count"   => ->(d, _) { d.respond_to?(:size) ? d.size : 1 },
          "sum"     => ->(d, a) { d.is_a?(Array) ? (a ? d.sum { |i| Transform.dig(i, a).to_f } : d.sum(&:to_f)) : d },
          "keys"    => ->(d, _) { d.is_a?(Hash) ? d.keys : [] },
          "values"  => ->(d, _) { d.is_a?(Hash) ? d.values : [] },
          "pick"    => ->(d, a) { d.is_a?(Hash) ? d.slice(*Array(a)) : d },
          "omit"    => ->(d, a) { d.is_a?(Hash) ? d.except(*Array(a)) : d },
          "merge"   => ->(d, a) { d.is_a?(Hash) && a.is_a?(Hash) ? d.merge(a) : d }
        }.freeze

        def call(state)
          input = config.input ? resolve(state, "$#{config.input}") : state.ctx.dup
          expr = config.expression

          result = expr.reduce(input) do |data, (op, arg)|
            OPS.fetch(op.to_s) { ->(d, _) { d } }.call(data, arg)
          end

          state = store(state, config.output, result)
          continue(state, output: result)
        end

        def self.dig(obj, key)
          keys = key.to_s.split(".")
          keys.reduce(obj) { |o, k| o.is_a?(Hash) ? (o[k] || o[k.to_sym]) : nil }
        end

        def self.match?(obj, conditions)
          conditions.all? { |k, v| dig(obj, k) == v }
        end
      end
    end
  end
end
```

### 9. `lib/durable_workflow/core/executors/halt.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Halt < Base
        Registry.register("halt", self)

        def call(state)
          extra_data = resolve(state, config.data) || {}

          halt(state,
            data: {
              reason: resolve(state, config.reason) || "Halted",
              halted_at: Time.now.iso8601,
              **extra_data
            },
            resume_step: config.resume_step || next_step,
            prompt: resolve(state, config.reason)
          )
        end
      end
    end
  end
end
```

### 10. `lib/durable_workflow/core/executors/approval.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Approval < Base
        Registry.register("approval", self)

        def call(state)
          # Check if timed out (when resuming)
          requested_at_str = state.ctx.dig(:_halt, :requested_at)
          if requested_at_str && config.timeout
            requested_at = Time.parse(requested_at_str)
            if Time.now - requested_at > config.timeout
              if config.on_timeout
                return continue(state, next_step: config.on_timeout)
              else
                raise ExecutionError, "Approval timeout"
              end
            end
          end

          # Resuming from approval
          if state.ctx.key?(:approved)
            approved = state.ctx[:approved]
            state = state.with(ctx: state.ctx.except(:approved))
            if approved
              return continue(state)
            elsif config.on_reject
              return continue(state, next_step: config.on_reject)
            else
              raise ExecutionError, "Rejected"
            end
          end

          # Request approval
          halt(state,
            data: {
              type: :approval,
              prompt: resolve(state, config.prompt),
              context: resolve(state, config.context),
              approvers: config.approvers,
              timeout: config.timeout,
              requested_at: Time.now.iso8601
            },
            resume_step: step.id,
            prompt: resolve(state, config.prompt)
          )
        end
      end
    end
  end
end
```

### 11. `lib/durable_workflow/core/executors/workflow.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class SubWorkflow < Base
        Registry.register("workflow", self)

        def call(state)
          child_wf = DurableWorkflow.registry[config.workflow_id]
          raise ExecutionError, "Workflow not found: #{config.workflow_id}" unless child_wf

          input = resolve(state, config.input) || {}

          result = with_timeout(config.timeout) do
            Engine.new(child_wf).run(input)
          end

          case result.status
          when :completed
            state = store(state, config.output, result.output)
            continue(state, output: result.output)
          when :halted
            halt(state, data: result.halt.data, resume_step: step.id, prompt: result.halt.prompt)
          when :failed
            raise ExecutionError, "Sub-workflow failed: #{result.error}"
          end
        end
      end
    end
  end
end
```

## Acceptance Criteria

1. All 11 executors are registered in `Executors::Registry`
2. `Registry.types` returns all core types: start, end, assign, call, router, loop, parallel, transform, halt, approval, workflow
3. Each executor returns `StepOutcome` with either `ContinueResult` or `HaltResult`
4. Loop executor bubbles up halts from body
5. Parallel executor uses async gem for concurrent execution
6. Approval executor handles timeout on resume
