# frozen_string_literal: true

begin
  require 'async'
  require 'async/barrier'
rescue LoadError
  # async gem not available - parallel executor will fail at runtime if used
end

module DurableWorkflow
  module Core
    module Executors
      class Parallel < Base
        Registry.register('parallel', self)

        def call(state)
          branches = config.branches
          return continue(state) if branches.empty?

          raise ExecutionError, "Parallel executor requires 'async' gem. Add it to your Gemfile." unless defined?(Async)

          wait_mode = config.wait
          required = case wait_mode
                     when 'all' then branches.size
                     when 'any' then 1
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
                rescue StandardError => e
                  errors << { branch: branch.id, error: e.message }
                  outcomes[i] = nil
                end
              end

              if wait_mode == 'any'
                barrier.wait { break if outcomes.compact.size >= required }
              else
                barrier.wait
              end
            ensure
              barrier.stop
            end
          end

          raise ExecutionError, "Parallel failed: #{errors.size} errors" if wait_mode == 'all' && errors.any?
          raise ExecutionError, 'Insufficient completions' if outcomes.compact.size < required

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
