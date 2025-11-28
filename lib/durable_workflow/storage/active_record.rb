# frozen_string_literal: true

require 'json'

module DurableWorkflow
  module Storage
    class ActiveRecord < Store
      # Assumes two tables exist:
      #   workflow_executions: id (uuid), workflow_id, status, input (json), ctx (json),
      #                        current_step, result (json), recover_to, halt_data (json),
      #                        error (text), created_at, updated_at
      #   workflow_entries:    id (uuid), execution_id, step_id, step_type, action,
      #                        duration_ms, input (json), output (json), error, timestamp

      def initialize(execution_class:, entry_class:)
        @execution_class = execution_class
        @entry_class = entry_class
      end

      def save(execution)
        record = @execution_class.find_or_initialize_by(id: execution.id)
        record.assign_attributes(
          workflow_id: execution.workflow_id,
          status: execution.status.to_s,
          input: execution.input.to_json,
          ctx: execution.ctx.to_json,
          current_step: execution.current_step,
          result: execution.result&.to_json,
          recover_to: execution.recover_to,
          halt_data: execution.halt_data&.to_json,
          error: execution.error
        )
        record.save!
        execution
      end

      def load(execution_id)
        record = @execution_class.find_by(id: execution_id)
        return nil unless record

        Core::Execution.new(
          id: record.id,
          workflow_id: record.workflow_id,
          status: record.status.to_sym,
          input: parse_json(record.input) || {},
          ctx: parse_json(record.ctx) || {},
          current_step: record.current_step,
          result: parse_json_any(record.respond_to?(:result) ? record.result : nil),
          recover_to: record.respond_to?(:recover_to) ? record.recover_to : nil,
          halt_data: parse_json(record.respond_to?(:halt_data) ? record.halt_data : nil),
          error: record.respond_to?(:error) ? record.error : nil,
          created_at: record.created_at,
          updated_at: record.updated_at
        )
      end

      def record(entry)
        @entry_class.create!(
          id: entry.id,
          execution_id: entry.execution_id,
          step_id: entry.step_id,
          step_type: entry.step_type,
          action: entry.action.to_s,
          duration_ms: entry.duration_ms,
          input: entry.input&.to_json,
          output: entry.output&.to_json,
          error: entry.error,
          timestamp: entry.timestamp
        )
        entry
      end

      def entries(execution_id)
        @entry_class.where(execution_id:).order(:timestamp).map do |r|
          Core::Entry.new(
            id: r.id,
            execution_id: r.execution_id,
            step_id: r.step_id,
            step_type: r.step_type,
            action: r.action.to_sym,
            duration_ms: r.duration_ms,
            input: parse_json(r.input),
            output: parse_json(r.output),
            error: r.error,
            timestamp: r.timestamp
          )
        end
      end

      def find(workflow_id: nil, status: nil, limit: 100)
        scope = @execution_class.all
        scope = scope.where(workflow_id:) if workflow_id
        scope = scope.where(status: status.to_s) if status
        scope.limit(limit).order(created_at: :desc).map do |record|
          Core::Execution.new(
            id: record.id,
            workflow_id: record.workflow_id,
            status: record.status.to_sym,
            input: parse_json(record.input) || {},
            ctx: parse_json(record.ctx) || {},
            current_step: record.current_step,
            result: parse_json_any(record.respond_to?(:result) ? record.result : nil),
            recover_to: record.respond_to?(:recover_to) ? record.recover_to : nil,
            halt_data: parse_json(record.respond_to?(:halt_data) ? record.halt_data : nil),
            error: record.respond_to?(:error) ? record.error : nil,
            created_at: record.created_at,
            updated_at: record.updated_at
          )
        end
      end

      def delete(execution_id)
        record = @execution_class.find_by(id: execution_id)
        return false unless record

        @entry_class.where(execution_id:).delete_all
        record.destroy
        true
      end

      def execution_ids(workflow_id: nil, limit: 1000)
        scope = @execution_class.all
        scope = scope.where(workflow_id:) if workflow_id
        scope.limit(limit).pluck(:id)
      end

      private

      def parse_json(str)
        return nil if str.nil? || str.empty?

        result = JSON.parse(str)
        result.is_a?(Hash) ? DurableWorkflow::Utils.deep_symbolize(result) : result
      rescue JSON::ParserError
        nil
      end

      def parse_json_any(str)
        return nil if str.nil? || str.empty?

        result = JSON.parse(str)
        result.is_a?(Hash) ? DurableWorkflow::Utils.deep_symbolize(result) : result
      rescue JSON::ParserError
        nil
      end
    end
  end
end
