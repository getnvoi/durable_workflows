# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Registry
        @executors = {}

        class << self
          def register(type, klass)
            @executors[type.to_s] = klass
          end

          def [](type)
            @executors[type.to_s]
          end

          def types
            @executors.keys
          end

          def registered?(type)
            @executors.key?(type.to_s)
          end
        end
      end

      # Convenience method for registration
      def self.register(type)
        ->(klass) { Registry.register(type, klass) }
      end
    end
  end
end
