# 05-EXAMPLE-DATA-PIPELINE: ETL Data Processing

## ⚠️ STATUS: FUTURE/ASPIRATIONAL

**This document describes a FUTURE example that requires features not yet implemented:**

- Ruby expression evaluation in YAML - NOT SUPPORTED
- `DurableWorkflow.register_service()` - NOT IMPLEMENTED (use `Object.const_get`)
- `DurableWorkflow.subscribe(pattern:)` - NOT IMPLEMENTED
- `DurableWorkflow::Runners::Stream` - NOT IMPLEMENTED
- `runner.subscribe` - NOT IMPLEMENTED
- Parallel branches as named hash - NOT SUPPORTED (use array of step defs)

**The resolver only supports `$ref` substitution, NOT expression evaluation.**

**Do not attempt to run this example until these features are built or the example is rewritten.**

---

## Goal

Data processing pipeline demonstrating transforms, parallel execution, external MCP consumption, and streaming events.

## Why This Example Doesn't Work

The workflow.yml relies on:

```yaml
# These DO NOT WORK
set:
  job_id: "'JOB-' + Date.now().toString(36)"  # ❌ No JS/Ruby eval
  raw_data: "$csv_data.concat($api_data || [])"  # ❌ No method calls
  stats:
    extracted: "$raw_data.length"  # ❌ No method calls

# Parallel branches format is wrong
branches:
  csv_extract:    # ❌ Named hash not supported
    - id: ...
  api_extract:    # ❌ Should be array of steps
    - id: ...
```

## How To Make This Work

1. **Move ALL computation to services** - Merging arrays, counting, etc.
2. **Use array format for parallel branches**:

```yaml
branches:
  - id: extract_csv
    type: call
    service: CSVExtractor
    ...
  - id: extract_api
    type: call
    service: APIExtractor
    ...
```

3. **Use `Object.const_get` for services** - Global modules
4. **Use `Runners::Sync`** - The only working runner
5. **Skip event streaming** - Not implemented

---

## Example Files That Were Created (Broken)

The `examples/data_pipeline/` directory was created but has been **deleted** because it relied on non-existent features:

- `run.rb` - Used `register_service`, `Runners::Stream`, `runner.subscribe`
- `stream_monitor.rb` - Used `DurableWorkflow.subscribe(pattern:)`
- `workflow.yml` - Used Ruby expressions throughout

---

## Implementation Prerequisites

To run this example AS DESIGNED, implement:

1. Expression evaluation in resolver
2. `DurableWorkflow.register_service()` method
3. `DurableWorkflow.subscribe(pattern:)` for global event subscription
4. `Runners::Stream` with event callbacks
5. Named branch support in parallel step (or document array-only)

OR rewrite the example to work with current constraints.

---

## Minimal Working Alternative

Here's a simplified data pipeline that WOULD work:

```ruby
module DataPipeline
  def self.run_etl(source_file:, output_path:)
    # Extract
    records = CSV.read(source_file, headers: true).map(&:to_h)

    # Validate
    valid, invalid = records.partition { |r| r["email"]&.include?("@") }

    # Transform
    transformed = valid.map do |r|
      r.merge("domain" => r["email"]&.split("@")&.last)
    end

    # Load
    File.write("#{output_path}/records.json", JSON.pretty_generate(transformed))
    File.write("#{output_path}/errors.json", JSON.pretty_generate(invalid))

    {
      extracted: records.size,
      valid: valid.size,
      invalid: invalid.size,
      output_path: output_path
    }
  end
end
```

```yaml
steps:
  - id: start
    type: start
    next: process

  - id: process
    type: call
    service: DataPipeline
    method: run_etl
    input:
      source_file: "$input.source_file"
      output_path: "$input.output_path"
    output: result
    next: end

  - id: end
    type: end
    result:
      stats: "$result"
```

This delegates everything to the service, which is the correct pattern given current resolver limitations.
