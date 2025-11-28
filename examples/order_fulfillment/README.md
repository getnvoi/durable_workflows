# Order Fulfillment

E-commerce order processing workflow demonstrating complex state transitions,
service integration, parallel execution, and approval workflows.

## Features

- Multi-step order processing pipeline
- Inventory checking and reservation
- Payment processing with retry logic
- Parallel shipping calculations
- Approval workflow for high-value orders
- Event streaming for order tracking

## Setup

```bash
cd examples/order_fulfillment
bundle install
redis-server
```

## Usage

```bash
ruby run.rb
```

## Architecture

```
┌─────────────────┐
│  Validate Order │
└────────┬────────┘
         ↓
┌─────────────────┐
│ Check Inventory │
└────────┬────────┘
         ↓ (parallel)
┌─────────┴─────────┐
│   Reserve Stock   │
│   Calculate Ship  │
└─────────┬─────────┘
         ↓
┌─────────────────┐     ┌──────────────┐
│  Check Amount   │────→│   Approval   │
└────────┬────────┘     └──────┬───────┘
         ↓                     ↓
┌─────────────────┐
│ Process Payment │
└────────┬────────┘
         ↓
┌─────────────────┐
│ Create Shipment │
└────────┬────────┘
         ↓
┌─────────────────┐
│    Complete     │
└─────────────────┘
```

## Order States

- `pending` - Initial state
- `validated` - Order validated
- `inventory_reserved` - Stock reserved
- `payment_pending` - Waiting for payment
- `payment_approved` - High-value order approved
- `paid` - Payment processed
- `shipped` - Order shipped
- `completed` - Order complete
- `cancelled` - Order cancelled
- `failed` - Processing failed

## Event Types

Subscribe to real-time order events:

- `order.validated`
- `order.inventory_reserved`
- `order.payment_processed`
- `order.shipped`
- `order.completed`
- `order.failed`
