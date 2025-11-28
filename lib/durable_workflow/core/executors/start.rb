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
