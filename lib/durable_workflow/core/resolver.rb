# frozen_string_literal: true

module DurableWorkflow
  module Core
    # Stateless resolver - all methods take state explicitly
    class Resolver
      PATTERN = /\$([a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)*)/

      class << self
        def resolve(state, value)
          case value
          when String then resolve_string(state, value)
          when Hash then value.transform_values { resolve(state, _1) }
          when Array then value.map { resolve(state, _1) }
          when nil then nil
          else value
          end
        end

        def resolve_ref(state, ref)
          parts = ref.split(".")
          root = parts.shift.to_sym

          base = case root
          when :input then state.input
          when :now then return Time.now
          when :history then return state.history
          else state.ctx[root]
          end

          dig(base, parts)
        end

        private

          def resolve_string(state, str)
            # Whole string is single reference -> return actual value (not stringified)
            return resolve_ref(state, str[1..]) if str.match?(/\A\$[a-zA-Z_][a-zA-Z0-9_.]*\z/)

            # Embedded references -> interpolate as strings
            str.gsub(PATTERN) { resolve_ref(state, _1[1..]).to_s }
          end

          def dig(value, keys)
            return value if keys.empty?
            key = keys.shift

            next_val = case value
            when Hash then Utils.fetch(value, key)
            when Array then key.match?(/\A\d+\z/) ? value[key.to_i] : nil
            when Struct then value.respond_to?(key) ? value.send(key) : nil
            else value.respond_to?(key) ? value.send(key) : nil
            end

            dig(next_val, keys)
          end
      end
    end
  end
end
