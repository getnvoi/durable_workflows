# 02-EXAMPLES-SIMPLE: Single-File Example Scripts

## Goal

Simple, runnable Ruby scripts demonstrating core workflow features. Each is self-contained.

## Directory Structure

```
examples/
  hello_workflow.rb          # Simplest possible workflow
  calculator.rb              # Routing + service calls
  item_processor.rb          # Service-based data processing
  approval_request.rb        # Halt and resume
  parallel_fetch.rb          # Concurrent execution
  service_integration.rb     # External service calls
```

---

## Key Constraints

**IMPORTANT**: The resolver only supports `$ref` substitution. There is NO Ruby expression evaluation.

- ✅ `$input.name` - reference substitution
- ✅ `$result.value` - nested reference
- ✅ `"Hello, $input.name!"` - string interpolation
- ❌ `$a + $b` - no arithmetic
- ❌ `$items.length` - no method calls
- ❌ `$total * 0.08` - no expressions

**For any computation, use a service via the `call` step.**

Other constraints:
- Services resolved via `Object.const_get(name)` - must be globally accessible Ruby constants
- `runner.run({ key: value })` - pass hash, not keyword args
- Router `field:` does NOT include `$` prefix (evaluator adds it internally)
- Call step uses `input:` not `args:`
- Parallel branches is an array of step definitions, not a named hash

---

## 1. `examples/hello_workflow.rb`

**Demonstrates:** Basic workflow structure, assign step, input/output, `$ref` substitution

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Hello Workflow - Simplest possible durable workflow
#
# Run: ruby examples/hello_workflow.rb
# Requires: Redis running on localhost:6379

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"

# Configure storage
DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

# Define workflow inline
workflow = DurableWorkflow::Core::Parser.parse(<<~YAML)
  id: hello_world
  name: Hello World
  version: "1.0"

  inputs:
    name:
      type: string
      required: true

  steps:
    - id: start
      type: start
      next: greet

    - id: greet
      type: assign
      set:
        greeting: "Hello, $input.name!"
        timestamp: "$now"
      next: end

    - id: end
      type: end
      result:
        message: "$greeting"
        generated_at: "$timestamp"
YAML

# Run it (pass input as a hash, not kwargs)
runner = DurableWorkflow::Runners::Sync.new(workflow)
result = runner.run({ name: "World" })

puts "Status: #{result.status}"
puts "Output: #{result.output}"
# => Status: completed
# => Output: {:message=>"Hello, World!", :generated_at=>2024-...}
```

---

## 2. `examples/calculator.rb`

**Demonstrates:** Router step, conditional branching, service calls for computation

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Calculator Workflow - Routing based on input
#
# Run: ruby examples/calculator.rb
# Requires: Redis running on localhost:6379

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"

# Calculator service - computation happens in Ruby code
# Must be globally accessible (module at top level)
module Calculator
  def self.add(a:, b:)
    { result: a + b, operation: "addition" }
  end

  def self.subtract(a:, b:)
    { result: a - b, operation: "subtraction" }
  end

  def self.multiply(a:, b:)
    { result: a * b, operation: "multiplication" }
  end

  def self.divide(a:, b:)
    { result: a.to_f / b, operation: "division" }
  end
end

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

workflow = DurableWorkflow::Core::Parser.parse(<<~YAML)
  id: calculator
  name: Calculator
  version: "1.0"

  inputs:
    operation:
      type: string
      required: true
    a:
      type: number
      required: true
    b:
      type: number
      required: true

  steps:
    - id: start
      type: start
      next: route

    - id: route
      type: router
      routes:
        - when:
            field: input.operation
            op: eq
            value: "add"
          then: add
        - when:
            field: input.operation
            op: eq
            value: "subtract"
          then: subtract
        - when:
            field: input.operation
            op: eq
            value: "multiply"
          then: multiply
        - when:
            field: input.operation
            op: eq
            value: "divide"
          then: divide
      default: error

    - id: add
      type: call
      service: Calculator
      method: add
      input:
        a: "$input.a"
        b: "$input.b"
      output: calc_result
      next: end

    - id: subtract
      type: call
      service: Calculator
      method: subtract
      input:
        a: "$input.a"
        b: "$input.b"
      output: calc_result
      next: end

    - id: multiply
      type: call
      service: Calculator
      method: multiply
      input:
        a: "$input.a"
        b: "$input.b"
      output: calc_result
      next: end

    - id: divide
      type: call
      service: Calculator
      method: divide
      input:
        a: "$input.a"
        b: "$input.b"
      output: calc_result
      next: end

    - id: error
      type: assign
      set:
        calc_result:
          error: "Unknown operation"
      next: end

    - id: end
      type: end
      result:
        result: "$calc_result.result"
        operation: "$calc_result.operation"
        error: "$calc_result.error"
YAML

runner = DurableWorkflow::Runners::Sync.new(workflow)

# Test all operations
[
  { operation: "add", a: 10, b: 5 },
  { operation: "subtract", a: 10, b: 5 },
  { operation: "multiply", a: 10, b: 5 },
  { operation: "divide", a: 10, b: 5 }
].each do |input|
  result = runner.run(input)
  puts "#{input[:a]} #{input[:operation]} #{input[:b]} = #{result.output[:result]}"
end
# => 10 add 5 = 15
# => 10 subtract 5 = 5
# => 10 multiply 5 = 50
# => 10 divide 5 = 2.0
```

---

## 3. `examples/item_processor.rb`

**Demonstrates:** Service-based data processing

Note: The workflow engine has a `loop` step type, but since we can't do arithmetic in YAML,
we delegate all processing to a service and keep the workflow simple.

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Item Processor - Process collection via service
#
# Run: ruby examples/item_processor.rb
# Requires: Redis running on localhost:6379

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"

# Service for item processing (must be globally accessible)
module ItemProcessor
  def self.process(items:)
    total = 0
    processed = []

    items.each do |item|
      line_total = item[:quantity] * item[:price]
      total += line_total
      processed << { name: item[:name], subtotal: line_total }
    end

    {
      count: items.size,
      total: total,
      average: items.empty? ? 0 : total.to_f / items.size,
      items: processed
    }
  end
end

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

workflow = DurableWorkflow::Core::Parser.parse(<<~YAML)
  id: item_processor
  name: Item Processor
  version: "1.0"

  inputs:
    items:
      type: array
      required: true

  steps:
    - id: start
      type: start
      next: process

    - id: process
      type: call
      service: ItemProcessor
      method: process
      input:
        items: "$input.items"
      output: result
      next: end

    - id: end
      type: end
      result:
        item_count: "$result.count"
        total: "$result.total"
        average: "$result.average"
        items: "$result.items"
YAML

runner = DurableWorkflow::Runners::Sync.new(workflow)

result = runner.run({
  items: [
    { name: "Widget", quantity: 3, price: 10.00 },
    { name: "Gadget", quantity: 2, price: 25.00 },
    { name: "Gizmo", quantity: 5, price: 5.00 }
  ]
})

puts "Processed #{result.output[:item_count]} items"
puts "Total: $#{result.output[:total]}"
puts "Average: $#{result.output[:average].round(2)}"
puts "Breakdown:"
result.output[:items].each do |item|
  puts "  #{item[:name]}: $#{item[:subtotal]}"
end
# => Processed 3 items
# => Total: $105.0
# => Average: $35.0
# => Breakdown:
# =>   Widget: $30.0
# =>   Gadget: $50.0
# =>   Gizmo: $25.0
```

---

## 4. `examples/approval_request.rb`

**Demonstrates:** Approval step, halt and resume, human-in-the-loop

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Approval Request - Workflow that halts for human input
#
# Run: ruby examples/approval_request.rb
# Requires: Redis running on localhost:6379

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

workflow = DurableWorkflow::Core::Parser.parse(<<~YAML)
  id: expense_approval
  name: Expense Approval
  version: "1.0"

  inputs:
    requester:
      type: string
      required: true
    amount:
      type: number
      required: true
    description:
      type: string
      required: true

  steps:
    - id: start
      type: start
      next: check_amount

    - id: check_amount
      type: router
      routes:
        - when:
            field: input.amount
            op: gt
            value: 100
          then: require_approval
      default: auto_approve

    - id: auto_approve
      type: assign
      set:
        approved: true
        approved_by: system
        reason: "Amount under threshold"
      next: end

    - id: require_approval
      type: approval
      prompt: "Please approve expense request"
      context:
        requester: "$input.requester"
        amount: "$input.amount"
        description: "$input.description"
      on_reject: rejected
      next: approved

    - id: approved
      type: assign
      set:
        approved: true
        approved_by: manager
      next: end

    - id: rejected
      type: assign
      set:
        approved: false
        approved_by: manager
        reason: "Request rejected"
      next: end

    - id: end
      type: end
      result:
        approved: "$approved"
        approved_by: "$approved_by"
        reason: "$reason"
YAML

runner = DurableWorkflow::Runners::Sync.new(workflow)

# Small expense - auto-approved
result = runner.run({ requester: "Alice", amount: 50, description: "Office supplies" })
puts "Small expense: #{result.output}"
# => Small expense: {:approved=>true, :approved_by=>"system", :reason=>"Amount under threshold"}

# Large expense - requires approval (halts)
result = runner.run({ requester: "Bob", amount: 500, description: "Conference ticket" })
puts "\nLarge expense halted: #{result.status}"
puts "Halt data: #{result.halt&.data}"
# Workflow halts here - would resume with approved: true/false
```

---

## 5. `examples/parallel_fetch.rb`

**Demonstrates:** Parallel step, concurrent execution

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Parallel Fetch - Execute multiple operations concurrently
#
# Run: ruby examples/parallel_fetch.rb
# Requires: Redis running on localhost:6379, async gem

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

# Mock services (must be globally accessible constants)
module UserService
  def self.get_profile(user_id:)
    sleep(0.1) # Simulate latency
    { id: user_id, name: "User #{user_id}", email: "user#{user_id}@example.com" }
  end
end

module OrderService
  def self.get_recent(user_id:, limit:)
    sleep(0.1)
    limit.times.map { |i| { id: "ORD-#{i}", amount: rand(10..100) } }
  end
end

module NotificationService
  def self.get_unread(user_id:)
    sleep(0.1)
    rand(0..5).times.map { |i| { id: "NOTIF-#{i}", message: "Notification #{i}" } }
  end
end

workflow = DurableWorkflow::Core::Parser.parse(<<~YAML)
  id: dashboard_data
  name: Dashboard Data Fetch
  version: "1.0"

  inputs:
    user_id:
      type: string
      required: true

  steps:
    - id: start
      type: start
      next: fetch_all

    - id: fetch_all
      type: parallel
      branches:
        - id: get_profile
          type: call
          service: UserService
          method: get_profile
          input:
            user_id: "$input.user_id"
          output: profile

        - id: get_orders
          type: call
          service: OrderService
          method: get_recent
          input:
            user_id: "$input.user_id"
            limit: 5
          output: orders

        - id: get_notifications
          type: call
          service: NotificationService
          method: get_unread
          input:
            user_id: "$input.user_id"
          output: notifications
      next: end

    - id: end
      type: end
      result:
        user: "$profile"
        recent_orders: "$orders"
        notifications: "$notifications"
YAML

runner = DurableWorkflow::Runners::Sync.new(workflow)

start_time = Time.now
result = runner.run({ user_id: "USER-123" })
elapsed = Time.now - start_time

puts "Fetched dashboard data in #{elapsed.round(2)}s (parallel, not sequential 0.3s)"
puts "User: #{result.output[:user][:name]}"
puts "Orders: #{result.output[:recent_orders].size}"
puts "Notifications: #{result.output[:notifications].size}"
```

---

## 6. `examples/service_integration.rb`

**Demonstrates:** Call step, service resolution via Object.const_get, routing

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Service Integration - Calling external services from workflow
#
# Run: ruby examples/service_integration.rb
# Requires: Redis running on localhost:6379

require "bundler/setup"
require "securerandom"
require "durable_workflow"
require "durable_workflow/storage/redis"

# Inventory service (must be globally accessible constant)
module InventoryService
  STOCK = {
    "PROD-001" => 50,
    "PROD-002" => 0,
    "PROD-003" => 10
  }

  def self.check_availability(product_id:, quantity:)
    available = STOCK.fetch(product_id, 0)
    {
      product_id: product_id,
      requested: quantity,
      available: available,
      in_stock: available >= quantity
    }
  end

  def self.reserve(product_id:, quantity:)
    current = STOCK.fetch(product_id, 0)
    raise "Insufficient stock" if current < quantity

    STOCK[product_id] = current - quantity
    {
      reservation_id: "RES-#{SecureRandom.hex(4)}",
      product_id: product_id,
      quantity: quantity,
      remaining: STOCK[product_id]
    }
  end
end

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

workflow = DurableWorkflow::Core::Parser.parse(<<~YAML)
  id: inventory_check
  name: Inventory Check and Reserve
  version: "1.0"

  inputs:
    product_id:
      type: string
      required: true
    quantity:
      type: integer
      required: true

  steps:
    - id: start
      type: start
      next: check

    - id: check
      type: call
      service: InventoryService
      method: check_availability
      input:
        product_id: "$input.product_id"
        quantity: "$input.quantity"
      output: availability
      next: decide

    - id: decide
      type: router
      routes:
        - when:
            field: availability.in_stock
            op: eq
            value: true
          then: reserve
      default: out_of_stock

    - id: reserve
      type: call
      service: InventoryService
      method: reserve
      input:
        product_id: "$input.product_id"
        quantity: "$input.quantity"
      output: reservation
      next: success

    - id: success
      type: assign
      set:
        status: reserved
      next: end

    - id: out_of_stock
      type: assign
      set:
        status: out_of_stock
        error: "Insufficient stock available"
      next: end

    - id: end
      type: end
      result:
        status: "$status"
        availability: "$availability"
        reservation: "$reservation"
        error: "$error"
YAML

runner = DurableWorkflow::Runners::Sync.new(workflow)

# Available product
result = runner.run({ product_id: "PROD-001", quantity: 5 })
puts "PROD-001 (qty 5): #{result.output[:status]}"
puts "  Reservation: #{result.output[:reservation][:reservation_id]}" if result.output[:reservation]

# Out of stock
result = runner.run({ product_id: "PROD-002", quantity: 1 })
puts "\nPROD-002 (qty 1): #{result.output[:status]}"
puts "  Error: #{result.output[:error]}"

# Partial availability
result = runner.run({ product_id: "PROD-003", quantity: 20 })
puts "\nPROD-003 (qty 20): #{result.output[:status]}"
puts "  Error: #{result.output[:error]}"
```

---

## Acceptance Criteria

1. Each script is self-contained and runnable
2. Each demonstrates a single core concept
3. Output shows expected results
4. Comments explain what's being demonstrated
5. Uses realistic (not toy) examples
6. All examples pass when run with `ruby examples/<name>.rb`
