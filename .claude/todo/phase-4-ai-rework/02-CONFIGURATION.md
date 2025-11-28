# 02-CONFIGURATION: Direct RubyLLM Configuration

## Goal

Replace `Provider.current=` dance with direct RubyLLM configuration.

## Files to Create

### `lib/durable_workflow/extensions/ai/configuration.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      class Configuration
        attr_accessor :default_model, :api_keys

        def initialize
          @default_model = "gpt-4o-mini"
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
```

## Usage

```ruby
# Configure AI extension
DurableWorkflow::Extensions::AI.configure do |c|
  c.api_keys[:openai] = ENV["OPENAI_API_KEY"]
  c.api_keys[:anthropic] = ENV["ANTHROPIC_API_KEY"]
  c.default_model = "gpt-4o"
end

# Use directly
chat = DurableWorkflow::Extensions::AI.chat
response = chat.ask("Hello")

# Or with specific model
chat = DurableWorkflow::Extensions::AI.chat(model: "claude-3-5-sonnet")
```

## Tests

### `test/unit/extensions/ai/configuration_test.rb`

```ruby
class ConfigurationTest < Minitest::Test
  def setup
    @config = DurableWorkflow::Extensions::AI::Configuration.new
  end

  def test_default_model
    assert_equal "gpt-4o-mini", @config.default_model
  end

  def test_api_keys_empty_by_default
    assert_equal({}, @config.api_keys)
  end

  def test_configure_yields_configuration
    DurableWorkflow::Extensions::AI.configure do |c|
      c.default_model = "test-model"
    end

    assert_equal "test-model", DurableWorkflow::Extensions::AI.configuration.default_model
  end

  def test_chat_returns_ruby_llm_chat
    # Mock RubyLLM.chat
    mock_chat = Minitest::Mock.new
    RubyLLM.stub :chat, mock_chat do
      result = DurableWorkflow::Extensions::AI.chat
      assert_equal mock_chat, result
    end
  end

  def test_chat_with_model_override
    RubyLLM.stub :chat, ->(model:) { "chat_with_#{model}" } do
      result = DurableWorkflow::Extensions::AI.chat(model: "custom")
      assert_equal "chat_with_custom", result
    end
  end
end
```

## Acceptance Criteria

1. `AI.configure` block sets API keys
2. `AI.configure` applies keys to RubyLLM
3. `AI.chat` returns RubyLLM chat instance
4. `AI.chat(model:)` overrides default model
5. Default model is "gpt-4o-mini"
