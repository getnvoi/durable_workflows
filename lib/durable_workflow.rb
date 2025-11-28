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
require_relative "durable_workflow/core/schema_validator"
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

# Extensions (base only - specific extensions loaded separately)
require_relative "durable_workflow/extensions/base"
