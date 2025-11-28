# Phase 4: AI Rework - RubyLLM + MCP Deep Integration

## Overview

Rework AI extension to fully embrace `ruby_llm` and `mcp` gems as internal dependencies. Two-way MCP integration: expose workflow tools AND consume external MCP servers.

## Status Legend

- [ ] Not started
- [~] In progress
- [x] Completed

---

## 1. DEPENDENCIES & CLEANUP (01-DEPENDENCIES.md)

### 1.1 Update Dependencies

- [ ] Add `ruby_llm` to gemspec as runtime dependency
- [ ] Add `mcp` to gemspec as runtime dependency
- [ ] Add `faraday` to gemspec as runtime dependency
- [ ] Update Gemfile with new dependencies
- [ ] Run `bundle install`

### 1.2 Delete Provider Abstraction

- [ ] Delete `lib/durable_workflow/extensions/ai/provider.rb`
- [ ] Delete `lib/durable_workflow/extensions/ai/providers/` directory
- [ ] Delete `test/unit/extensions/ai/provider_test.rb`
- [ ] Update `lib/durable_workflow/extensions/ai/ai.rb` requires

---

## 2. CONFIGURATION (02-CONFIGURATION.md)

### 2.1 Implementation

- [ ] Create `lib/durable_workflow/extensions/ai/configuration.rb`
- [ ] Add `AI.configuration` class method
- [ ] Add `AI.configure` with block yield
- [ ] Add `AI.chat(model:)` helper
- [ ] Apply API keys to RubyLLM in configure

### 2.2 Tests

- [ ] Create `test/unit/extensions/ai/configuration_test.rb`
- [ ] Test: `AI.configuration` returns Configuration instance
- [ ] Test: `AI.configure` yields configuration
- [ ] Test: `AI.configure` applies keys to RubyLLM
- [ ] Test: `AI.chat` returns RubyLLM chat instance
- [ ] Test: `AI.chat(model:)` uses specified model
- [ ] Test: Default model is "gpt-4o-mini"

---

## 3. TOOL REGISTRY (03-TOOL-REGISTRY.md)

### 3.1 Implementation

- [ ] Add `ToolDef#to_ruby_llm_tool` method to types.rb
- [ ] Create `lib/durable_workflow/extensions/ai/tool_registry.rb`
- [ ] Implement `ToolRegistry.register(tool_class)`
- [ ] Implement `ToolRegistry.register_from_def(tool_def)`
- [ ] Implement `ToolRegistry[name]`
- [ ] Implement `ToolRegistry.for_workflow(workflow)`
- [ ] Update parser to register tools on parse

### 3.2 Tests

- [ ] Create `test/unit/extensions/ai/tool_registry_test.rb`
- [ ] Test: `ToolDef#to_ruby_llm_tool` creates RubyLLM::Tool subclass
- [ ] Test: Generated tool has correct description
- [ ] Test: Generated tool has correct parameters
- [ ] Test: Generated tool execute calls service method
- [ ] Test: `ToolRegistry.register` stores tool class
- [ ] Test: `ToolRegistry[]` retrieves tool class
- [ ] Test: `ToolRegistry.for_workflow` returns workflow tools

---

## 4. MCP SERVER - EXPOSE TOOLS (04-MCP-SERVER.md)

### 4.1 Implementation

- [ ] Create `lib/durable_workflow/extensions/ai/mcp/` directory
- [ ] Create `lib/durable_workflow/extensions/ai/mcp/adapter.rb`
- [ ] Implement `Adapter.to_mcp_tool(ruby_llm_tool)`
- [ ] Create `lib/durable_workflow/extensions/ai/mcp/server.rb`
- [ ] Implement `Server.build(workflow)`
- [ ] Implement `Server.stdio(workflow)`
- [ ] Implement `Server.rack_app(workflow)`
- [ ] Create `lib/durable_workflow/extensions/ai/mcp/rack_app.rb`
- [ ] Create `exe/durable_workflow_mcp` CLI

### 4.2 Tests

- [ ] Create `test/unit/extensions/ai/mcp/adapter_test.rb`
- [ ] Test: `Adapter.to_mcp_tool` converts RubyLLM::Tool to MCP::Tool
- [ ] Test: Converted tool has correct name
- [ ] Test: Converted tool has correct description
- [ ] Test: Converted tool has correct schema
- [ ] Test: Converted tool executes and returns response
- [ ] Test: Converted tool handles errors gracefully
- [ ] Create `test/unit/extensions/ai/mcp/server_test.rb`
- [ ] Test: `Server.build` creates MCP::Server
- [ ] Test: Server includes workflow tools
- [ ] Test: Server with `expose_workflow: true` includes workflow tool
- [ ] Test: `Server.rack_app` returns Rack-compatible app

---

## 5. MCP CLIENT - CONSUME EXTERNAL (05-MCP-CLIENT.md)

### 5.1 Implementation

- [ ] Create `lib/durable_workflow/extensions/ai/mcp/client.rb`
- [ ] Implement `Client.for(server_config)` with caching
- [ ] Implement `Client.tools(server_config)`
- [ ] Implement `Client.call_tool(server_config, tool_name, args)`
- [ ] Support HTTP transport
- [ ] Support stdio transport
- [ ] Implement env variable interpolation in headers
- [ ] Add `MCPServerConfig` to types.rb
- [ ] Update parser to parse `mcp_servers` section
- [ ] Rewrite `lib/durable_workflow/extensions/ai/executors/mcp.rb`

### 5.2 Tests

- [ ] Create `test/unit/extensions/ai/mcp/client_test.rb`
- [ ] Test: `Client.for` creates client with HTTP transport
- [ ] Test: `Client.for` caches connections
- [ ] Test: `Client.tools` returns tool list
- [ ] Test: `Client.call_tool` invokes tool
- [ ] Test: `Client.call_tool` raises for unknown tool
- [ ] Test: `Client.reset!` clears cache
- [ ] Test: Environment variables interpolated in headers
- [ ] Update `test/unit/extensions/ai/executors/mcp_test.rb`
- [ ] Test: MCP executor resolves server config
- [ ] Test: MCP executor calls tool via Client
- [ ] Test: MCP executor stores result in output
- [ ] Test: MCP executor raises for unknown server

---

## 6. EXECUTORS UPDATE (06-EXECUTORS.md)

### 6.1 Agent Executor

- [ ] Rewrite `lib/durable_workflow/extensions/ai/executors/agent.rb`
- [ ] Use `AI.chat(model:)` directly
- [ ] Attach tools from ToolRegistry
- [ ] Set system instructions
- [ ] Update `test/unit/extensions/ai/executors/agent_test.rb`
- [ ] Test: Agent resolves agent definition
- [ ] Test: Agent builds chat with correct model
- [ ] Test: Agent attaches tools to chat
- [ ] Test: Agent sets system instructions
- [ ] Test: Agent executes and stores response
- [ ] Test: Agent raises for unknown agent_id

### 6.2 Guardrail Executor

- [ ] Update `lib/durable_workflow/extensions/ai/executors/guardrail.rb`
- [ ] Replace provider.moderate with `RubyLLM.moderate`
- [ ] Update `test/unit/extensions/ai/executors/guardrail_test.rb`
- [ ] Test: Moderation check calls RubyLLM.moderate
- [ ] Test: Moderation check fails when flagged
- [ ] Test: Moderation check passes when not flagged
- [ ] Test: Moderation check handles errors gracefully (fail-open)

---

## 7. INTEGRATION TESTS

### 7.1 MCP Server Integration

- [ ] Create `test/integration/ai/mcp_server_test.rb`
- [ ] Test: Workflow tools exposed via MCP server
- [ ] Test: tools/list returns workflow tools
- [ ] Test: tools/call executes tool and returns result
- [ ] Test: Workflow exposed as tool when configured

### 7.2 MCP Client Integration

- [ ] Create `test/integration/ai/mcp_client_test.rb`
- [ ] Test: mcp step calls external server (mocked)
- [ ] Test: mcp step stores result in state

### 7.3 Agent Integration

- [ ] Create `test/integration/ai/agent_test.rb`
- [ ] Test: Agent uses workflow-defined tools
- [ ] Test: Agent tool execution calls service method

---

## 8. DOCUMENTATION

### 8.1 README Updates

- [ ] Add MCP server setup instructions
- [ ] Add Claude Desktop configuration example
- [ ] Add HTTP endpoint mounting example
- [ ] Add mcp_servers YAML configuration example

### 8.2 Examples

- [ ] Create `examples/mcp_server.rb` - Stdio server example
- [ ] Create `examples/mcp_rails.rb` - Rails integration example
- [ ] Create `examples/workflow_with_mcp.yml` - Workflow using external MCP

---

## File Changes Summary

| Action | Path |
|--------|------|
| DELETE | `lib/durable_workflow/extensions/ai/provider.rb` |
| DELETE | `lib/durable_workflow/extensions/ai/providers/` |
| DELETE | `test/unit/extensions/ai/provider_test.rb` |
| CREATE | `lib/durable_workflow/extensions/ai/configuration.rb` |
| CREATE | `lib/durable_workflow/extensions/ai/tool_registry.rb` |
| CREATE | `lib/durable_workflow/extensions/ai/mcp/adapter.rb` |
| CREATE | `lib/durable_workflow/extensions/ai/mcp/server.rb` |
| CREATE | `lib/durable_workflow/extensions/ai/mcp/rack_app.rb` |
| CREATE | `lib/durable_workflow/extensions/ai/mcp/client.rb` |
| CREATE | `exe/durable_workflow_mcp` |
| MODIFY | `durable_workflow.gemspec` |
| MODIFY | `Gemfile` |
| MODIFY | `lib/durable_workflow/extensions/ai/ai.rb` |
| MODIFY | `lib/durable_workflow/extensions/ai/types.rb` |
| MODIFY | `lib/durable_workflow/extensions/ai/executors/agent.rb` |
| MODIFY | `lib/durable_workflow/extensions/ai/executors/mcp.rb` |
| MODIFY | `lib/durable_workflow/extensions/ai/executors/guardrail.rb` |

---

## Summary Stats

| Section | Implementation | Tests | Total |
|---------|----------------|-------|-------|
| 1. Dependencies | 9 | 0 | 9 |
| 2. Configuration | 5 | 7 | 12 |
| 3. Tool Registry | 7 | 8 | 15 |
| 4. MCP Server | 9 | 11 | 20 |
| 5. MCP Client | 10 | 12 | 22 |
| 6. Executors | 8 | 11 | 19 |
| 7. Integration | 0 | 7 | 7 |
| 8. Documentation | 6 | 0 | 6 |
| **TOTAL** | **54** | **56** | **110** |

---

## Acceptance Criteria

- [ ] `ruby_llm` and `mcp` are runtime dependencies
- [ ] No provider abstraction layer
- [ ] Tools defined in YAML convert to RubyLLM::Tool
- [ ] Tools exposed via MCP::Server
- [ ] `durable_workflow_mcp` CLI works with Claude Desktop
- [ ] Rack app mounts in Rails/Sinatra
- [ ] `mcp` step executor calls external MCP servers
- [ ] Agent executor uses RubyLLM directly
- [ ] Guardrail uses RubyLLM.moderate
- [ ] All tests pass
