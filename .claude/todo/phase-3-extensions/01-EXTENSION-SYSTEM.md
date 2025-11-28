# 01-EXTENSION-SYSTEM: Plugin Architecture

## Goal

Define the extension system that allows plugins (like AI) to register:

1. New step types (executors)
2. New config classes
3. Parser hooks for workflow-level data
4. Custom workflow definition attributes via `extensions` hash

## Dependencies

- Phase 1 complete
- Phase 2 complete

## Design Principles

1. **No Monkey Patching** - Extensions use hooks, not `alias_method`
2. **Registry Pattern** - Step types and configs register themselves
3. **Fail Fast** - Unknown step types fail at parse/validation time
4. **Isolation** - Extensions can't break core functionality

## How Extensions Work

### 1. Executor Registration

Extensions register their executors in the global registry:

```ruby
# In extension code
DurableWorkflow::Core::Executors::Registry.register("agent", AgentExecutor)
```

### 2. Config Registration

Extensions register their config classes:

```ruby
# In extension code
DurableWorkflow::Core.register_config("agent", AgentConfig)
```

### 3. Parser Hooks

Extensions inject parsing logic:

```ruby
# Before parse - modify raw YAML
DurableWorkflow::Core::Parser.before_parse do |yaml|
  # Transform raw YAML before parsing
  yaml
end

# After parse - modify WorkflowDef
DurableWorkflow::Core::Parser.after_parse do |workflow|
  # Parse extension-specific data and store in extensions hash
  workflow.with(extensions: workflow.extensions.merge(my_data: parsed))
end

# Config transformer - modify config for specific type
DurableWorkflow::Core::Parser.transform_config("agent") do |raw_config|
  # Transform raw config before building typed config
  raw_config
end
```

### 4. Extension Data in WorkflowDef

Extensions store their data in `workflow.extensions`:

```ruby
workflow.extensions[:ai]  # => { agents: {...}, tools: {...} }
```

## Files to Create

### 1. `lib/durable_workflow/extensions/base.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Extensions
    # Base class for extensions
    # Extensions inherit from this and call register! to set up
    class Base
      class << self
        # Extension name (used as key in workflow.extensions)
        def extension_name
          @extension_name ||= name.split("::").last.downcase
        end

        def extension_name=(name)
          @extension_name = name
        end

        # Register all components of the extension
        def register!
          register_configs
          register_executors
          register_parser_hooks
        end

        # Override in subclass to register config classes
        def register_configs
          # Example:
          # DurableWorkflow::Core.register_config("agent", AgentConfig)
        end

        # Override in subclass to register executors
        def register_executors
          # Example:
          # DurableWorkflow::Core::Executors::Registry.register("agent", AgentExecutor)
        end

        # Override in subclass to register parser hooks
        def register_parser_hooks
          # Example:
          # DurableWorkflow::Core::Parser.after_parse { |wf| ... }
        end

        # Helper to get extension data from workflow
        def data_from(workflow)
          workflow.extensions[extension_name.to_sym] || {}
        end

        # Helper to store extension data in workflow
        def store_in(workflow, data)
          workflow.with(extensions: workflow.extensions.merge(extension_name.to_sym => data))
        end
      end
    end

    # Registry of loaded extensions
    @extensions = {}

    class << self
      attr_reader :extensions

      def register(name, extension_class)
        @extensions[name.to_sym] = extension_class
        extension_class.register!
      end

      def [](name)
        @extensions[name.to_sym]
      end

      def loaded?(name)
        @extensions.key?(name.to_sym)
      end
    end
  end
end
```

### 2. Update `lib/durable_workflow/core/types/configs.rb`

Ensure the registry supports extension registration:

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Core
    # ... existing config classes ...

    # Mutable registry - extensions add their configs here
    CONFIG_REGISTRY = {
      "start" => StartConfig,
      "end" => EndConfig,
      "call" => CallConfig,
      "assign" => AssignConfig,
      "router" => RouterConfig,
      "loop" => LoopConfig,
      "halt" => HaltConfig,
      "approval" => ApprovalConfig,
      "transform" => TransformConfig,
      "parallel" => ParallelConfig,
      "workflow" => WorkflowConfig
    }

    # Allow extensions to register config classes
    def self.register_config(type, klass)
      CONFIG_REGISTRY[type.to_s] = klass
    end

    # Check if a config type is registered
    def self.config_registered?(type)
      CONFIG_REGISTRY.key?(type.to_s)
    end
  end
end
```

### 3. Example Extension Structure

Here's how an extension should be structured:

```ruby
# lib/durable_workflow/extensions/my_extension/my_extension.rb

module DurableWorkflow
  module Extensions
    module MyExtension
      class Extension < Base
        self.extension_name = "my_extension"

        def self.register_configs
          Core.register_config("my_step", MyStepConfig)
        end

        def self.register_executors
          Core::Executors::Registry.register("my_step", MyStepExecutor)
        end

        def self.register_parser_hooks
          Core::Parser.after_parse do |workflow|
            # Parse extension-specific YAML keys
            raw = workflow.to_h
            my_data = parse_my_data(raw)
            store_in(workflow, my_data)
          end
        end

        def self.parse_my_data(raw)
          # Parse extension-specific data from raw workflow hash
          {}
        end
      end

      # Config class
      class MyStepConfig < Core::StepConfig
        attribute :some_field, Types::Strict::String
      end

      # Executor class
      class MyStepExecutor < Core::Executors::Base
        def call(state)
          # Do work
          continue(state)
        end
      end
    end
  end
end

# Auto-register when required
DurableWorkflow::Extensions.register(:my_extension, DurableWorkflow::Extensions::MyExtension::Extension)
```

## Extension Loading Pattern

```ruby
# User code - load core
require "durable_workflow"

# Load extension (auto-registers)
require "durable_workflow/extensions/ai"

# Now AI step types are available
wf = DurableWorkflow.load("workflow_with_agents.yml")
```

## Validation with Extensions

The validator automatically checks step types against the registry:

```ruby
# In validator.rb
def check_step_types!
  @workflow.steps.each do |step|
    unless Executors::Registry.registered?(step.type)
      @errors << "Unknown step type '#{step.type}' in step '#{step.id}'"
    end
  end
end
```

If an extension isn't loaded, its step types will fail validation.

## Best Practices for Extensions

1. **Namespace your data** - Store in `extensions[:my_extension]`, not top-level
2. **Register early** - Call `register!` when the extension is required
3. **Validate your configs** - Use dry-types constraints
4. **Don't modify core types** - Extend, don't mutate
5. **Document YAML schema** - Users need to know what to write

## Acceptance Criteria

1. `Extensions.register(:name, ExtensionClass)` registers an extension
2. Extensions can add step types via `Registry.register`
3. Extensions can add configs via `Core.register_config`
4. Parser hooks run in order (before -> parse -> after)
5. Unknown step types fail validation if extension not loaded
6. `workflow.extensions[:name]` returns extension data
