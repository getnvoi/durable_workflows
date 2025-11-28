# frozen_string_literal: true

module DurableWorkflow
  module Utils
    module_function

    def deep_symbolize(obj)
      case obj
      when Hash
        obj.transform_keys(&:to_sym).transform_values { deep_symbolize(_1) }
      when Array
        obj.map { deep_symbolize(_1) }
      else
        obj
      end
    end

    # Indifferent access - handles both symbol and string keys
    def fetch(hash, key, default = nil)
      return default unless hash.is_a?(Hash)

      hash[key.to_sym] || hash[key.to_s] || default
    end
  end
end
