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
      def run(input: {}, execution_id: nil, queue: nil, priority: nil)
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
