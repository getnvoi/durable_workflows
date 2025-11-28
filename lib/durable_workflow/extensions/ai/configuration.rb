# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      class Configuration
        attr_accessor :default_model, :api_keys

        def initialize
          @default_model = 'gpt-4o-mini'
          @api_keys = {}
        end
      end

      class << self
        def configuration
          @configuration ||= Configuration.new
        end

        def configure
          yield configuration if block_given?
          apply_ruby_llm_config
          configuration
        end

        def chat(model: nil)
          RubyLLM.chat(model: model || configuration.default_model)
        end

        private

        def apply_ruby_llm_config
          RubyLLM.configure do |c|
            c.openai_api_key = configuration.api_keys[:openai] if configuration.api_keys[:openai]
            c.anthropic_api_key = configuration.api_keys[:anthropic] if configuration.api_keys[:anthropic]
          end
        end
      end
    end
  end
end
