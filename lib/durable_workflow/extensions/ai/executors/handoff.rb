# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module Executors
        class Handoff < Core::Executors::Base
          def call(state)
            target_agent = config.to || state.ctx[:_handoff_to]
            raise ExecutionError, 'No handoff target specified' unless target_agent

            workflow = DurableWorkflow.registry[state.workflow_id]
            agents = Extension.agents(workflow)
            raise ExecutionError, "Agent not found: #{target_agent}" unless agents.key?(target_agent)

            new_ctx = state.ctx.except(:_handoff_to).merge(
              _current_agent: target_agent,
              _handoff_context: {
                from: config.from,
                to: target_agent,
                reason: config.reason,
                timestamp: Time.now.iso8601
              }
            )
            state = state.with(ctx: new_ctx)

            continue(state)
          end
        end
      end
    end
  end
end
