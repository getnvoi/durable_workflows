# 02-RUNNERS: Sync, Async, and Stream Runners

## Goal

Implement execution runners: Sync (blocking), Async (background jobs), and Stream (SSE events).

## Dependencies

- Phase 1 complete
- 01-STORAGE complete

## Files to Create

### 1. `lib/durable_workflow/runners/sync.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Runners
    class Sync
      attr_reader :workflow, :store

      def initialize(workflow, store: nil)
        @workflow = workflow
        @store = store || DurableWorkflow.config&.store
        raise ConfigError, "No store configured" unless @store
      end

      # Run workflow, block until complete/halted
      def run(input, execution_id: nil)
        engine = Core::Engine.new(workflow, store:)
        engine.run(input, execution_id:)
      end

      # Resume halted workflow
      def resume(execution_id, response: nil, approved: nil)
        engine = Core::Engine.new(workflow, store:)
        engine.resume(execution_id, response:, approved:)
      end

      # Run until fully complete (auto-handle halts with block)
      # Without block, returns halted result when halt encountered
      def run_until_complete(input, execution_id: nil)
        result = run(input, execution_id:)

        while result.halted? && block_given?
          response = yield result.halt
          result = resume(result.execution_id, response:)
        end

        result
      end
    end
  end
end
```

### 2. `lib/durable_workflow/runners/async.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Runners
    class Async
      attr_reader :workflow, :store, :adapter

      def initialize(workflow, store: nil, adapter: nil)
        @workflow = workflow
        @store = store || DurableWorkflow.config&.store
        raise ConfigError, "No store configured" unless @store
        @adapter = adapter || Adapters::Inline.new(store: @store)
      end

      # Queue workflow for execution, return immediately
      def run(input, execution_id: nil, queue: nil, priority: nil)
        exec_id = execution_id || SecureRandom.uuid

        # Pre-create Execution with :pending status
        execution = Core::Execution.new(
          id: exec_id,
          workflow_id: workflow.id,
          status: :pending,
          input: input.freeze,
          ctx: {}
        )
        store.save(execution)

        # Enqueue
        adapter.enqueue(
          workflow_id: workflow.id,
          workflow_data: serialize_workflow,
          execution_id: exec_id,
          input:,
          action: :start,
          queue:,
          priority:
        )

        exec_id
      end

      # Queue resume
      def resume(execution_id, response: nil, approved: nil, queue: nil)
        adapter.enqueue(
          workflow_id: workflow.id,
          workflow_data: serialize_workflow,
          execution_id:,
          response:,
          approved:,
          action: :resume,
          queue:
        )

        execution_id
      end

      # Poll for completion
      def wait(execution_id, timeout: 30, interval: 0.1)
        deadline = Time.now + timeout

        while Time.now < deadline
          execution = store.load(execution_id)

          case execution&.status
          when :completed, :failed, :halted
            return build_result(execution)
          end

          sleep(interval)
        end

        nil # Timeout
      end

      # Get current status
      def status(execution_id)
        execution = store.load(execution_id)
        execution&.status || :unknown
      end

      private

        def serialize_workflow
          { id: workflow.id, name: workflow.name, version: workflow.version }
        end

        def build_result(execution)
          Core::ExecutionResult.new(
            status: execution.status,
            execution_id: execution.id,
            output: execution.result,
            halt: execution.status == :halted ? Core::HaltResult.new(data: execution.halt_data || {}) : nil,
            error: execution.error
          )
        end
    end
  end
end
```

### 3. `lib/durable_workflow/runners/stream.rb`

```ruby
# frozen_string_literal: true

require "json"

module DurableWorkflow
  module Runners
    # Stream event - typed struct for SSE events
    class Event < BaseStruct
      attribute :type, Types::Strict::String
      attribute :data, Types::Hash.default({}.freeze)
      attribute :timestamp, Types::Any

      def to_h
        { type:, data:, timestamp: timestamp.is_a?(Time) ? timestamp.iso8601 : timestamp }
      end

      def to_json(*)
        JSON.generate(to_h)
      end

      def to_sse
        "event: #{type}\ndata: #{to_json}\n\n"
      end
    end

    class Stream
      EVENTS = %w[
        workflow.started workflow.completed workflow.halted workflow.failed
        step.started step.completed step.failed step.halted
      ].freeze

      attr_reader :workflow, :store, :subscribers

      def initialize(workflow, store: nil)
        @workflow = workflow
        @store = store || DurableWorkflow.config&.store
        raise ConfigError, "No store configured" unless @store
        @subscribers = []
      end

      # Subscribe to events
      def subscribe(events: nil, &block)
        @subscribers << { events:, handler: block }
        self
      end

      # Run with event streaming
      def run(input, execution_id: nil)
        emit("workflow.started", workflow_id: workflow.id, input:)

        engine = StreamingEngine.new(workflow, store:, emitter: method(:emit))
        result = engine.run(input, execution_id:)

        case result.status
        when :completed
          emit("workflow.completed", execution_id: result.execution_id, output: result.output)
        when :halted
          emit("workflow.halted", execution_id: result.execution_id, halt: result.halt&.data, prompt: result.halt&.prompt)
        when :failed
          emit("workflow.failed", execution_id: result.execution_id, error: result.error)
        end

        result
      end

      # Resume with event streaming
      def resume(execution_id, response: nil, approved: nil)
        emit("workflow.resumed", execution_id:)

        engine = StreamingEngine.new(workflow, store:, emitter: method(:emit))
        result = engine.resume(execution_id, response:, approved:)

        case result.status
        when :completed
          emit("workflow.completed", execution_id: result.execution_id, output: result.output)
        when :halted
          emit("workflow.halted", execution_id: result.execution_id, halt: result.halt&.data, prompt: result.halt&.prompt)
        when :failed
          emit("workflow.failed", execution_id: result.execution_id, error: result.error)
        end

        result
      end

      # Emit event
      def emit(type, **data)
        event = Event.new(type:, data:, timestamp: Time.now)

        subscribers.each do |sub|
          next if sub[:events] && !sub[:events].include?(type)
          sub[:handler].call(event)
        end
      end
    end

    # Engine subclass with event hooks
    class StreamingEngine < Core::Engine
      def initialize(workflow, store:, emitter:)
        super(workflow, store:)
        @emitter = emitter
      end

      private

        def execute_step(state, step)
          @emitter.call("step.started", step_id: step.id, step_type: step.type)

          outcome = super

          event = case outcome.result
          when Core::HaltResult then "step.halted"
          else "step.completed"
          end

          @emitter.call(event, step_id: step.id, output: outcome.result.output)

          outcome
        rescue => e
          @emitter.call("step.failed", step_id: step.id, error: e.message)
          raise
        end
    end
  end
end
```

### 4. `lib/durable_workflow/runners/adapters/inline.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Runners
    module Adapters
      class Inline
        def initialize(store: nil)
          @store = store
        end

        def enqueue(workflow_id:, workflow_data:, execution_id:, action:, **kwargs)
          # Execute immediately in current thread (for testing/dev)
          perform(
            workflow_id:,
            workflow_data:,
            execution_id:,
            action:,
            **kwargs
          )
        end

        def perform(workflow_id:, workflow_data:, execution_id:, action:, input: nil, response: nil, approved: nil, **_)
          workflow = DurableWorkflow.registry[workflow_id]
          raise ExecutionError, "Workflow not found: #{workflow_id}" unless workflow

          store = @store || DurableWorkflow.config&.store
          raise ConfigError, "No store configured" unless store

          engine = Core::Engine.new(workflow, store:)

          # Engine saves Execution with proper typed status - no manual status update needed
          case action.to_sym
          when :start
            engine.run(input || {}, execution_id:)
          when :resume
            engine.resume(execution_id, response:, approved:)
          end
        end
      end
    end
  end
end
```

### 5. `lib/durable_workflow/runners/adapters/sidekiq.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Runners
    module Adapters
      class Sidekiq
        def initialize(job_class: nil)
          @job_class = job_class || default_job_class
        end

        def enqueue(workflow_id:, workflow_data:, execution_id:, action:, queue: nil, priority: nil, **kwargs)
          job_args = {
            workflow_id:,
            workflow_data:,
            execution_id:,
            action: action.to_s,
            **kwargs.compact
          }

          if queue
            @job_class.set(queue:).perform_async(job_args)
          else
            @job_class.perform_async(job_args)
          end

          execution_id
        end

        private

          def default_job_class
            # Define a default job class if sidekiq is available
            return @default_job_class if defined?(@default_job_class)

            @default_job_class = Class.new do
              if defined?(::Sidekiq::Job)
                include ::Sidekiq::Job

                def perform(args)
                  args = DurableWorkflow::Utils.deep_symbolize(args)

                  workflow = DurableWorkflow.registry[args[:workflow_id]]
                  raise DurableWorkflow::ExecutionError, "Workflow not found: #{args[:workflow_id]}" unless workflow

                  store = DurableWorkflow.config&.store
                  raise DurableWorkflow::ConfigError, "No store configured" unless store

                  engine = DurableWorkflow::Core::Engine.new(workflow, store:)

                  # Engine saves Execution with proper typed status - no manual status update needed
                  case args[:action].to_sym
                  when :start
                    engine.run(args[:input] || {}, execution_id: args[:execution_id])
                  when :resume
                    engine.resume(args[:execution_id], response: args[:response], approved: args[:approved])
                  end
                end
              end
            end

            # Register in Object so it can be found by Sidekiq
            Object.const_set(:DurableWorkflowJob, @default_job_class) unless defined?(::DurableWorkflowJob)

            @default_job_class
          end
      end
    end
  end
end
```

### 6. Update `lib/durable_workflow.rb` (require runners)

Add to the main entry point:

```ruby
# Runners
require_relative "durable_workflow/runners/sync"
require_relative "durable_workflow/runners/async"
require_relative "durable_workflow/runners/stream"
require_relative "durable_workflow/runners/adapters/inline"
```

## Usage Examples

### Sync Runner

```ruby
wf = DurableWorkflow.load("order.yml")
runner = DurableWorkflow::Runners::Sync.new(wf)

# Simple run
result = runner.run(user_id: 123, items: [...])
puts result.status  # :completed, :halted, or :failed

# Run with approval handling
result = runner.run_until_complete(user_id: 123) do |halt|
  puts "Approval needed: #{halt.prompt}"
  # Return user response
  { approved: true }
end
```

### Async Runner

```ruby
wf = DurableWorkflow.load("order.yml")
DurableWorkflow.register(wf)  # Required for async

runner = DurableWorkflow::Runners::Async.new(wf)

# Fire and forget
exec_id = runner.run(user_id: 123)

# Poll for result
result = runner.wait(exec_id, timeout: 60)

# Check status
status = runner.status(exec_id)  # :pending, :running, :completed, :halted, :failed
```

### Stream Runner (SSE)

```ruby
wf = DurableWorkflow.load("order.yml")
runner = DurableWorkflow::Runners::Stream.new(wf)

# Subscribe to events
runner.subscribe do |event|
  puts event.to_sse
end

# Or subscribe to specific events
runner.subscribe(events: ["step.completed", "workflow.completed"]) do |event|
  broadcast_to_client(event.to_json)
end

# Run with streaming
result = runner.run(user_id: 123)
```

### Sidekiq Adapter

```ruby
require "durable_workflow/runners/adapters/sidekiq"

wf = DurableWorkflow.load("order.yml")
DurableWorkflow.register(wf)

runner = DurableWorkflow::Runners::Async.new(
  wf,
  adapter: DurableWorkflow::Runners::Adapters::Sidekiq.new
)

exec_id = runner.run(user_id: 123, queue: "workflows")
```

## Acceptance Criteria

1. Sync runner blocks until completion
2. Async runner returns immediately with execution_id
3. Stream runner emits events for each step
4. Sidekiq adapter enqueues jobs correctly
5. All runners require store configuration (no fallback to memory)
6. `run_until_complete` handles approval loops
7. `Event` uses `BaseStruct` (not Ruby Struct)
8. Async runner creates `Execution` with typed `status: :pending` (not `ctx[:_status]`)
9. Async `wait`/`status` uses `execution.status` (not `ctx[:_status]`)
10. Async `build_result` uses `execution.result`, `execution.halt_data`, `execution.error`
11. Adapters don't manually update status - Engine handles it via `Execution`
