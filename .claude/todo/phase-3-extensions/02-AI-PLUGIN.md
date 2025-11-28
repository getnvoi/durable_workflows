# 02-AI-PLUGIN: AI Extension

## Goal

Implement the AI extension as a plugin, demonstrating the extension system. Provides: agent, guardrail, handoff, file_search, mcp step types.

## Dependencies

- Phase 1 complete
- Phase 2 complete
- 01-EXTENSION-SYSTEM complete

## Files to Create

### 1. `lib/durable_workflow/extensions/ai/ai.rb` (Main loader)

```ruby
# frozen_string_literal: true

require_relative "types"
require_relative "provider"
require_relative "providers/ruby_llm"

require_relative "executors/agent"
require_relative "executors/guardrail"
require_relative "executors/handoff"
require_relative "executors/file_search"
require_relative "executors/mcp"

module DurableWorkflow
  module Extensions
    module AI
      class Extension < Base
        self.extension_name = "ai"

        def self.register_configs
          Core.register_config("agent", AgentConfig)
          Core.register_config("guardrail", GuardrailConfig)
          Core.register_config("handoff", HandoffConfig)
          Core.register_config("file_search", FileSearchConfig)
          Core.register_config("mcp", MCPConfig)
        end

        def self.register_executors
          # Executors register themselves in their files
        end

        def self.register_parser_hooks
          Core::Parser.after_parse do |workflow|
            raw = workflow.to_h
            ai_data = {
              agents: parse_agents(raw[:agents]),
              tools: parse_tools(raw[:tools])
            }
            store_in(workflow, ai_data)
          end
        end

        def self.parse_agents(agents)
          return {} unless agents

          agents.each_with_object({}) do |a, h|
            agent = AgentDef.new(
              id: a[:id],
              name: a[:name],
              model: a[:model],
              instructions: a[:instructions],
              tools: a[:tools] || [],
              handoffs: parse_handoffs(a[:handoffs])
            )
            h[agent.id] = agent
          end
        end

        def self.parse_handoffs(handoffs)
          return [] unless handoffs

          handoffs.map do |hd|
            HandoffDef.new(
              agent_id: hd[:agent_id],
              description: hd[:description]
            )
          end
        end

        def self.parse_tools(tools)
          return {} unless tools

          tools.each_with_object({}) do |t, h|
            tool = ToolDef.new(
              id: t[:id],
              description: t[:description],
              parameters: parse_tool_params(t[:parameters]),
              service: t[:service],
              method_name: t[:method]
            )
            h[tool.id] = tool
          end
        end

        def self.parse_tool_params(params)
          return [] unless params

          params.map do |p|
            ToolParam.new(
              name: p[:name],
              type: p[:type] || "string",
              required: p.fetch(:required, true),
              description: p[:description]
            )
          end
        end

        # Helper to get agents from workflow
        def self.agents(workflow)
          data_from(workflow)[:agents] || {}
        end

        # Helper to get tools from workflow
        def self.tools(workflow)
          data_from(workflow)[:tools] || {}
        end
      end

      # Setup provider (call after requiring)
      def self.setup(provider: nil)
        Provider.current = provider || Providers::RubyLLM.new
      end
    end
  end
end

# Auto-register
DurableWorkflow::Extensions.register(:ai, DurableWorkflow::Extensions::AI::Extension)
```

### 2. `lib/durable_workflow/extensions/ai/types.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      # Message role enum (AI-specific, not in core)
      module Types
        MessageRole = DurableWorkflow::Types::Strict::String.enum("system", "user", "assistant", "tool")
      end

      # Handoff definition
      class HandoffDef < BaseStruct
        attribute :agent_id, DurableWorkflow::Types::Strict::String
        attribute? :description, DurableWorkflow::Types::Strict::String.optional
      end

      # Agent definition
      class AgentDef < BaseStruct
        attribute :id, DurableWorkflow::Types::Strict::String
        attribute? :name, DurableWorkflow::Types::Strict::String.optional
        attribute :model, DurableWorkflow::Types::Strict::String
        attribute? :instructions, DurableWorkflow::Types::Strict::String.optional
        attribute :tools, DurableWorkflow::Types::Strict::Array.of(DurableWorkflow::Types::Strict::String).default([].freeze)
        attribute :handoffs, DurableWorkflow::Types::Strict::Array.of(HandoffDef).default([].freeze)
      end

      # Tool parameter
      class ToolParam < BaseStruct
        attribute :name, DurableWorkflow::Types::Strict::String
        attribute? :type, DurableWorkflow::Types::Strict::String.optional.default("string")
        attribute? :required, DurableWorkflow::Types::Strict::Bool.default(true)
        attribute? :description, DurableWorkflow::Types::Strict::String.optional
      end

      # Tool definition
      class ToolDef < BaseStruct
        attribute :id, DurableWorkflow::Types::Strict::String
        attribute :description, DurableWorkflow::Types::Strict::String
        attribute :parameters, DurableWorkflow::Types::Strict::Array.of(ToolParam).default([].freeze)
        attribute :service, DurableWorkflow::Types::Strict::String
        attribute :method_name, DurableWorkflow::Types::Strict::String

        def to_function_schema
          {
            name: id,
            description:,
            parameters: {
              type: "object",
              properties: parameters.each_with_object({}) do |p, h|
                h[p.name] = { type: p.type, description: p.description }.compact
              end,
              required: parameters.select(&:required).map(&:name)
            }
          }
        end
      end

      # Tool call from LLM
      class ToolCall < BaseStruct
        attribute :id, DurableWorkflow::Types::Strict::String
        attribute :name, DurableWorkflow::Types::Strict::String
        attribute :arguments, DurableWorkflow::Types::Hash.default({}.freeze)
      end

      # Message in conversation
      class Message < BaseStruct
        attribute :role, Types::MessageRole
        attribute? :content, DurableWorkflow::Types::Strict::String.optional
        attribute? :tool_calls, DurableWorkflow::Types::Strict::Array.of(ToolCall).optional
        attribute? :tool_call_id, DurableWorkflow::Types::Strict::String.optional
        attribute? :name, DurableWorkflow::Types::Strict::String.optional

        def self.system(content)
          new(role: "system", content:)
        end

        def self.user(content)
          new(role: "user", content:)
        end

        def self.assistant(content, tool_calls: nil)
          new(role: "assistant", content:, tool_calls:)
        end

        def self.tool(content, tool_call_id:, name: nil)
          new(role: "tool", content:, tool_call_id:, name:)
        end

        def system? = role == "system"
        def user? = role == "user"
        def assistant? = role == "assistant"
        def tool? = role == "tool"
        def tool_calls? = tool_calls&.any?
      end

      # LLM response
      class Response < BaseStruct
        attribute? :content, DurableWorkflow::Types::Strict::String.optional
        attribute :tool_calls, DurableWorkflow::Types::Strict::Array.of(ToolCall).default([].freeze)
        attribute? :finish_reason, DurableWorkflow::Types::Strict::String.optional
        attribute? :usage, DurableWorkflow::Types::Hash.optional

        def tool_calls? = tool_calls.any?
      end

      # Moderation result
      class ModerationResult < BaseStruct
        attribute :flagged, DurableWorkflow::Types::Strict::Bool
        attribute? :categories, DurableWorkflow::Types::Hash.optional
        attribute? :scores, DurableWorkflow::Types::Hash.optional
      end

      # Guardrail check
      class GuardrailCheck < BaseStruct
        attribute :type, DurableWorkflow::Types::Strict::String
        attribute? :pattern, DurableWorkflow::Types::Strict::String.optional
        attribute? :block_on_match, DurableWorkflow::Types::Strict::Bool.default(true)
        attribute? :max, DurableWorkflow::Types::Strict::Integer.optional
        attribute? :min, DurableWorkflow::Types::Strict::Integer.optional
      end

      # Guardrail result
      class GuardrailResult < BaseStruct
        attribute :passed, DurableWorkflow::Types::Strict::Bool
        attribute :check_type, DurableWorkflow::Types::Strict::String
        attribute? :reason, DurableWorkflow::Types::Strict::String.optional
      end

      # AI Step Configs
      class AgentConfig < Core::StepConfig
        attribute :agent_id, DurableWorkflow::Types::Strict::String
        attribute :prompt, DurableWorkflow::Types::Strict::String
        attribute :output, DurableWorkflow::Types::Coercible::Symbol
      end

      class GuardrailConfig < Core::StepConfig
        attribute? :content, DurableWorkflow::Types::Strict::String.optional
        attribute? :input, DurableWorkflow::Types::Strict::String.optional
        attribute :checks, DurableWorkflow::Types::Strict::Array.of(GuardrailCheck).default([].freeze)
        attribute? :on_fail, DurableWorkflow::Types::Strict::String.optional
      end

      class HandoffConfig < Core::StepConfig
        attribute? :to, DurableWorkflow::Types::Strict::String.optional
        attribute? :from, DurableWorkflow::Types::Strict::String.optional
        attribute? :reason, DurableWorkflow::Types::Strict::String.optional
      end

      class FileSearchConfig < Core::StepConfig
        attribute :query, DurableWorkflow::Types::Strict::String
        attribute :files, DurableWorkflow::Types::Strict::Array.of(DurableWorkflow::Types::Strict::String).default([].freeze)
        attribute? :max_results, DurableWorkflow::Types::Strict::Integer.optional.default(10)
        attribute? :output, DurableWorkflow::Types::Coercible::Symbol.optional
      end

      class MCPConfig < Core::StepConfig
        attribute :server, DurableWorkflow::Types::Strict::String
        attribute :tool, DurableWorkflow::Types::Strict::String
        attribute? :arguments, DurableWorkflow::Types::Hash.default({}.freeze)
        attribute? :output, DurableWorkflow::Types::Coercible::Symbol.optional
      end
    end
  end
end
```

### 3. `lib/durable_workflow/extensions/ai/provider.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      # Abstract LLM provider interface
      class Provider
        class << self
          attr_accessor :current
        end

        def complete(messages:, model:, tools: nil, **opts)
          raise NotImplementedError, "#{self.class}#complete not implemented"
        end

        def moderate(content)
          raise NotImplementedError, "#{self.class}#moderate not implemented"
        end

        def stream(messages:, model:, tools: nil, **opts, &block)
          response = complete(messages:, model:, tools:, **opts)
          yield response.content if block_given?
          response
        end
      end
    end
  end
end
```

### 4. `lib/durable_workflow/extensions/ai/providers/ruby_llm.rb`

```ruby
# frozen_string_literal: true

require "json"

module DurableWorkflow
  module Extensions
    module AI
      module Providers
        class RubyLLM < Provider
          def initialize(client: nil)
            @client = client
          end

          def complete(messages:, model:, tools: nil, **opts)
            raise "RubyLLM gem not loaded" unless defined?(::RubyLLM)

            client = @client || ::RubyLLM

            llm_messages = messages.map { |m| convert_message(m) }

            request_opts = { model: }
            request_opts[:tools] = tools if tools

            result = client.chat(llm_messages, **request_opts)

            convert_response(result)
          end

          def moderate(content)
            ModerationResult.new(flagged: false, categories: {}, scores: {})
          end

          private

            def convert_message(msg)
              case msg.role
              when "system"
                { role: :system, content: msg.content }
              when "user"
                { role: :user, content: msg.content }
              when "assistant"
                result = { role: :assistant, content: msg.content }
                result[:tool_calls] = msg.tool_calls.map { |tc| convert_tool_call(tc) } if msg.tool_calls?
                result
              when "tool"
                { role: :tool, content: msg.content, tool_call_id: msg.tool_call_id }
              else
                { role: msg.role.to_sym, content: msg.content }
              end
            end

            def convert_tool_call(tc)
              {
                id: tc.id,
                type: "function",
                function: {
                  name: tc.name,
                  arguments: tc.arguments.is_a?(String) ? tc.arguments : tc.arguments.to_json
                }
              }
            end

            def convert_response(result)
              content = result.respond_to?(:content) ? result.content : result.to_s
              tool_calls = []

              if result.respond_to?(:tool_calls) && result.tool_calls&.any?
                tool_calls = result.tool_calls.map do |tc|
                  ToolCall.new(
                    id: tc[:id] || tc["id"],
                    name: tc.dig(:function, :name) || tc.dig("function", "name"),
                    arguments: parse_arguments(tc.dig(:function, :arguments) || tc.dig("function", "arguments"))
                  )
                end
              end

              Response.new(
                content:,
                tool_calls:,
                finish_reason: result.respond_to?(:finish_reason) ? result.finish_reason : nil
              )
            end

            def parse_arguments(args)
              return {} if args.nil?
              return args if args.is_a?(Hash)
              JSON.parse(args)
            rescue JSON::ParserError
              { raw: args }
            end
        end
      end
    end
  end
end
```

### 5. `lib/durable_workflow/extensions/ai/executors/agent.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module Executors
        class Agent < Core::Executors::Base
          Core::Executors::Registry.register("agent", self)

          MAX_TOOL_ITERATIONS = 10

          def call(state)
            @current_state = state

            agent_id = config.agent_id
            agent = Extension.agents(workflow(state))[agent_id]
            raise ExecutionError, "Agent not found: #{agent_id}" unless agent

            prompt = resolve(state, config.prompt)
            messages = build_messages(agent, prompt)
            tools = build_tools(state, agent)

            response = run_agent_loop(state, agent, messages, tools)

            state = @current_state
            state = store(state, config.output, response.content)
            continue(state, output: response.content)
          end

          private

            def workflow(state)
              DurableWorkflow.registry[state.workflow_id]
            end

            def provider
              Provider.current || raise(ExecutionError, "No AI provider configured")
            end

            def build_messages(agent, prompt)
              messages = []
              messages << Message.system(agent.instructions) if agent.instructions
              messages << Message.user(prompt)
              messages
            end

            def build_tools(state, agent)
              return nil if agent.tools.empty? && agent.handoffs.empty?

              wf_tools = Extension.tools(workflow(state))
              tool_schemas = agent.tools.map do |tool_id|
                tool = wf_tools[tool_id]
                next unless tool
                tool.to_function_schema
              end.compact

              agent.handoffs.each do |handoff|
                tool_schemas << {
                  name: "transfer_to_#{handoff.agent_id}",
                  description: handoff.description || "Transfer to #{handoff.agent_id}",
                  parameters: { type: "object", properties: {}, required: [] }
                }
              end

              tool_schemas.empty? ? nil : tool_schemas
            end

            def run_agent_loop(state, agent, messages, tools)
              iterations = 0

              loop do
                iterations += 1
                raise ExecutionError, "Agent exceeded max iterations" if iterations > MAX_TOOL_ITERATIONS

                response = provider.complete(
                  messages:,
                  model: agent.model,
                  tools:
                )

                return response unless response.tool_calls?

                messages << Message.assistant(response.content, tool_calls: response.tool_calls)

                response.tool_calls.each do |tool_call|
                  result = execute_tool_call(state, agent, tool_call)
                  messages << Message.tool(result.to_s, tool_call_id: tool_call.id, name: tool_call.name)
                end
              end
            end

            def execute_tool_call(state, agent, tool_call)
              if tool_call.name.start_with?("transfer_to_")
                target_agent = tool_call.name.sub("transfer_to_", "")
                @current_state = @current_state.with_ctx(_handoff_to: target_agent)
                return "Transferring to #{target_agent}"
              end

              wf_tools = Extension.tools(workflow(state))
              tool = wf_tools[tool_call.name]
              raise ExecutionError, "Tool not found: #{tool_call.name}" unless tool

              invoke_tool(tool, tool_call.arguments)
            rescue => e
              "Error: #{e.message}"
            end

            def invoke_tool(tool, arguments)
              svc = resolve_service(tool.service)
              method = tool.method_name

              target = svc.respond_to?(method) ? svc : svc.new
              m = target.method(method)

              has_kwargs = m.parameters.any? { |type, _| %i[key keyreq keyrest].include?(type) }

              args = arguments.is_a?(Hash) ? arguments : {}
              if has_kwargs
                m.call(**args.transform_keys(&:to_sym))
              elsif m.arity == 0
                m.call
              else
                m.call(args)
              end
            end

            def resolve_service(name)
              DurableWorkflow.config&.service_resolver&.call(name) || Object.const_get(name)
            end
        end
      end
    end
  end
end
```

### 6. `lib/durable_workflow/extensions/ai/executors/guardrail.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module Executors
        class Guardrail < Core::Executors::Base
          Core::Executors::Registry.register("guardrail", self)

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
            /\b\d{3}-\d{2}-\d{4}\b/,
            /\b\d{16}\b/,
            /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/,
            /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
            /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/
          ].freeze

          def call(state)
            content = resolve(state, config.content || config.input)
            checks = config.checks || []
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
              detected = INJECTION_PATTERNS.any? { |pattern| content.match?(pattern) }
              GuardrailResult.new(
                passed: !detected,
                check_type: "prompt_injection",
                reason: detected ? "Potential prompt injection detected" : nil
              )
            end

            def check_pii(content)
              detected = PII_PATTERNS.any? { |pattern| content.match?(pattern) }
              GuardrailResult.new(
                passed: !detected,
                check_type: "pii",
                reason: detected ? "PII detected in content" : nil
              )
            end

            def check_moderation(content)
              provider = Provider.current
              return GuardrailResult.new(passed: true, check_type: "moderation") unless provider

              result = provider.moderate(content)
              GuardrailResult.new(
                passed: !result.flagged,
                check_type: "moderation",
                reason: result.flagged ? "Content flagged by moderation" : nil
              )
            end

            def check_regex(content, pattern, block_on_match = true)
              return GuardrailResult.new(passed: true, check_type: "regex") unless pattern

              matches = content.match?(Regexp.new(pattern))
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
```

### 7. `lib/durable_workflow/extensions/ai/executors/handoff.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module Executors
        class Handoff < Core::Executors::Base
          Core::Executors::Registry.register("handoff", self)

          def call(state)
            target_agent = config.to || state.ctx[:_handoff_to]
            raise ExecutionError, "No handoff target specified" unless target_agent

            workflow = DurableWorkflow.registry[state.workflow_id]
            agents = Extension.agents(workflow)
            raise ExecutionError, "Agent not found: #{target_agent}" unless agents.key?(target_agent)

            new_ctx = state.ctx.except(:_handoff_to).merge(
              _current_agent: target_agent,
              _handoff_context: {
                from: config.from,
                to: target_agent,
                reason: config.reason,
                timestamp: Time.now.iso8601
              }
            )
            state = state.with(ctx: new_ctx)

            continue(state)
          end
        end
      end
    end
  end
end
```

### 8. `lib/durable_workflow/extensions/ai/executors/file_search.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module Executors
        class FileSearch < Core::Executors::Base
          Core::Executors::Registry.register("file_search", self)

          def call(state)
            query = resolve(state, config.query)
            files = config.files || []
            max_results = config.max_results || 10

            results = search_files(query, files, max_results)

            state = store(state, config.output, results)
            continue(state, output: results)
          end

          private

            def search_files(query, files, max_results)
              # Placeholder - integrate with vector stores in production
              {
                query:,
                results: [],
                total: 0,
                searched_files: files.size
              }
            end
        end
      end
    end
  end
end
```

### 9. `lib/durable_workflow/extensions/ai/executors/mcp.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      module Executors
        class MCP < Core::Executors::Base
          Core::Executors::Registry.register("mcp", self)

          def call(state)
            server = config.server
            tool_name = config.tool
            arguments = resolve(state, config.arguments)

            result = call_mcp_tool(server, tool_name, arguments)

            state = store(state, config.output, result)
            continue(state, output: result)
          end

          private

            def call_mcp_tool(server, tool_name, arguments)
              # Placeholder - integrate with MCP client in production
              {
                server:,
                tool: tool_name,
                arguments:,
                result: nil,
                error: "MCP not configured"
              }
            end
        end
      end
    end
  end
end
```

## Usage

```ruby
# Load core
require "durable_workflow"

# Load AI extension
require "durable_workflow/extensions/ai"

# Setup provider
DurableWorkflow::Extensions::AI.setup

# Load workflow with agents
wf = DurableWorkflow.load("ai_workflow.yml")
```

## Example YAML

```yaml
id: customer-service
name: Customer Service Bot

agents:
  - id: triage
    model: gpt-4
    instructions: "You are a triage agent. Route to appropriate specialist."
    handoffs:
      - agent_id: billing
        description: "Transfer billing inquiries"
      - agent_id: technical
        description: "Transfer technical issues"

  - id: billing
    model: gpt-4
    instructions: "You handle billing questions."
    tools:
      - lookup_invoice

  - id: technical
    model: gpt-4
    instructions: "You handle technical issues."
    tools:
      - check_status

tools:
  - id: lookup_invoice
    description: "Look up an invoice by ID"
    parameters:
      - name: invoice_id
        type: string
        required: true
    service: BillingService
    method: lookup

  - id: check_status
    description: "Check system status"
    parameters: []
    service: StatusService
    method: check

steps:
  - id: start
    type: start
    next: guardrail

  - id: guardrail
    type: guardrail
    input: $input.message
    checks:
      - type: prompt_injection
      - type: pii
    on_fail: reject
    next: triage_agent

  - id: triage_agent
    type: agent
    agent_id: triage
    prompt: $input.message
    output: response
    next: end

  - id: reject
    type: end
    result:
      error: "Input rejected by guardrail"

  - id: end
    type: end
    result:
      response: $response
```

## Acceptance Criteria

1. `require "durable_workflow/extensions/ai"` registers all AI executors
2. AI step types (agent, guardrail, etc.) work in workflows
3. Agents/tools parsed from YAML into `workflow.extensions[:ai]`
4. Provider interface allows swapping LLM backends
5. Guardrail checks work independently of LLM
6. Extension doesn't pollute core types
