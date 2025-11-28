# frozen_string_literal: true

require "securerandom"

# Mock services for support agent demo
module SupportServices
  ORDERS = {
    "ORD-12345" => {
      id: "ORD-12345",
      customer_email: "alice@example.com",
      status: "shipped",
      total: 149.99,
      items: [
        { name: "Wireless Headphones", quantity: 1, price: 149.99 }
      ],
      created_at: "2024-01-10",
      tracking: "1Z999AA10123456784"
    },
    "ORD-67890" => {
      id: "ORD-67890",
      customer_email: "bob@example.com",
      status: "delivered",
      total: 299.99,
      items: [
        { name: "Smart Watch", quantity: 1, price: 299.99 }
      ],
      created_at: "2024-01-05",
      delivered_at: "2024-01-08"
    }
  }

  TICKETS = {}

  class << self
    def classify_request(category:, urgency:, summary:)
      {
        category: category,
        urgency: urgency,
        summary: summary,
        classified_at: Time.now.iso8601
      }
    end

    def lookup_order(order_id: nil, email: nil)
      if order_id
        order = ORDERS[order_id]
        return { error: "Order not found: #{order_id}" } unless order
        order
      elsif email
        orders = ORDERS.values.select { |o| o[:customer_email] == email }
        return { error: "No orders found for #{email}" } if orders.empty?
        { orders: orders, count: orders.size }
      else
        { error: "Please provide order_id or email" }
      end
    end

    def refund_order(order_id:, reason:, amount: nil)
      order = ORDERS[order_id]
      return { error: "Order not found: #{order_id}" } unless order

      refund_amount = amount || order[:total]
      {
        refund_id: "REF-#{SecureRandom.hex(4).upcase}",
        order_id: order_id,
        amount: refund_amount,
        reason: reason,
        status: "processed",
        processed_at: Time.now.iso8601
      }
    end

    def create_ticket(subject:, description:, priority: "medium")
      ticket_id = "TKT-#{SecureRandom.hex(4).upcase}"
      ticket = {
        id: ticket_id,
        subject: subject,
        description: description,
        priority: priority,
        status: "open",
        created_at: Time.now.iso8601
      }
      TICKETS[ticket_id] = ticket
      ticket
    end

    def check_status(ticket_id:)
      ticket = TICKETS[ticket_id]
      return { error: "Ticket not found: #{ticket_id}" } unless ticket
      ticket
    end

    def reset_password(email:)
      {
        email: email,
        reset_sent: true,
        message: "Password reset email sent to #{email}",
        expires_in: "24 hours"
      }
    end

    def escalate(reason:, urgency:)
      {
        escalation_id: "ESC-#{SecureRandom.hex(4).upcase}",
        reason: reason,
        urgency: urgency,
        status: "pending_human_review",
        estimated_response: urgency == "high" ? "1 hour" : "4 hours",
        created_at: Time.now.iso8601
      }
    end
  end
end
