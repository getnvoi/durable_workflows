# Phase 3 Extensions - Implementation & Test Coverage Todo

## Status Legend

- [ ] Not started
- [~] In progress
- [x] Completed

---

## 1. EXTENSION SYSTEM (01-EXTENSION-SYSTEM.md)

### 1.1 Implementation

- [ ] Create `lib/durable_workflow/extensions/` directory
- [ ] Create `lib/durable_workflow/extensions/base.rb` with Extensions::Base class
- [ ] Update `lib/durable_workflow/core/types/configs.rb` to add `Core.register_config(type, klass)` method
- [ ] Update `lib/durable_workflow/core/types/configs.rb` to add `Core.config_registered?(type)` method
- [ ] Update `lib/durable_workflow/core/parser.rb` with `before_parse`, `after_parse`, `transform_config` hooks
- [ ] Update `lib/durable_workflow.rb` to require extensions/base

### 1.2 Tests - Extensions::Base

- [ ] Test: `Extensions::Base.extension_name` returns class-derived name
- [ ] Test: `Extensions::Base.extension_name=` sets custom name
- [ ] Test: `Extensions::Base.register!` calls register_configs, register_executors, register_parser_hooks
- [ ] Test: `Extensions::Base.data_from(workflow)` returns extension data
- [ ] Test: `Extensions::Base.store_in(workflow, data)` stores in extensions hash

### 1.3 Tests - Extensions Registry

- [ ] Test: `Extensions.register(name, klass)` registers extension
- [ ] Test: `Extensions.register(name, klass)` calls `klass.register!`
- [ ] Test: `Extensions[name]` returns registered extension
- [ ] Test: `Extensions.loaded?(name)` returns true for registered
- [ ] Test: `Extensions.loaded?(name)` returns false for unregistered

### 1.4 Tests - Config Registration

- [ ] Test: `Core.register_config(type, klass)` adds to CONFIG_REGISTRY
- [ ] Test: `Core.config_registered?(type)` returns true for registered
- [ ] Test: `Core.config_registered?(type)` returns false for unregistered

### 1.5 Tests - Parser Hooks

- [ ] Test: `Parser.before_parse` hooks run before parsing
- [ ] Test: `Parser.before_parse` hooks can modify raw YAML
- [ ] Test: `Parser.after_parse` hooks run after parsing
- [ ] Test: `Parser.after_parse` hooks receive WorkflowDef
- [ ] Test: `Parser.after_parse` hooks can return modified WorkflowDef
- [ ] Test: `Parser.transform_config(type)` transforms config for specific type
- [ ] Test: Multiple hooks run in order registered

### 1.6 Tests - Extension Loading

- [ ] Test: Requiring extension auto-registers it
- [ ] Test: Extension step types available after loading
- [ ] Test: Unknown step types fail validation when extension not loaded

---

## 2. AI EXTENSION (02-AI-PLUGIN.md)

### 2.1 Implementation - Core Files

- [ ] Create `lib/durable_workflow/extensions/ai/` directory
- [ ] Create `lib/durable_workflow/extensions/ai/ai.rb` (main loader & Extension class)
- [ ] Create `lib/durable_workflow/extensions/ai/types.rb` (AI-specific types)
- [ ] Create `lib/durable_workflow/extensions/ai/provider.rb` (abstract provider interface)
- [ ] Create `lib/durable_workflow/extensions/ai/providers/ruby_llm.rb` (RubyLLM provider)

### 2.2 Implementation - Executors

- [ ] Create `lib/durable_workflow/extensions/ai/executors/agent.rb`
- [ ] Create `lib/durable_workflow/extensions/ai/executors/guardrail.rb`
- [ ] Create `lib/durable_workflow/extensions/ai/executors/handoff.rb`
- [ ] Create `lib/durable_workflow/extensions/ai/executors/file_search.rb`
- [ ] Create `lib/durable_workflow/extensions/ai/executors/mcp.rb`

### 2.3 Tests - AI Types

- [ ] Test: `Types::MessageRole` accepts "system", "user", "assistant", "tool"
- [ ] Test: `HandoffDef` can be created with agent_id and description
- [ ] Test: `AgentDef` can be created with id, model, instructions, tools, handoffs
- [ ] Test: `AgentDef.tools` defaults to empty array
- [ ] Test: `AgentDef.handoffs` defaults to empty array
- [ ] Test: `ToolParam` can be created with name, type, required, description
- [ ] Test: `ToolParam.type` defaults to "string"
- [ ] Test: `ToolParam.required` defaults to true
- [ ] Test: `ToolDef` can be created with id, description, parameters, service, method_name
- [ ] Test: `ToolDef.to_function_schema` returns valid function schema
- [ ] Test: `ToolCall` can be created with id, name, arguments
- [ ] Test: `Message.system(content)` creates system message
- [ ] Test: `Message.user(content)` creates user message
- [ ] Test: `Message.assistant(content)` creates assistant message
- [ ] Test: `Message.tool(content, tool_call_id:)` creates tool message
- [ ] Test: `Message.tool_calls?` returns true when tool_calls present
- [ ] Test: `Response` stores content, tool_calls, finish_reason
- [ ] Test: `Response.tool_calls?` returns true when tool_calls present
- [ ] Test: `ModerationResult` stores flagged, categories, scores
- [ ] Test: `GuardrailCheck` stores type, pattern, block_on_match, max, min
- [ ] Test: `GuardrailResult` stores passed, check_type, reason

### 2.4 Tests - AI Configs

- [ ] Test: `AgentConfig` requires agent_id, prompt, output
- [ ] Test: `GuardrailConfig` accepts content, input, checks, on_fail
- [ ] Test: `HandoffConfig` accepts to, from, reason
- [ ] Test: `FileSearchConfig` requires query, accepts files, max_results, output
- [ ] Test: `MCPConfig` requires server, tool, accepts arguments, output

### 2.5 Tests - Provider Interface

- [ ] Test: `Provider.current` is nil by default
- [ ] Test: `Provider.current=` sets current provider
- [ ] Test: `Provider#complete` raises NotImplementedError
- [ ] Test: `Provider#moderate` raises NotImplementedError
- [ ] Test: `Provider#stream` falls back to complete

### 2.6 Tests - RubyLLM Provider

- [ ] Test: `RubyLLM#complete` raises when RubyLLM gem not loaded
- [ ] Test: `RubyLLM#complete` converts Message to RubyLLM format
- [ ] Test: `RubyLLM#complete` returns Response
- [ ] Test: `RubyLLM#complete` parses tool_calls from response
- [ ] Test: `RubyLLM#moderate` returns ModerationResult (default unflagged)

### 2.7 Tests - Agent Executor

- [ ] Test: Agent executor is registered as "agent"
- [ ] Test: Agent raises ExecutionError when agent_id not found
- [ ] Test: Agent builds messages with system instruction
- [ ] Test: Agent resolves prompt from state
- [ ] Test: Agent calls provider.complete
- [ ] Test: Agent stores response content in output
- [ ] Test: Agent handles tool calls
- [ ] Test: Agent respects MAX_TOOL_ITERATIONS
- [ ] Test: Agent handles handoff tool calls
- [ ] Test: Agent raises ExecutionError when provider not configured

### 2.8 Tests - Guardrail Executor

- [ ] Test: Guardrail executor is registered as "guardrail"
- [ ] Test: Guardrail resolves content from state
- [ ] Test: Guardrail check "prompt_injection" detects injection patterns
- [ ] Test: Guardrail check "pii" detects SSN pattern
- [ ] Test: Guardrail check "pii" detects credit card pattern
- [ ] Test: Guardrail check "pii" detects email pattern
- [ ] Test: Guardrail check "pii" detects phone pattern
- [ ] Test: Guardrail check "moderation" calls provider.moderate
- [ ] Test: Guardrail check "regex" matches pattern
- [ ] Test: Guardrail check "regex" respects block_on_match=false
- [ ] Test: Guardrail check "length" validates max length
- [ ] Test: Guardrail check "length" validates min length
- [ ] Test: Guardrail on_fail routes to specified step
- [ ] Test: Guardrail raises ExecutionError when no on_fail and check fails
- [ ] Test: Guardrail stores failure info in ctx on fail

### 2.9 Tests - Handoff Executor

- [ ] Test: Handoff executor is registered as "handoff"
- [ ] Test: Handoff uses config.to as target agent
- [ ] Test: Handoff falls back to ctx[:_handoff_to]
- [ ] Test: Handoff raises ExecutionError when no target
- [ ] Test: Handoff raises ExecutionError when target agent not found
- [ ] Test: Handoff sets _current_agent in ctx
- [ ] Test: Handoff sets _handoff_context in ctx
- [ ] Test: Handoff removes _handoff_to from ctx

### 2.10 Tests - FileSearch Executor

- [ ] Test: FileSearch executor is registered as "file_search"
- [ ] Test: FileSearch resolves query from state
- [ ] Test: FileSearch stores results in output
- [ ] Test: FileSearch respects max_results

### 2.11 Tests - MCP Executor

- [ ] Test: MCP executor is registered as "mcp"
- [ ] Test: MCP resolves arguments from state
- [ ] Test: MCP stores result in output
- [ ] Test: MCP includes server and tool in result

### 2.12 Tests - AI Extension Class

- [ ] Test: `AI::Extension.extension_name` is "ai"
- [ ] Test: `AI::Extension.register_configs` registers all AI configs
- [ ] Test: `AI::Extension.parse_agents` parses agents from YAML
- [ ] Test: `AI::Extension.parse_tools` parses tools from YAML
- [ ] Test: `AI::Extension.parse_handoffs` parses handoffs
- [ ] Test: `AI::Extension.agents(workflow)` returns agents hash
- [ ] Test: `AI::Extension.tools(workflow)` returns tools hash
- [ ] Test: `AI.setup` sets default provider
- [ ] Test: `AI.setup(provider:)` sets custom provider

### 2.13 Tests - AI Parser Integration

- [ ] Test: Parser parses agents section into extensions[:ai][:agents]
- [ ] Test: Parser parses tools section into extensions[:ai][:tools]
- [ ] Test: Agent steps resolve agent_id from extensions[:ai][:agents]
- [ ] Test: Tool calls resolve tool from extensions[:ai][:tools]

---

## 3. INTEGRATION TESTS

### 3.1 Extension System Integration

- [ ] Test: Custom extension with step type works end-to-end
- [ ] Test: Multiple extensions can be loaded
- [ ] Test: Extension data persists through workflow execution

### 3.2 AI Extension Integration

- [ ] Test: Workflow with agent step (mocked provider)
- [ ] Test: Workflow with guardrail -> agent pipeline
- [ ] Test: Workflow with multiple agents and handoffs
- [ ] Test: Agent tool calling works with defined tools
- [ ] Test: Guardrail rejection routes to error step

---

## 4. TEST FILE ORGANIZATION

### 4.1 Test Files to Create

- [ ] Create `test/unit/extensions/base_test.rb`
- [ ] Create `test/unit/extensions/registry_test.rb`
- [ ] Create `test/unit/core/parser_hooks_test.rb`
- [ ] Create `test/unit/extensions/ai/types_test.rb`
- [ ] Create `test/unit/extensions/ai/provider_test.rb`
- [ ] Create `test/unit/extensions/ai/providers/ruby_llm_test.rb`
- [ ] Create `test/unit/extensions/ai/executors/agent_test.rb`
- [ ] Create `test/unit/extensions/ai/executors/guardrail_test.rb`
- [ ] Create `test/unit/extensions/ai/executors/handoff_test.rb`
- [ ] Create `test/unit/extensions/ai/executors/file_search_test.rb`
- [ ] Create `test/unit/extensions/ai/executors/mcp_test.rb`
- [ ] Create `test/unit/extensions/ai/extension_test.rb`
- [ ] Create `test/integration/extension_test.rb`
- [ ] Create `test/integration/ai_workflow_test.rb`
- [ ] Create `test/support/mock_provider.rb`

---

## Summary Stats

| Section                     | Implementation Tasks | Test Tasks | Total   |
| --------------------------- | -------------------- | ---------- | ------- |
| 1. Extension System         | 6                    | 18         | 24      |
| 2. AI Extension             | 10                   | 76         | 86      |
| 3. Integration Tests        | 0                    | 8          | 8       |
| 4. Test Files               | 15                   | 0          | 15      |
| **TOTAL**                   | **31**               | **102**    | **133** |

---

## Notes

- Extension system must be completed before AI extension
- AI extension tests require mock provider for isolation
- RubyLLM provider tests should be skipped if gem not available
- FileSearch and MCP are placeholder implementations (integrate with real backends later)
