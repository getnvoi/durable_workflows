# 03-TOOL-REGISTRY: RubyLLM::Tool as Source of Truth

## Goal

Tools defined in workflow YAML convert to RubyLLM::Tool classes. Single registry for all tools.

## Architecture

```
YAML tools:           Ruby classes:           Registry:
  lookup_order    →   RubyLLM::Tool subclass → ToolRegistry["lookup_order"]
  create_ticket   →   RubyLLM::Tool subclass → ToolRegistry["create_ticket"]
```

## Files to Update

### `lib/durable_workflow/extensions/ai/types.rb`

Add `to_ruby_llm_tool` method to ToolDef:

```ruby
class ToolDef < BaseStruct
  attribute :id, Types::Strict::String
  attribute :description, Types::Strict::String
  attribute :parameters, Types::Strict::Array.default([].freeze)
  attribute :service, Types::Strict::String
  attribute :method_name, Types::Strict::String

  # Convert to RubyLLM::Tool class
  def to_ruby_llm_tool
    tool_def = self

    Class.new(RubyLLM::Tool) do
      # Store reference to original definition
      @tool_def = tool_def

      # Set description
      description tool_def.description

      # Define parameters
      tool_def.parameters.each do |p|
        param p.name.to_sym,
              type: p.type.to_sym,
              desc: p.description,
              required: p.required
      end

      # Execute calls the service method
      define_method(:execute) do |**args|
        svc = Object.const_get(tool_def.service)
        svc.public_send(tool_def.method_name, **args)
      end

      class << self
        attr_reader :tool_def
      end
    end
  end
end
```

## Files to Create

### `lib/durable_workflow/extensions/ai/tool_registry.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    module AI
      class ToolRegistry
        class << self
          def registry
            @registry ||= {}
          end

          # Register a RubyLLM::Tool class directly
          def register(tool_class)
            name = tool_name(tool_class)
            registry[name] = tool_class
          end

          # Register from ToolDef (YAML-defined)
          def register_from_def(tool_def)
            tool_class = tool_def.to_ruby_llm_tool
            registry[tool_def.id] = tool_class
          end

          # Get tool class by name
          def [](name)
            registry[name.to_s]
          end

          # Get all tool classes
          def all
            registry.values
          end

          # Get tools for a workflow
          def for_workflow(workflow)
            tool_ids = AI.data_from(workflow)[:tools]&.keys || []
            tool_ids.map { |id| registry[id.to_s] }.compact
          end

          # Clear registry (for testing)
          def reset!
            @registry = {}
          end

          private

          def tool_name(tool_class)
            if tool_class.respond_to?(:tool_def) && tool_class.tool_def
              tool_class.tool_def.id
            else
              tool_class.name&.demodulize&.underscore || "unknown"
            end
          end
        end
      end
    end
  end
end
```

## Usage

### From YAML

```yaml
tools:
  lookup_order:
    description: "Look up order by ID"
    parameters:
      - name: order_id
        type: string
        required: true
    service: OrderService
    method: find
```

Parser automatically registers:

```ruby
# In AI extension after_parse hook
tool_defs.each { |td| ToolRegistry.register_from_def(td) }
```

### From Ruby

```ruby
class LookupOrder < RubyLLM::Tool
  description "Look up order by ID"
  param :order_id, type: :string, required: true

  def execute(order_id:)
    OrderService.find(order_id)
  end
end

DurableWorkflow::Extensions::AI::ToolRegistry.register(LookupOrder)
```

### Retrieve

```ruby
tool_class = ToolRegistry["lookup_order"]
tool = tool_class.new
result = tool.call(order_id: "123")
```

## Tests

### `test/unit/extensions/ai/tool_registry_test.rb`

```ruby
class ToolRegistryTest < Minitest::Test
  def setup
    ToolRegistry.reset!
  end

  def test_to_ruby_llm_tool_creates_subclass
    tool_def = ToolDef.new(
      id: "test_tool",
      description: "A test tool",
      parameters: [],
      service: "TestService",
      method_name: "call"
    )

    tool_class = tool_def.to_ruby_llm_tool
    assert tool_class < RubyLLM::Tool
  end

  def test_generated_tool_has_description
    tool_def = ToolDef.new(
      id: "test_tool",
      description: "My description",
      parameters: [],
      service: "TestService",
      method_name: "call"
    )

    tool_class = tool_def.to_ruby_llm_tool
    assert_equal "My description", tool_class.new.description
  end

  def test_register_stores_tool
    tool_def = ToolDef.new(...)
    ToolRegistry.register_from_def(tool_def)

    assert_equal tool_def.to_ruby_llm_tool, ToolRegistry["test_tool"]
  end

  def test_for_workflow_returns_workflow_tools
    # Setup workflow with tools in extensions[:ai][:tools]
    workflow = create_workflow_with_tools(["tool_a", "tool_b"])

    ToolRegistry.register_from_def(tool_a_def)
    ToolRegistry.register_from_def(tool_b_def)

    tools = ToolRegistry.for_workflow(workflow)
    assert_equal 2, tools.size
  end
end
```

## Acceptance Criteria

1. `ToolDef#to_ruby_llm_tool` creates valid RubyLLM::Tool subclass
2. Generated tool has correct description and parameters
3. Generated tool execute calls service method
4. `ToolRegistry.register` stores Ruby tool classes
5. `ToolRegistry.register_from_def` stores YAML-defined tools
6. `ToolRegistry[]` retrieves tool by name
7. `ToolRegistry.for_workflow` returns tools for specific workflow
