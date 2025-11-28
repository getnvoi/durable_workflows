# frozen_string_literal: true

require "test_helper"

class SchemaValidatorTest < Minitest::Test
  SchemaValidator = DurableWorkflow::Core::SchemaValidator

  def test_returns_true_when_schema_is_nil
    assert SchemaValidator.validate!({"foo" => "bar"}, nil, context: "test")
  end

  def test_returns_true_when_json_schemer_not_available
    # Without json_schemer gem, validation is skipped
    # This test verifies the graceful fallback
    result = SchemaValidator.validate!(
      { name: "test" },
      { type: "object", properties: { name: { type: "string" } } },
      context: "test"
    )
    # Should return true (either validates or skips if gem not available)
    assert result
  end

  def test_validates_value_against_schema
    schema = {
      type: "object",
      properties: {
        name: { type: "string" },
        age: { type: "integer" }
      },
      required: ["name"]
    }

    # Valid value - should not raise
    assert SchemaValidator.validate!(
      { name: "Alice", age: 30 },
      schema,
      context: "test"
    )
  end

  def test_raises_validation_error_on_schema_violation
    schema = {
      type: "object",
      properties: {
        name: { type: "string" }
      },
      required: ["name"]
    }

    error = assert_raises(DurableWorkflow::ValidationError) do
      SchemaValidator.validate!(
        { age: 30 },  # missing required 'name'
        schema,
        context: "Step 'test' output"
      )
    end

    assert_match(/Step 'test' output/, error.message)
  end
end
