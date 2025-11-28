# 04-EXAMPLE-ORDER-FULFILLMENT: E-Commerce Order Processing

## ⚠️ STATUS: FUTURE/ASPIRATIONAL

**This document describes a FUTURE example that requires features not yet implemented:**

- Ruby expression evaluation in YAML (e.g., `$item.quantity * $item.price`) - NOT SUPPORTED
- `DurableWorkflow.register_service()` - NOT IMPLEMENTED (use `Object.const_get`)
- `DurableWorkflow::Runners::Stream` - NOT IMPLEMENTED
- `runner.subscribe` - NOT IMPLEMENTED
- `runner.run_until_complete` with block - NOT IMPLEMENTED
- Loop step with inline computation - NOT SUPPORTED (no expression eval)

**The resolver only supports `$ref` substitution, NOT expression evaluation.**

**Do not attempt to run this example until these features are built or the example is rewritten.**

---

## Goal

Complete order fulfillment workflow demonstrating complex business logic, service integration, approvals, and error handling.

## Why This Example Doesn't Work

The workflow.yml in the original design relies heavily on Ruby expressions:

```yaml
# These DO NOT WORK - no expression evaluation
set:
  line_total: "$item.quantity * $item.price"    # ❌ No arithmetic
  subtotal: "$subtotal + $line_total"           # ❌ No arithmetic
  tax: "$subtotal * $tax_rate"                  # ❌ No arithmetic
  shipping_cost: "$subtotal >= 100 ? 0 : 9.99"  # ❌ No ternary
```

## How To Make This Work

To implement this example with current capabilities:

1. **Move ALL computation to services** - Every arithmetic operation must be in Ruby code
2. **Use `Object.const_get` for services** - Define as global modules/classes
3. **Use `Runners::Sync`** - The only working runner
4. **Simplify the workflow** - Use fewer steps, delegate logic to services

Example of correct approach:

```ruby
module OrderCalculator
  def self.calculate_totals(items:, tax_rate: 0.08)
    subtotal = items.sum { |i| i[:quantity] * i[:price] }
    tax = subtotal * tax_rate
    shipping = subtotal >= 100 ? 0 : 9.99
    {
      subtotal: subtotal,
      tax: tax,
      shipping: shipping,
      total: subtotal + tax + shipping
    }
  end
end
```

```yaml
- id: calculate
  type: call
  service: OrderCalculator
  method: calculate_totals
  input:
    items: "$input.items"
  output: totals
  next: end
```

---

## Implementation Prerequisites

To run this example AS DESIGNED (with expressions), implement:

1. Expression evaluation in resolver (or a dedicated `eval` step type)
2. `DurableWorkflow.register_service()` method
3. `Runners::Stream` with event subscription
4. `run_until_complete` with halt handling

OR rewrite the example to work with current constraints.

---

## Original Design Reference

[The original design below should be used as a reference for what the workflow
SHOULD do, but the YAML syntax needs to be rewritten to use services for all
computation.]
