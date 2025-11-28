# frozen_string_literal: true

require "test_helper"
require "durable_workflow/extensions/ai"

class ConfigurationTest < Minitest::Test
  AI = DurableWorkflow::Extensions::AI

  def setup
    @original_config = AI.instance_variable_get(:@configuration)
    AI.instance_variable_set(:@configuration, nil)
  end

  def teardown
    AI.instance_variable_set(:@configuration, @original_config)
  end

  def test_default_model_is_gpt_4o_mini
    config = AI::Configuration.new
    assert_equal "gpt-4o-mini", config.default_model
  end

  def test_api_keys_empty_by_default
    config = AI::Configuration.new
    assert_equal({}, config.api_keys)
  end

  def test_configure_yields_configuration
    AI.configure do |c|
      c.default_model = "claude-3-sonnet"
      c.api_keys[:anthropic] = "test-key"
    end

    assert_equal "claude-3-sonnet", AI.configuration.default_model
    assert_equal "test-key", AI.configuration.api_keys[:anthropic]
  end

  def test_configuration_returns_same_instance
    config1 = AI.configuration
    config2 = AI.configuration

    assert_same config1, config2
  end

  def test_chat_uses_default_model
    model_used = nil

    RubyLLM.stub :chat, ->(model:) {
      model_used = model
      Object.new
    } do
      AI.chat
    end

    assert_equal AI.configuration.default_model, model_used
  end

  def test_chat_accepts_model_override
    model_used = nil

    RubyLLM.stub :chat, ->(model:) {
      model_used = model
      Object.new
    } do
      AI.chat(model: "gpt-4")
    end

    assert_equal "gpt-4", model_used
  end
end
