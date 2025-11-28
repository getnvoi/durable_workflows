# 02-EXAMPLES: Example Workflows

## Goal

Provide complete, working example workflows demonstrating all features of the durable_workflow gem.

## Dependencies

- Phase 1 complete
- Phase 2 complete
- Phase 3 complete

## Directory Structure

```
examples/
├── basic/
│   ├── hello_world.yml
│   ├── calculator.yml
│   └── run_basic.rb
├── routing/
│   ├── conditional_flow.yml
│   ├── multi_branch.yml
│   └── run_routing.rb
├── loops/
│   ├── process_items.yml
│   ├── aggregation.yml
│   └── run_loops.rb
├── halts/
│   ├── human_input.yml
│   ├── approval_flow.yml
│   └── run_halts.rb
├── parallel/
│   ├── concurrent_tasks.yml
│   ├── fan_out_fan_in.yml
│   └── run_parallel.rb
├── services/
│   ├── external_api.yml
│   ├── service_chain.yml
│   ├── services.rb
│   └── run_services.rb
├── subworkflows/
│   ├── parent.yml
│   ├── child.yml
│   └── run_subworkflows.rb
├── streaming/
│   ├── streamed_workflow.yml
│   └── run_streaming.rb
├── ai/ (requires AI extension)
│   ├── chatbot.yml
│   ├── multi_agent.yml
│   └── run_ai.rb
└── complete/
    ├── order_processing.yml
    ├── document_review.yml
    └── run_complete.rb
```

## Example Files

### 1. `examples/basic/hello_world.yml`

```yaml
# Simplest possible workflow
id: hello_world
name: Hello World
version: "1.0"

input_schema:
  type: object
  properties:
    name:
      type: string
  required:
    - name

steps:
  - id: start
    type: start
    next: greet

  - id: greet
    type: assign
    config:
      assignments:
        greeting: "'Hello, ' + $.input.name + '!'"
    next: done

  - id: done
    type: end
```

### 2. `examples/basic/calculator.yml`

```yaml
# Simple arithmetic workflow
id: calculator
name: Calculator
version: "1.0"

input_schema:
  type: object
  properties:
    operation:
      type: string
      enum: ["add", "subtract", "multiply", "divide"]
    a:
      type: number
    b:
      type: number
  required:
    - operation
    - a
    - b

steps:
  - id: start
    type: start
    next: route_operation

  - id: route_operation
    type: router
    config:
      routes:
        - condition: "$.input.operation == 'add'"
          next: add
        - condition: "$.input.operation == 'subtract'"
          next: subtract
        - condition: "$.input.operation == 'multiply'"
          next: multiply
        - condition: "$.input.operation == 'divide'"
          next: divide
      default: error

  - id: add
    type: assign
    config:
      assignments:
        result: "$.input.a + $.input.b"
    next: done

  - id: subtract
    type: assign
    config:
      assignments:
        result: "$.input.a - $.input.b"
    next: done

  - id: multiply
    type: assign
    config:
      assignments:
        result: "$.input.a * $.input.b"
    next: done

  - id: divide
    type: assign
    config:
      assignments:
        result: "$.input.a / $.input.b"
    next: done

  - id: error
    type: assign
    config:
      assignments:
        error: "'Unknown operation: ' + $.input.operation"
    next: done

  - id: done
    type: end
```

### 3. `examples/basic/run_basic.rb`

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"

# Configure with Redis
DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

# Load and run Hello World
puts "=== Hello World ==="
hello = DurableWorkflow.load("examples/basic/hello_world.yml")
runner = DurableWorkflow::Runners::Sync.new(hello)

result = runner.run(name: "Alice")
puts "Result: #{result.output[:greeting]}"
# => Hello, Alice!

# Load and run Calculator
puts "\n=== Calculator ==="
calc = DurableWorkflow.load("examples/basic/calculator.yml")
runner = DurableWorkflow::Runners::Sync.new(calc)

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
# => 10 divide 5 = 2
```

### 4. `examples/routing/conditional_flow.yml`

```yaml
# Workflow with conditional branching
id: conditional_flow
name: Conditional Flow
version: "1.0"

input_schema:
  type: object
  properties:
    score:
      type: integer
      minimum: 0
      maximum: 100

steps:
  - id: start
    type: start
    next: evaluate

  - id: evaluate
    type: router
    config:
      routes:
        - condition: "$.input.score >= 90"
          next: grade_a
        - condition: "$.input.score >= 80"
          next: grade_b
        - condition: "$.input.score >= 70"
          next: grade_c
        - condition: "$.input.score >= 60"
          next: grade_d
      default: grade_f

  - id: grade_a
    type: assign
    config:
      assignments:
        grade: "'A'"
        message: "'Excellent!'"
    next: done

  - id: grade_b
    type: assign
    config:
      assignments:
        grade: "'B'"
        message: "'Good job!'"
    next: done

  - id: grade_c
    type: assign
    config:
      assignments:
        grade: "'C'"
        message: "'Satisfactory'"
    next: done

  - id: grade_d
    type: assign
    config:
      assignments:
        grade: "'D'"
        message: "'Needs improvement'"
    next: done

  - id: grade_f
    type: assign
    config:
      assignments:
        grade: "'F'"
        message: "'Please try again'"
    next: done

  - id: done
    type: end
```

### 5. `examples/routing/multi_branch.yml`

```yaml
# Complex routing with multiple conditions
id: multi_branch
name: Multi Branch Decision
version: "1.0"

input_schema:
  type: object
  properties:
    user_type:
      type: string
    subscription:
      type: string
    amount:
      type: number

steps:
  - id: start
    type: start
    next: check_user

  - id: check_user
    type: router
    config:
      routes:
        - condition: "$.input.user_type == 'admin'"
          next: admin_flow
        - condition: "$.input.user_type == 'premium'"
          next: premium_flow
      default: standard_flow

  - id: admin_flow
    type: assign
    config:
      assignments:
        discount: 1.0
        access_level: "'full'"
    next: calculate_final

  - id: premium_flow
    type: router
    config:
      routes:
        - condition: "$.input.subscription == 'annual'"
          next: premium_annual
        - condition: "$.input.subscription == 'monthly'"
          next: premium_monthly
      default: premium_basic

  - id: premium_annual
    type: assign
    config:
      assignments:
        discount: 0.3
        access_level: "'premium'"
    next: calculate_final

  - id: premium_monthly
    type: assign
    config:
      assignments:
        discount: 0.15
        access_level: "'premium'"
    next: calculate_final

  - id: premium_basic
    type: assign
    config:
      assignments:
        discount: 0.1
        access_level: "'premium'"
    next: calculate_final

  - id: standard_flow
    type: assign
    config:
      assignments:
        discount: 0
        access_level: "'basic'"
    next: calculate_final

  - id: calculate_final
    type: assign
    config:
      assignments:
        final_amount: "$.input.amount * (1 - $.ctx.discount)"
    next: done

  - id: done
    type: end
```

### 6. `examples/loops/process_items.yml`

```yaml
# Process a collection of items
id: process_items
name: Process Items
version: "1.0"

input_schema:
  type: object
  properties:
    items:
      type: array
      items:
        type: object
        properties:
          name:
            type: string
          quantity:
            type: integer
          price:
            type: number

steps:
  - id: start
    type: start
    next: init

  - id: init
    type: assign
    config:
      assignments:
        total: 0
        processed_items: "[]"
    next: loop_items

  - id: loop_items
    type: loop
    config:
      collection: "$.input.items"
      item_var: item
      body:
        - id: calculate_item
          type: assign
          config:
            assignments:
              item_total: "$.ctx.item.quantity * $.ctx.item.price"
              total: "$.ctx.total + $.ctx.item_total"
              processed_items: "$.ctx.processed_items.concat([{ name: $.ctx.item.name, subtotal: $.ctx.item_total }])"
    next: summarize

  - id: summarize
    type: assign
    config:
      assignments:
        summary:
          item_count: "$.ctx.processed_items.length"
          total: "$.ctx.total"
          items: "$.ctx.processed_items"
    next: done

  - id: done
    type: end
```

### 7. `examples/loops/aggregation.yml`

```yaml
# Aggregate data from multiple sources
id: aggregation
name: Data Aggregation
version: "1.0"

input_schema:
  type: object
  properties:
    numbers:
      type: array
      items:
        type: number

steps:
  - id: start
    type: start
    next: init_stats

  - id: init_stats
    type: assign
    config:
      assignments:
        sum: 0
        min: "$.input.numbers[0]"
        max: "$.input.numbers[0]"
        count: 0
    next: aggregate

  - id: aggregate
    type: loop
    config:
      collection: "$.input.numbers"
      item_var: num
      body:
        - id: update_stats
          type: assign
          config:
            assignments:
              sum: "$.ctx.sum + $.ctx.num"
              count: "$.ctx.count + 1"
              min: "$.ctx.num < $.ctx.min ? $.ctx.num : $.ctx.min"
              max: "$.ctx.num > $.ctx.max ? $.ctx.num : $.ctx.max"
    next: calculate_average

  - id: calculate_average
    type: assign
    config:
      assignments:
        average: "$.ctx.sum / $.ctx.count"
        statistics:
          sum: "$.ctx.sum"
          min: "$.ctx.min"
          max: "$.ctx.max"
          count: "$.ctx.count"
          average: "$.ctx.average"
    next: done

  - id: done
    type: end
```

### 8. `examples/halts/human_input.yml`

```yaml
# Workflow that pauses for human input
id: human_input
name: Human Input Required
version: "1.0"

input_schema:
  type: object
  properties:
    document_id:
      type: string

steps:
  - id: start
    type: start
    next: fetch_document

  - id: fetch_document
    type: assign
    config:
      assignments:
        document:
          id: "$.input.document_id"
          title: "'Sample Document'"
          content: "'This is the document content...'"
    next: request_review

  - id: request_review
    type: halt
    config:
      data:
        message: "'Please review the document'"
        document: "$.ctx.document"
    next: process_review

  - id: process_review
    type: assign
    config:
      assignments:
        review_notes: "$.ctx._response.notes"
        reviewer: "$.ctx._response.reviewer"
    next: check_approval

  - id: check_approval
    type: router
    config:
      routes:
        - condition: "$.ctx._response.approved == true"
          next: approved
      default: rejected

  - id: approved
    type: assign
    config:
      assignments:
        status: "'approved'"
        result:
          status: "'approved'"
          document: "$.ctx.document"
          reviewer: "$.ctx.reviewer"
          notes: "$.ctx.review_notes"
    next: done

  - id: rejected
    type: assign
    config:
      assignments:
        status: "'rejected'"
        result:
          status: "'rejected'"
          document: "$.ctx.document"
          reviewer: "$.ctx.reviewer"
          notes: "$.ctx.review_notes"
    next: done

  - id: done
    type: end
```

### 9. `examples/halts/approval_flow.yml`

```yaml
# Multi-level approval workflow
id: approval_flow
name: Multi-Level Approval
version: "1.0"

input_schema:
  type: object
  properties:
    request_type:
      type: string
    amount:
      type: number
    requester:
      type: string

steps:
  - id: start
    type: start
    next: check_amount

  - id: check_amount
    type: router
    config:
      routes:
        - condition: "$.input.amount > 10000"
          next: executive_approval
        - condition: "$.input.amount > 1000"
          next: manager_approval
      default: auto_approve

  - id: manager_approval
    type: approval
    config:
      prompt: "'Manager approval required for $' + $.input.amount"
      data:
        request_type: "$.input.request_type"
        amount: "$.input.amount"
        requester: "$.input.requester"
        level: "'manager'"
      approved_next: approved
      rejected_next: rejected

  - id: executive_approval
    type: approval
    config:
      prompt: "'Executive approval required for $' + $.input.amount"
      data:
        request_type: "$.input.request_type"
        amount: "$.input.amount"
        requester: "$.input.requester"
        level: "'executive'"
      approved_next: approved
      rejected_next: rejected

  - id: auto_approve
    type: assign
    config:
      assignments:
        approval_level: "'auto'"
        approved_by: "'system'"
    next: approved

  - id: approved
    type: assign
    config:
      assignments:
        result:
          status: "'approved'"
          amount: "$.input.amount"
          approved_by: "$.ctx.approved_by || 'approver'"
          timestamp: "new Date().toISOString()"
    next: done

  - id: rejected
    type: assign
    config:
      assignments:
        result:
          status: "'rejected'"
          amount: "$.input.amount"
          rejected_by: "'approver'"
          reason: "$.ctx._response.reason || 'No reason provided'"
    next: done

  - id: done
    type: end
```

### 10. `examples/halts/run_halts.rb`

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

# Human Input Example
puts "=== Human Input Workflow ==="
workflow = DurableWorkflow.load("examples/halts/human_input.yml")
runner = DurableWorkflow::Runners::Sync.new(workflow)

# Start workflow - will halt for review
result = runner.run(document_id: "DOC-123")
puts "Status: #{result.status}"
puts "Halt data: #{result.halt.data}"

# Simulate human providing review
result = runner.resume(result.execution_id, response: {
  approved: true,
  reviewer: "John Smith",
  notes: "Looks good!"
})

puts "Final status: #{result.status}"
puts "Result: #{result.output[:result]}"

# Approval Flow Example
puts "\n=== Approval Flow ==="
approval_wf = DurableWorkflow.load("examples/halts/approval_flow.yml")
runner = DurableWorkflow::Runners::Sync.new(approval_wf)

# Use run_until_complete with block to handle approvals
result = runner.run_until_complete(
  request_type: "expense",
  amount: 5000,
  requester: "Alice"
) do |halt|
  puts "Approval needed: #{halt.prompt}"
  puts "Data: #{halt.data}"

  # Simulate approval
  { approved: true }
end

puts "Final result: #{result.output[:result]}"
```

### 11. `examples/parallel/concurrent_tasks.yml`

```yaml
# Execute multiple tasks in parallel
id: concurrent_tasks
name: Concurrent Tasks
version: "1.0"

input_schema:
  type: object
  properties:
    user_id:
      type: string

steps:
  - id: start
    type: start
    next: fetch_data

  - id: fetch_data
    type: parallel
    config:
      branches:
        profile:
          - id: get_profile
            type: call
            config:
              service: user_service
              method: get_profile
              args:
                user_id: "$.input.user_id"
              result_key: profile

        orders:
          - id: get_orders
            type: call
            config:
              service: order_service
              method: get_recent
              args:
                user_id: "$.input.user_id"
                limit: 10
              result_key: orders

        notifications:
          - id: get_notifications
            type: call
            config:
              service: notification_service
              method: unread
              args:
                user_id: "$.input.user_id"
              result_key: notifications

      merge_strategy: all
    next: combine

  - id: combine
    type: assign
    config:
      assignments:
        dashboard:
          user: "$.ctx.profile"
          recent_orders: "$.ctx.orders"
          unread_notifications: "$.ctx.notifications"
    next: done

  - id: done
    type: end
```

### 12. `examples/parallel/fan_out_fan_in.yml`

```yaml
# Fan-out processing then fan-in results
id: fan_out_fan_in
name: Fan Out Fan In
version: "1.0"

input_schema:
  type: object
  properties:
    regions:
      type: array
      items:
        type: string

steps:
  - id: start
    type: start
    next: process_regions

  - id: process_regions
    type: parallel
    config:
      branches:
        us:
          - id: us_data
            type: assign
            config:
              assignments:
                us_result:
                  region: "'US'"
                  sales: 1000000
                  growth: 0.15

        eu:
          - id: eu_data
            type: assign
            config:
              assignments:
                eu_result:
                  region: "'EU'"
                  sales: 850000
                  growth: 0.12

        apac:
          - id: apac_data
            type: assign
            config:
              assignments:
                apac_result:
                  region: "'APAC'"
                  sales: 750000
                  growth: 0.22

      merge_strategy: all
    next: aggregate_results

  - id: aggregate_results
    type: assign
    config:
      assignments:
        total_sales: "$.ctx.us_result.sales + $.ctx.eu_result.sales + $.ctx.apac_result.sales"
        regions: "[$.ctx.us_result, $.ctx.eu_result, $.ctx.apac_result]"
        average_growth: "($.ctx.us_result.growth + $.ctx.eu_result.growth + $.ctx.apac_result.growth) / 3"
    next: done

  - id: done
    type: end
```

### 13. `examples/services/services.rb`

```ruby
# frozen_string_literal: true

# Example service implementations

module ExampleServices
  class UserService
    def get_profile(user_id:)
      {
        id: user_id,
        name: "User #{user_id}",
        email: "user#{user_id}@example.com",
        created_at: Time.now.iso8601
      }
    end

    def update_profile(user_id:, updates:)
      { updated: true, user_id: user_id, changes: updates }
    end
  end

  class OrderService
    def get_recent(user_id:, limit: 10)
      limit.times.map do |i|
        {
          id: "ORD-#{user_id}-#{i}",
          amount: rand(10..500),
          status: %w[pending shipped delivered].sample,
          created_at: (Time.now - rand(1..30) * 86400).iso8601
        }
      end
    end

    def create(user_id:, items:)
      {
        id: "ORD-#{SecureRandom.hex(4)}",
        user_id: user_id,
        items: items,
        total: items.sum { |i| i[:price] * i[:quantity] },
        status: "pending",
        created_at: Time.now.iso8601
      }
    end
  end

  class NotificationService
    def unread(user_id:)
      rand(0..10).times.map do |i|
        {
          id: "NOTIF-#{i}",
          type: %w[order_update promotion reminder].sample,
          message: "Notification #{i} for user #{user_id}",
          created_at: (Time.now - rand(1..7) * 86400).iso8601
        }
      end
    end

    def send(user_id:, type:, message:)
      { sent: true, notification_id: "NOTIF-#{SecureRandom.hex(4)}" }
    end
  end

  class PaymentService
    def process(amount:, currency: "USD", method: "card")
      sleep(0.1) # Simulate processing time
      {
        transaction_id: "TXN-#{SecureRandom.hex(6)}",
        amount: amount,
        currency: currency,
        method: method,
        status: "completed",
        processed_at: Time.now.iso8601
      }
    end

    def refund(transaction_id:, amount:)
      {
        refund_id: "REF-#{SecureRandom.hex(6)}",
        original_transaction: transaction_id,
        amount: amount,
        status: "completed"
      }
    end
  end

  class InventoryService
    def check(product_id:)
      {
        product_id: product_id,
        available: rand(0..100),
        reserved: rand(0..20),
        warehouse: %w[WEST EAST CENTRAL].sample
      }
    end

    def reserve(product_id:, quantity:)
      {
        reservation_id: "RES-#{SecureRandom.hex(4)}",
        product_id: product_id,
        quantity: quantity,
        expires_at: (Time.now + 3600).iso8601
      }
    end
  end
end
```

### 14. `examples/services/external_api.yml`

```yaml
# Call external API service
id: external_api
name: External API Call
version: "1.0"

input_schema:
  type: object
  properties:
    product_id:
      type: string
    quantity:
      type: integer

steps:
  - id: start
    type: start
    next: check_inventory

  - id: check_inventory
    type: call
    config:
      service: inventory_service
      method: check
      args:
        product_id: "$.input.product_id"
      result_key: inventory
    next: evaluate_stock

  - id: evaluate_stock
    type: router
    config:
      routes:
        - condition: "$.ctx.inventory.available >= $.input.quantity"
          next: reserve_stock
      default: out_of_stock

  - id: reserve_stock
    type: call
    config:
      service: inventory_service
      method: reserve
      args:
        product_id: "$.input.product_id"
        quantity: "$.input.quantity"
      result_key: reservation
    next: success

  - id: out_of_stock
    type: assign
    config:
      assignments:
        error: "'Insufficient inventory'"
        available: "$.ctx.inventory.available"
        requested: "$.input.quantity"
    next: done

  - id: success
    type: assign
    config:
      assignments:
        result:
          status: "'reserved'"
          reservation: "$.ctx.reservation"
          product_id: "$.input.product_id"
          quantity: "$.input.quantity"
    next: done

  - id: done
    type: end
```

### 15. `examples/services/run_services.rb`

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"
require_relative "services"

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

# Register services
DurableWorkflow.register_service(:user_service, ExampleServices::UserService.new)
DurableWorkflow.register_service(:order_service, ExampleServices::OrderService.new)
DurableWorkflow.register_service(:notification_service, ExampleServices::NotificationService.new)
DurableWorkflow.register_service(:payment_service, ExampleServices::PaymentService.new)
DurableWorkflow.register_service(:inventory_service, ExampleServices::InventoryService.new)

# External API Example
puts "=== External API Workflow ==="
workflow = DurableWorkflow.load("examples/services/external_api.yml")
runner = DurableWorkflow::Runners::Sync.new(workflow)

result = runner.run(product_id: "PROD-001", quantity: 5)
puts "Result: #{result.output}"

# Concurrent Tasks Example
puts "\n=== Concurrent Tasks Workflow ==="
concurrent = DurableWorkflow.load("examples/parallel/concurrent_tasks.yml")
runner = DurableWorkflow::Runners::Sync.new(concurrent)

result = runner.run(user_id: "USER-123")
puts "Dashboard data:"
puts "  Profile: #{result.output[:dashboard][:user][:name]}"
puts "  Orders: #{result.output[:dashboard][:recent_orders].size} recent orders"
puts "  Notifications: #{result.output[:dashboard][:unread_notifications].size} unread"
```

### 16. `examples/subworkflows/parent.yml`

```yaml
# Parent workflow that calls child workflows
id: parent_workflow
name: Parent Workflow
version: "1.0"

input_schema:
  type: object
  properties:
    orders:
      type: array
      items:
        type: object

steps:
  - id: start
    type: start
    next: init

  - id: init
    type: assign
    config:
      assignments:
        processed_orders: "[]"
        total_revenue: 0
    next: process_orders

  - id: process_orders
    type: loop
    config:
      collection: "$.input.orders"
      item_var: order
      body:
        - id: process_single_order
          type: workflow
          config:
            workflow_id: child_workflow
            input:
              order_id: "$.ctx.order.id"
              items: "$.ctx.order.items"
              customer_id: "$.ctx.order.customer_id"
            result_key: order_result

        - id: accumulate
          type: assign
          config:
            assignments:
              processed_orders: "$.ctx.processed_orders.concat([$.ctx.order_result])"
              total_revenue: "$.ctx.total_revenue + $.ctx.order_result.total"
    next: summarize

  - id: summarize
    type: assign
    config:
      assignments:
        summary:
          orders_processed: "$.ctx.processed_orders.length"
          total_revenue: "$.ctx.total_revenue"
          orders: "$.ctx.processed_orders"
    next: done

  - id: done
    type: end
```

### 17. `examples/subworkflows/child.yml`

```yaml
# Child workflow for processing a single order
id: child_workflow
name: Process Single Order
version: "1.0"

input_schema:
  type: object
  properties:
    order_id:
      type: string
    items:
      type: array
    customer_id:
      type: string

steps:
  - id: start
    type: start
    next: calculate_total

  - id: calculate_total
    type: assign
    config:
      assignments:
        subtotal: 0
    next: sum_items

  - id: sum_items
    type: loop
    config:
      collection: "$.input.items"
      item_var: item
      body:
        - id: add_item
          type: assign
          config:
            assignments:
              subtotal: "$.ctx.subtotal + ($.ctx.item.price * $.ctx.item.quantity)"
    next: apply_tax

  - id: apply_tax
    type: assign
    config:
      assignments:
        tax: "$.ctx.subtotal * 0.08"
        total: "$.ctx.subtotal * 1.08"
    next: create_result

  - id: create_result
    type: assign
    config:
      assignments:
        result:
          order_id: "$.input.order_id"
          customer_id: "$.input.customer_id"
          subtotal: "$.ctx.subtotal"
          tax: "$.ctx.tax"
          total: "$.ctx.total"
          status: "'processed'"
    next: done

  - id: done
    type: end
```

### 18. `examples/subworkflows/run_subworkflows.rb`

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

# Load and register both workflows
child = DurableWorkflow.load("examples/subworkflows/child.yml")
parent = DurableWorkflow.load("examples/subworkflows/parent.yml")

DurableWorkflow.register(child)
DurableWorkflow.register(parent)

# Run parent workflow
runner = DurableWorkflow::Runners::Sync.new(parent)

result = runner.run(orders: [
  {
    id: "ORD-001",
    customer_id: "CUST-001",
    items: [
      { name: "Widget", price: 10, quantity: 3 },
      { name: "Gadget", price: 25, quantity: 2 }
    ]
  },
  {
    id: "ORD-002",
    customer_id: "CUST-002",
    items: [
      { name: "Widget", price: 10, quantity: 5 },
      { name: "Gizmo", price: 15, quantity: 1 }
    ]
  }
])

puts "=== Order Processing Complete ==="
puts "Orders processed: #{result.output[:summary][:orders_processed]}"
puts "Total revenue: $#{result.output[:summary][:total_revenue].round(2)}"
puts "\nOrder details:"
result.output[:summary][:orders].each do |order|
  puts "  #{order[:order_id]}: $#{order[:total].round(2)}"
end
```

### 19. `examples/streaming/run_streaming.rb`

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

# Load workflow
workflow = DurableWorkflow.load("examples/basic/calculator.yml")
runner = DurableWorkflow::Runners::Stream.new(workflow)

# Subscribe to all events
puts "=== Streaming Events ==="
runner.subscribe do |event|
  puts "[#{event.timestamp.strftime('%H:%M:%S.%L')}] #{event.type}"
  puts "  Data: #{event.data}"
end

# Also show SSE format
runner.subscribe(events: ["workflow.completed"]) do |event|
  puts "\n=== SSE Format ==="
  puts event.to_sse
end

# Run workflow
result = runner.run(operation: "multiply", a: 7, b: 6)
puts "\nFinal result: #{result.output[:result]}"
```

### 20. `examples/complete/order_processing.yml`

```yaml
# Complete order processing workflow
id: order_processing
name: Complete Order Processing
version: "1.0"

input_schema:
  type: object
  properties:
    customer_id:
      type: string
    items:
      type: array
      items:
        type: object
        properties:
          product_id:
            type: string
          quantity:
            type: integer
          price:
            type: number
    shipping_address:
      type: object
    payment_method:
      type: string
  required:
    - customer_id
    - items
    - shipping_address
    - payment_method

steps:
  - id: start
    type: start
    next: validate_order

  - id: validate_order
    type: assign
    config:
      assignments:
        order_id: "'ORD-' + Date.now().toString(36)"
        item_count: "$.input.items.length"
    next: check_items

  - id: check_items
    type: router
    config:
      routes:
        - condition: "$.ctx.item_count == 0"
          next: empty_cart_error
      default: calculate_totals

  - id: empty_cart_error
    type: assign
    config:
      assignments:
        error: "'Cannot process empty order'"
    next: failed

  - id: calculate_totals
    type: assign
    config:
      assignments:
        subtotal: 0
        processing_items: "[]"
    next: process_items

  - id: process_items
    type: loop
    config:
      collection: "$.input.items"
      item_var: item
      body:
        - id: check_inventory
          type: call
          config:
            service: inventory_service
            method: check
            args:
              product_id: "$.ctx.item.product_id"
            result_key: stock

        - id: validate_stock
          type: router
          config:
            routes:
              - condition: "$.ctx.stock.available >= $.ctx.item.quantity"
                next: add_to_order
            default: insufficient_stock

        - id: add_to_order
          type: assign
          config:
            assignments:
              line_total: "$.ctx.item.quantity * $.ctx.item.price"
              subtotal: "$.ctx.subtotal + $.ctx.line_total"
              processing_items: "$.ctx.processing_items.concat([{ ...$.ctx.item, available: true, line_total: $.ctx.line_total }])"

        - id: insufficient_stock
          type: assign
          config:
            assignments:
              processing_items: "$.ctx.processing_items.concat([{ ...$.ctx.item, available: false, error: 'Insufficient stock' }])"
    next: check_availability

  - id: check_availability
    type: router
    config:
      routes:
        - condition: "$.ctx.processing_items.every(i => i.available)"
          next: apply_pricing
      default: partial_availability

  - id: partial_availability
    type: halt
    config:
      data:
        message: "'Some items are unavailable'"
        available_items: "$.ctx.processing_items.filter(i => i.available)"
        unavailable_items: "$.ctx.processing_items.filter(i => !i.available)"
        subtotal: "$.ctx.subtotal"
    next: handle_partial_response

  - id: handle_partial_response
    type: router
    config:
      routes:
        - condition: "$.ctx._response.proceed == true"
          next: apply_pricing
      default: cancelled

  - id: apply_pricing
    type: assign
    config:
      assignments:
        tax_rate: 0.08
        shipping_cost: "$.ctx.subtotal > 100 ? 0 : 9.99"
        tax: "$.ctx.subtotal * $.ctx.tax_rate"
        total: "$.ctx.subtotal + $.ctx.tax + $.ctx.shipping_cost"
    next: check_high_value

  - id: check_high_value
    type: router
    config:
      routes:
        - condition: "$.ctx.total > 500"
          next: require_approval
      default: process_payment

  - id: require_approval
    type: approval
    config:
      prompt: "'High value order requires approval: $' + $.ctx.total.toFixed(2)"
      data:
        order_id: "$.ctx.order_id"
        customer_id: "$.input.customer_id"
        total: "$.ctx.total"
        items: "$.ctx.processing_items"
      approved_next: process_payment
      rejected_next: rejected

  - id: process_payment
    type: call
    config:
      service: payment_service
      method: process
      args:
        amount: "$.ctx.total"
        currency: "'USD'"
        method: "$.input.payment_method"
      result_key: payment
    next: reserve_inventory

  - id: reserve_inventory
    type: loop
    config:
      collection: "$.ctx.processing_items.filter(i => i.available)"
      item_var: item
      body:
        - id: reserve_item
          type: call
          config:
            service: inventory_service
            method: reserve
            args:
              product_id: "$.ctx.item.product_id"
              quantity: "$.ctx.item.quantity"
    next: create_order_record

  - id: create_order_record
    type: assign
    config:
      assignments:
        order:
          id: "$.ctx.order_id"
          customer_id: "$.input.customer_id"
          items: "$.ctx.processing_items.filter(i => i.available)"
          subtotal: "$.ctx.subtotal"
          tax: "$.ctx.tax"
          shipping: "$.ctx.shipping_cost"
          total: "$.ctx.total"
          payment: "$.ctx.payment"
          shipping_address: "$.input.shipping_address"
          status: "'confirmed'"
          created_at: "new Date().toISOString()"
    next: send_confirmation

  - id: send_confirmation
    type: call
    config:
      service: notification_service
      method: send
      args:
        user_id: "$.input.customer_id"
        type: "'order_confirmation'"
        message: "'Your order ' + $.ctx.order_id + ' has been confirmed!'"
    next: completed

  - id: completed
    type: assign
    config:
      assignments:
        result:
          status: "'success'"
          order: "$.ctx.order"
    next: done

  - id: cancelled
    type: assign
    config:
      assignments:
        result:
          status: "'cancelled'"
          reason: "'Customer cancelled due to unavailable items'"
    next: done

  - id: rejected
    type: assign
    config:
      assignments:
        result:
          status: "'rejected'"
          reason: "'Order rejected during approval'"
    next: done

  - id: failed
    type: assign
    config:
      assignments:
        result:
          status: "'failed'"
          error: "$.ctx.error"
    next: done

  - id: done
    type: end
```

### 21. `examples/complete/run_complete.rb`

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"
require_relative "../services/services"

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
end

# Register services
DurableWorkflow.register_service(:inventory_service, ExampleServices::InventoryService.new)
DurableWorkflow.register_service(:payment_service, ExampleServices::PaymentService.new)
DurableWorkflow.register_service(:notification_service, ExampleServices::NotificationService.new)

# Load workflow
workflow = DurableWorkflow.load("examples/complete/order_processing.yml")
runner = DurableWorkflow::Runners::Stream.new(workflow)

# Subscribe to events
runner.subscribe do |event|
  case event.type
  when "step.started"
    puts "  -> #{event.data[:step_id]}"
  when "workflow.halted"
    puts "  HALTED: #{event.data[:halt][:message]}"
  when "workflow.completed"
    puts "  COMPLETED"
  end
end

puts "=== Order Processing Workflow ==="
puts

# Process an order
result = runner.run_until_complete(
  customer_id: "CUST-001",
  items: [
    { product_id: "PROD-001", quantity: 2, price: 29.99 },
    { product_id: "PROD-002", quantity: 1, price: 149.99 },
    { product_id: "PROD-003", quantity: 3, price: 9.99 }
  ],
  shipping_address: {
    street: "123 Main St",
    city: "Anytown",
    state: "CA",
    zip: "12345"
  },
  payment_method: "card"
) do |halt|
  puts "\nHalt received: #{halt.prompt || halt.data[:message]}"

  if halt.data[:unavailable_items]
    puts "Unavailable items: #{halt.data[:unavailable_items].size}"
    puts "Proceed anyway? (simulating yes)"
    { proceed: true }
  else
    # Approval request
    puts "Approving high-value order..."
    true
  end
end

puts "\n=== Result ==="
puts "Status: #{result.output[:result][:status]}"
if result.output[:result][:order]
  order = result.output[:result][:order]
  puts "Order ID: #{order[:id]}"
  puts "Total: $#{order[:total].round(2)}"
  puts "Items: #{order[:items].size}"
end
```

### 22. `examples/ai/chatbot.yml` (requires AI extension)

```yaml
# Simple chatbot workflow using AI extension
id: chatbot
name: AI Chatbot
version: "1.0"

# AI extension data
agents:
  assistant:
    model: claude-sonnet
    system_prompt: |
      You are a helpful customer service assistant. Be friendly,
      professional, and concise. If you don't know something, say so.
    tools:
      - get_order_status
      - get_product_info

tools:
  get_order_status:
    description: Get the status of a customer order
    parameters:
      order_id:
        type: string
        description: The order ID to look up
    handler: order_service.get_status

  get_product_info:
    description: Get information about a product
    parameters:
      product_id:
        type: string
        description: The product ID to look up
    handler: product_service.get_info

input_schema:
  type: object
  properties:
    message:
      type: string
    conversation_history:
      type: array

steps:
  - id: start
    type: start
    next: chat

  - id: chat
    type: agent
    config:
      agent: assistant
      input: "$.input.message"
      context:
        history: "$.input.conversation_history"
    next: done

  - id: done
    type: end
```

### 23. `examples/ai/run_ai.rb`

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "durable_workflow"
require "durable_workflow/storage/redis"
require "durable_workflow/extensions/ai"  # Load AI extension

DurableWorkflow.configure do |c|
  c.store = DurableWorkflow::Storage::Redis.new(url: "redis://localhost:6379")
  c.ai_api_key = ENV["ANTHROPIC_API_KEY"]
end

# Mock services for tool calls
class OrderService
  def get_status(order_id:)
    { order_id: order_id, status: "shipped", eta: "2024-01-15" }
  end
end

class ProductService
  def get_info(product_id:)
    { product_id: product_id, name: "Widget Pro", price: 49.99, in_stock: true }
  end
end

DurableWorkflow.register_service(:order_service, OrderService.new)
DurableWorkflow.register_service(:product_service, ProductService.new)

# Load AI workflow
workflow = DurableWorkflow.load("examples/ai/chatbot.yml")
runner = DurableWorkflow::Runners::Stream.new(workflow)

# Subscribe to AI events
runner.subscribe(events: ["agent.thinking", "agent.tool_use", "agent.response"]) do |event|
  case event.type
  when "agent.thinking"
    print "."
  when "agent.tool_use"
    puts "\n[Tool: #{event.data[:tool]}]"
  when "agent.response"
    puts "\nAssistant: #{event.data[:content]}"
  end
end

# Chat loop
history = []
puts "=== AI Chatbot ==="
puts "Type 'quit' to exit\n\n"

loop do
  print "You: "
  input = gets.chomp
  break if input.downcase == "quit"

  result = runner.run(message: input, conversation_history: history)

  history << { role: "user", content: input }
  history << { role: "assistant", content: result.output[:response] }
end
```

## Usage Instructions

### Quick Start

```bash
# Install dependencies
bundle install

# Start Redis
redis-server

# Run basic examples
ruby examples/basic/run_basic.rb

# Run with streaming
ruby examples/streaming/run_streaming.rb

# Run complete order processing
ruby examples/complete/run_complete.rb
```

### Running Individual Examples

```bash
# Basic workflows
ruby examples/basic/run_basic.rb

# Routing examples
ruby examples/routing/run_routing.rb

# Loop examples
ruby examples/loops/run_loops.rb

# Halt/approval examples
ruby examples/halts/run_halts.rb

# Service integration
ruby examples/services/run_services.rb

# Sub-workflows
ruby examples/subworkflows/run_subworkflows.rb

# AI chatbot (requires API key)
ANTHROPIC_API_KEY=your-key ruby examples/ai/run_ai.rb
```

## Acceptance Criteria

1. All example workflows are syntactically valid
2. Each category has working runner script
3. Services demonstrate integration patterns
4. Streaming example shows SSE format
5. Complete example combines multiple features
6. AI example demonstrates extension usage
7. All examples include comments explaining key concepts
