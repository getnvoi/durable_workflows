# 01-GEMSPEC: Gem Setup and Dependencies

## Goal

Complete the gemspec with proper metadata and dependencies. Set up the base module structure.

## Dependencies

None - this is the first step.

## Files to Create/Modify

### 1. `durable_workflow.gemspec`

```ruby
# frozen_string_literal: true

require_relative "lib/durable_workflow/version"

Gem::Specification.new do |spec|
  spec.name = "durable_workflow"
  spec.version = DurableWorkflow::VERSION
  spec.authors = ["Ben"]
  spec.email = ["ben@dee.mx"]

  spec.summary = "Durable workflow engine with YAML-defined steps and pluggable executors"
  spec.description = "A workflow engine supporting loops, parallel execution, approvals, halts, and extensible step types. Designed for durable, resumable execution with optional AI capabilities."
  spec.homepage = "https://github.com/your-org/durable_workflow"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github .circleci appveyor])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core dependencies
  spec.add_dependency "dry-types", "~> 1.7"
  spec.add_dependency "dry-struct", "~> 1.6"

  # Optional runtime dependencies (for specific features)
  # async - for parallel executor
  # redis - for Redis storage
  # ruby_llm - for AI extension
end
```

### 2. `Gemfile`

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Development
gem "rake", "~> 13.0"
gem "minitest", "~> 5.0"
gem "rubocop", "~> 1.21"

# Optional runtime (for testing all features)
gem "async", "~> 2.21"
gem "redis", "~> 5.0"
gem "ruby_llm", "~> 1.0"
```

### 3. `lib/durable_workflow/version.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  VERSION = "0.1.0"
end
```

### 4. `lib/durable_workflow.rb`

```ruby
# frozen_string_literal: true

require "securerandom"
require "time"
require_relative "durable_workflow/version"

module DurableWorkflow
  class Error < StandardError; end
  class ConfigError < Error; end
  class ValidationError < Error; end
  class ExecutionError < Error; end

  class << self
    attr_accessor :config

    def configure
      self.config ||= Config.new
      yield config if block_given?
      config
    end

    def load(source)
      wf = Core::Parser.parse(source)
      Core::Validator.validate!(wf)
      wf
    end

    def registry
      @registry ||= {}
    end

    def register(workflow)
      registry[workflow.id] = workflow
    end

    def log(level, msg, **data)
      config&.logger&.send(level, "[DurableWorkflow] #{msg} #{data}")
    end
  end

  Config = Struct.new(:store, :service_resolver, :logger, keyword_init: true)
end

# Core (always loaded)
require_relative "durable_workflow/utils"
require_relative "durable_workflow/core/types"
require_relative "durable_workflow/core/parser"
require_relative "durable_workflow/core/validator"
require_relative "durable_workflow/core/resolver"
require_relative "durable_workflow/core/condition"
require_relative "durable_workflow/core/executors/registry"
require_relative "durable_workflow/core/executors/base"

# Load all core executors
Dir[File.join(__dir__, "durable_workflow/core/executors/*.rb")].each { |f| require f }

require_relative "durable_workflow/core/engine"

# Storage (no default - must be configured)
require_relative "durable_workflow/storage/store"

# Runners
require_relative "durable_workflow/runners/sync"
require_relative "durable_workflow/runners/async"
require_relative "durable_workflow/runners/stream"
require_relative "durable_workflow/runners/adapters/inline"
```

### 5. `lib/durable_workflow/utils.rb`

```ruby
# frozen_string_literal: true

module DurableWorkflow
  module Utils
    module_function

    def deep_symbolize(obj)
      case obj
      when Hash
        obj.transform_keys(&:to_sym).transform_values { deep_symbolize(_1) }
      when Array
        obj.map { deep_symbolize(_1) }
      else
        obj
      end
    end
  end
end
```

## Acceptance Criteria

1. `bundle install` succeeds
2. `bundle exec ruby -e "require 'durable_workflow'; puts DurableWorkflow::VERSION"` outputs `0.1.0`
3. No reference to AI types in base module
4. Module namespace is `DurableWorkflow` (not `Workflow`)

## Notes

- The entry point is `lib/durable_workflow.rb` (standard gem layout)
- Core dependencies are dry-types and dry-struct only
- Optional deps (async, redis, ruby_llm) are development dependencies for testing
- Config struct removed `extensions` field - extensions register themselves
