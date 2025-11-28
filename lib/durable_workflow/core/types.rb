# frozen_string_literal: true

module DurableWorkflow
  module Core
    class << self
      def config_registry
        @config_registry ||= {}
      end

      def register_config(type, klass)
        config_registry[type.to_s] = klass
      end

      def config_registered?(type)
        config_registry.key?(type.to_s)
      end
    end
  end
end

# Load base types first
require_relative 'types/base'
require_relative 'types/condition'
require_relative 'types/configs'
require_relative 'types/step_def'
require_relative 'types/workflow_def'
require_relative 'types/state'
require_relative 'types/entry'
require_relative 'types/results'
