# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Call < Base
        Registry.register('call', self)

        def call(state)
          svc = resolve_service(config.service)
          method = config.method_name
          input = resolve(state, config.input)

          result = with_retry(
            max_retries: config.retries,
            delay: config.retry_delay,
            backoff: config.retry_backoff
          ) do
            with_timeout { invoke(svc, method, input) }
          end

          # Runtime schema validation (if schema defined)
          validate_output!(result) if output_schema

          state = store(state, output_key, result)
          continue(state, output: result)
        end

        private

        def resolve_service(name)
          DurableWorkflow.config&.service_resolver&.call(name) || Object.const_get(name)
        end

        def invoke(svc, method, input)
          target = svc.respond_to?(method) ? svc : svc.new
          m = target.method(method)

          # Check if method takes keyword args
          has_kwargs = m.parameters.any? { |type, _| %i[key keyreq keyrest].include?(type) }

          if has_kwargs && input.is_a?(Hash)
            m.call(**input.transform_keys(&:to_sym))
          elsif m.arity.zero?
            m.call
          else
            m.call(input)
          end
        end

        def output_key
          case config.output
          when Symbol, String then config.output
          when OutputConfig then config.output.key
          when Hash then config.output[:key]
          end
        end

        def output_schema
          case config.output
          when OutputConfig then config.output.schema
          when Hash then config.output[:schema]
          end
        end

        def validate_output!(result)
          SchemaValidator.validate!(
            result,
            output_schema,
            context: "Step '#{step.id}' output"
          )
        end
      end
    end
  end
end
