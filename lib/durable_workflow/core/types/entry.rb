# frozen_string_literal: true

module DurableWorkflow
  module Core
    class Entry < BaseStruct
      attribute :id, Types::Strict::String
      attribute :execution_id, Types::Strict::String
      attribute :step_id, Types::Strict::String
      attribute :step_type, Types::StepType  # Just a string
      attribute :action, Types::EntryAction
      attribute? :duration_ms, Types::Strict::Integer.optional
      attribute? :input, Types::Any
      attribute? :output, Types::Any
      attribute? :error, Types::Strict::String.optional
      attribute :timestamp, Types::Any

      def self.from_h(h)
        new(
          **h,
          action: h[:action]&.to_sym,
          timestamp: h[:timestamp].is_a?(String) ? Time.parse(h[:timestamp]) : h[:timestamp]
        )
      end
    end
  end
end
