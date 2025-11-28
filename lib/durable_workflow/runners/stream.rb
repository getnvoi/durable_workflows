# frozen_string_literal: true

require "json"

module DurableWorkflow
  module Runners
    # Stream event type
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
      def run(input: {}, execution_id: nil)
        emit("workflow.started", workflow_id: workflow.id, input:)

        engine = StreamingEngine.new(workflow, store:, emitter: method(:emit))
        result = engine.run(input:, execution_id:)

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
