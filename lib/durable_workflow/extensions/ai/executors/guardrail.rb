# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module Executors
        class Guardrail < Core::Executors::Base
          INJECTION_PATTERNS = [
            /ignore\s+(all\s+)?previous\s+instructions/i,
            /disregard\s+(all\s+)?previous/i,
            /forget\s+(everything|all)/i,
            /you\s+are\s+now\s+/i,
            /new\s+instructions?:/i,
            /system\s*:\s*/i,
            /\[system\]/i,
            /pretend\s+you\s+are/i,
            /act\s+as\s+if/i,
            /roleplay\s+as/i
          ].freeze

          PII_PATTERNS = [
            /\b\d{3}-\d{2}-\d{4}\b/,                           # SSN
            /\b\d{16}\b/,                                       # Credit card (no spaces)
            /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/,      # Credit card (with spaces/dashes)
            /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, # Email
            /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/                     # Phone
          ].freeze

          def call(state)
            content = resolve(state, config.content || config.input)
            checks = parse_checks(config.checks)
            on_fail = config.on_fail

            results = checks.map { |check| run_check(check, content) }
            failed = results.find { |r| !r.passed }

            if failed
              state = state.with_ctx(_guardrail_failure: {
                check_type: failed.check_type,
                reason: failed.reason
              })
              return on_fail ? continue(state, next_step: on_fail) : raise(ExecutionError, "Guardrail failed: #{failed.reason}")
            end

            continue(state)
          end

          private

            def parse_checks(checks)
              checks.map do |check|
                case check
                when Hash
                  GuardrailCheck.new(
                    type: check[:type],
                    pattern: check[:pattern],
                    block_on_match: check.fetch(:block_on_match, true),
                    max: check[:max],
                    min: check[:min]
                  )
                when GuardrailCheck
                  check
                else
                  GuardrailCheck.new(type: check.to_s)
                end
              end
            end

            def run_check(check, content)
              case check.type
              when "prompt_injection"
                check_prompt_injection(content)
              when "pii"
                check_pii(content)
              when "moderation"
                check_moderation(content)
              when "regex"
                check_regex(content, check.pattern, check.block_on_match)
              when "length"
                check_length(content, check.max, check.min)
              else
                GuardrailResult.new(passed: true, check_type: check.type)
              end
            end

            def check_prompt_injection(content)
              detected = INJECTION_PATTERNS.any? { |pattern| content.to_s.match?(pattern) }
              GuardrailResult.new(
                passed: !detected,
                check_type: "prompt_injection",
                reason: detected ? "Potential prompt injection detected" : nil
              )
            end

            def check_pii(content)
              detected = PII_PATTERNS.any? { |pattern| content.to_s.match?(pattern) }
              GuardrailResult.new(
                passed: !detected,
                check_type: "pii",
                reason: detected ? "PII detected in content" : nil
              )
            end

            def check_moderation(content)
              result = RubyLLM.moderate(content)
              GuardrailResult.new(
                passed: !result.flagged,
                check_type: "moderation",
                reason: result.flagged ? "Content flagged by moderation" : nil
              )
            rescue => e
              # If moderation fails (e.g., no API key), pass by default
              GuardrailResult.new(passed: true, check_type: "moderation")
            end

            def check_regex(content, pattern, block_on_match = true)
              return GuardrailResult.new(passed: true, check_type: "regex") unless pattern

              matches = content.to_s.match?(Regexp.new(pattern))
              passed = block_on_match ? !matches : matches

              GuardrailResult.new(
                passed:,
                check_type: "regex",
                reason: passed ? nil : "Content #{block_on_match ? 'matched' : 'did not match'} pattern"
              )
            end

            def check_length(content, max, min)
              len = content.to_s.length
              passed = true
              reason = nil

              if max && len > max
                passed = false
                reason = "Content exceeds max length (#{len} > #{max})"
              elsif min && len < min
                passed = false
                reason = "Content below min length (#{len} < #{min})"
              end

              GuardrailResult.new(passed:, check_type: "length", reason:)
            end
        end
      end
    end
  end
end
