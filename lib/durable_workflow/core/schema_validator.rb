# frozen_string_literal: true

module DurableWorkflow
  module Core
    # Runtime JSON Schema validation (optional - requires json_schemer gem)
    class SchemaValidator
      def self.validate!(value, schema, context:)
        return true if schema.nil?

        begin
          require 'json_schemer'
        rescue LoadError
          # If json_schemer not available, skip runtime validation
          DurableWorkflow.log(:debug, "json_schemer not available, skipping runtime schema validation")
          return true
        end

        schemer = JSONSchemer.schema(normalize(schema))
        errors = schemer.validate(jsonify(value)).to_a

        return true if errors.empty?

        messages = errors.map { _1['error'] }.join('; ')
        raise ValidationError, "#{context}: #{messages}"
      end

      def self.normalize(schema)
        deep_stringify(schema)
      end

      def self.jsonify(value)
        JSON.parse(value.to_json)
      end

      def self.deep_stringify(obj)
        case obj
        when Hash
          obj.transform_keys(&:to_s).transform_values { deep_stringify(_1) }
        when Array
          obj.map { deep_stringify(_1) }
        else
          obj
        end
      end
    end
  end
end
