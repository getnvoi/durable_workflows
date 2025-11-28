# 01-DEPENDENCIES: RubyLLM + MCP as Runtime Dependencies

## Goal

Remove provider abstraction. Make `ruby_llm` and `mcp` gems required runtime dependencies.

## Gem Details

### ruby_llm

- **Gem:** `ruby_llm`
- **Repo:** https://github.com/crmne/ruby_llm
- **Features:** Multi-provider (OpenAI, Anthropic, Gemini, etc.), chat, streaming, tools, embeddings, moderation

```ruby
# Chat
chat = RubyLLM.chat
response = chat.ask("Hello")

# Streaming
chat.ask("Tell me a story") { |chunk| print chunk.content }

# Tools
class MyTool < RubyLLM::Tool
  description "Does something"
  param :input, desc: "The input"
  def execute(input:)
    # return result
  end
end
chat.with_tool(MyTool).ask("Use the tool")

# Moderation
RubyLLM.moderate("content to check")
```

### mcp (Anthropic Ruby SDK)

- **Gem:** `mcp`
- **Repo:** https://github.com/modelcontextprotocol/ruby-sdk
- **Maintainers:** Anthropic + Shopify

```ruby
# Server (expose tools)
server = MCP::Server.new(name: "my_server", tools: [...])
transport = MCP::Server::Transports::StdioTransport.new(server)
transport.open

# Client (consume external)
transport = MCP::Client::HTTP.new(url: "https://server.example.com/mcp")
client = MCP::Client.new(transport: transport)
tools = client.tools
result = client.call_tool(tool: tools.first, arguments: { foo: "bar" })
```

## Files to Modify

### `durable_workflow.gemspec`

```ruby
spec.add_dependency "ruby_llm", "~> 1.0"
spec.add_dependency "mcp", "~> 0.1"
spec.add_dependency "faraday", ">= 2.0"
```

### `Gemfile`

```ruby
# Runtime
gem "ruby_llm", "~> 1.0"
gem "mcp", "~> 0.1"
gem "faraday", ">= 2.0"
```

## Files to Delete

| File                                                       | Reason                             |
| ---------------------------------------------------------- | ---------------------------------- |
| `lib/durable_workflow/extensions/ai/provider.rb`           | Abstract provider no longer needed |
| `lib/durable_workflow/extensions/ai/providers/ruby_llm.rb` | Direct RubyLLM usage instead       |
| `lib/durable_workflow/extensions/ai/providers/`            | Entire directory                   |
| `test/unit/extensions/ai/provider_test.rb`                 | No provider to test                |

## Files to Update

### `lib/durable_workflow/extensions/ai/ai.rb`

Remove:

```ruby
require_relative "provider"
require_relative "providers/ruby_llm"
```

Add:

```ruby
require "ruby_llm"
require "mcp"
```

## Acceptance Criteria

1. `bundle install` succeeds with new dependencies
2. `require "durable_workflow/extensions/ai"` loads without error
3. No references to `Provider` class remain
4. Tests pass without provider abstraction
