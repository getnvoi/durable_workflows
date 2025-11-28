# frozen_string_literal: true

module DurableWorkflow
  module Runners
    class Sync
      attr_reader :workflow, :store

      def initialize(workflow, store: nil)
        @workflow = workflow
        @store = store || DurableWorkflow.config&.store
        raise ConfigError, 'No store configured' unless @store
      end

      # Run workflow, block until complete/halted
      def run(input: {}, execution_id: nil)
        engine = Core::Engine.new(workflow, store:)
        engine.run(input:, execution_id:)
      end

      # Resume halted workflow
      def resume(execution_id, response: nil, approved: nil)
        engine = Core::Engine.new(workflow, store:)
        engine.resume(execution_id, response:, approved:)
      end

      # Run until fully complete (auto-handle halts with block)
      # Without block, returns halted result when halt encountered
      def run_until_complete(input: {}, execution_id: nil)
        result = run(input:, execution_id:)

        while result.halted? && block_given?
          response = yield result.halt
          result = resume(result.execution_id, response:)
        end

        result
      end
    end
  end
end
