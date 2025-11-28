# 03-EXAMPLE-SUPPORT-AGENT: AI-Powered Support System

## ⚠️ STATUS: FUTURE/ASPIRATIONAL

**This document describes a FUTURE example that requires features not yet implemented:**

- `type: agent` step - NOT IMPLEMENTED
- `type: guardrail` step - NOT IMPLEMENTED
- `type: handoff` step - NOT IMPLEMENTED
- `DurableWorkflow::Extensions::AI` - NOT IMPLEMENTED
- `DurableWorkflow::Extensions::AI::MCP::Server` - NOT IMPLEMENTED
- `DurableWorkflow.register_service()` - NOT IMPLEMENTED (services use `Object.const_get`)
- `DurableWorkflow::Runners::Stream` - NOT IMPLEMENTED
- `runner.subscribe` - NOT IMPLEMENTED

**Do not attempt to run this example until these features are built.**

---

## Goal

Full-featured example app demonstrating AI extension with MCP integration. Claude Desktop can connect to this as an MCP server.

## Required Features (Not Yet Built)

1. **AI Extension** (`lib/durable_workflow/extensions/ai/`)
   - Agent step executor
   - Tool calling integration
   - Model configuration (OpenAI, Anthropic)
   - Handoff between agents

2. **Guardrails**
   - Content moderation
   - Prompt injection detection

3. **MCP Server**
   - stdio transport for Claude Desktop
   - Tool discovery and invocation

4. **Event Streaming**
   - `runner.subscribe` for real-time events
   - Stream runner for progressive output

---

## Directory Structure (When Implemented)

```
examples/support_agent/
  README.md
  Gemfile
  workflow.yml
  services.rb
  tools.rb
  run.rb                    # Interactive CLI
  mcp_server.rb             # MCP stdio server for Claude Desktop
  config/
    claude_desktop.json     # Example Claude Desktop config
```

---

## Workflow Design (Aspirational)

The workflow would:
1. Receive customer message
2. Run content moderation guardrail
3. Triage with AI agent to classify request
4. Route to specialized agent (billing, technical, general)
5. Execute tools as needed (lookup_order, create_ticket, etc.)
6. Support handoffs between agents
7. Return response

---

## Implementation Prerequisites

Before this example can work, implement:

1. `lib/durable_workflow/extensions/ai/` module
2. `agent` executor in `lib/durable_workflow/core/executors/agent.rb`
3. `guardrail` executor for content checks
4. `handoff` executor for agent transfers
5. MCP server transport layer
6. Event subscription system

See the original design below for reference when implementing.

---

## Original Design Reference

[The rest of this file contains the aspirational design that was here before.
It should be used as a reference when implementing these features, NOT as
working documentation.]
