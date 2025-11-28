# frozen_string_literal: true

require_relative 'lib/durable_workflow/version'

Gem::Specification.new do |spec|
  spec.name = 'durable_workflow'
  spec.version = DurableWorkflow::VERSION
  spec.authors = ['Ben']
  spec.email = ['ben@dee.mx']

  spec.summary = 'Durable workflow engine with YAML-defined steps and pluggable executors'
  spec.description = 'A workflow engine supporting loops, parallel execution, approvals, halts, and extensible step types. Designed for durable, resumable execution with optional AI capabilities.'
  spec.homepage = 'https://github.com/your-org/durable_workflow'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github .circleci appveyor])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Core dependencies
  spec.add_dependency 'dry-types', '~> 1.7'
  spec.add_dependency 'dry-struct', '~> 1.6'
  spec.add_dependency 'json_schemer', '~> 2.0'
  spec.add_dependency 'async', '~> 2.21'

  # AI extension dependencies
  spec.add_dependency 'ruby_llm', '~> 1.0'
  spec.add_dependency 'mcp', '~> 0.1'
  spec.add_dependency 'faraday', '>= 2.0'
  spec.add_dependency 'rack', '>= 2.0'
end
