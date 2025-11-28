# Support Agent

AI-powered customer support workflow with tool calling and MCP integration.

## Features

- Multi-agent system (triage, billing, technical)
- Tool integration (lookup orders, create tickets, check status)
- Handoffs between specialized agents
- Content moderation guardrails
- MCP server for Claude Desktop integration

## Setup

```bash
cd examples/support_agent
bundle install

# Set API key
export OPENAI_API_KEY=your-key
# or
export ANTHROPIC_API_KEY=your-key

# Start Redis
redis-server
```

## Usage

### Interactive CLI

```bash
ruby run.rb
```

### As MCP Server (Claude Desktop)

1. Copy config to Claude Desktop:
```bash
cp config/claude_desktop.json ~/.config/claude/claude_desktop_config.json
```

2. Restart Claude Desktop

3. The support tools will be available in Claude

## Architecture

```
User Input
    ↓
┌─────────────┐
│   Triage    │ ← Classifies request
│   Agent     │
└─────────────┘
    ↓
┌─────────────────────────────────┐
│         Router                  │
├─────────────┬─────────┬─────────┤
│   Billing   │  Tech   │  Other  │
│   Agent     │  Agent  │         │
└─────────────┴─────────┴─────────┘
    ↓
Tools: lookup_order, create_ticket, check_status, escalate
```

## Tools Available

| Tool | Description |
|------|-------------|
| `lookup_order` | Find order by ID or customer email |
| `create_ticket` | Create support ticket |
| `check_status` | Check ticket status |
| `escalate` | Escalate to human agent |
| `refund_order` | Process refund (billing only) |
| `reset_password` | Reset user password (tech only) |

## MCP Integration

When running as MCP server, external AI agents can:

1. Discover available tools via `tools/list`
2. Call tools via `tools/call`
3. Run the full workflow as a tool

Example Claude Desktop interaction:
```
User: "I need help with order ORD-12345"
Claude: [calls lookup_order with order_id: "ORD-12345"]
Claude: "I found your order. It was placed on..."
```
