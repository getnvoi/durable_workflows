# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "durable_workflow"
require_relative "support/test_store"

require "minitest/autorun"

# Convenience alias for tests
TestStore = DurableWorkflow::Storage::TestStore

# Configure a test store for all tests
module DurableWorkflow
  module TestHelpers
    def setup_test_store
      @test_store = Storage::TestStore.new
      DurableWorkflow.configure do |c|
        c.store = @test_store
      end
    end

    def teardown_test_store
      @test_store&.clear!
      DurableWorkflow.config = nil
      DurableWorkflow.instance_variable_set(:@registry, nil)
    end

    # Helper to build minimal workflow for testing
    def build_workflow(id:, name: "Test", steps:, inputs: [])
      Core::WorkflowDef.new(
        id: id,
        name: name,
        steps: steps,
        inputs: inputs
      )
    end

    # Helper to build a step
    def build_step(id:, type:, config: {}, next_step: nil, on_error: nil)
      config_class = Core.config_registry[type]
      typed_config = config_class ? config_class.new(config) : config

      Core::StepDef.new(
        id: id,
        type: type,
        config: typed_config,
        next_step: next_step,
        on_error: on_error
      )
    end

    # Helper to build state
    def build_state(execution_id: "test-exec", workflow_id: "test-wf", input: {}, ctx: {})
      Core::State.new(
        execution_id: execution_id,
        workflow_id: workflow_id,
        input: input,
        ctx: ctx
      )
    end

    # Helper to build execution (for storage tests)
    def build_execution(id: "test-exec", workflow_id: "test-wf", status: :running, input: {}, ctx: {}, current_step: nil, result: nil, recover_to: nil, halt_data: nil, error: nil)
      Core::Execution.new(
        id: id,
        workflow_id: workflow_id,
        status: status,
        input: input,
        ctx: ctx,
        current_step: current_step,
        result: result,
        recover_to: recover_to,
        halt_data: halt_data,
        error: error
      )
    end
  end
end
