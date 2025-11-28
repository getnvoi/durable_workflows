# frozen_string_literal: true

require "securerandom"

# Order validation and calculation service
module OrderService
  class << self
    def validate_order(order_id:, customer:, items:)
      errors = []

      errors << "Order ID required" if order_id.nil? || order_id.to_s.empty?
      errors << "Customer required" if customer.nil?
      errors << "Customer email required" if customer && customer[:email].to_s.empty?
      errors << "Items required" if items.nil? || items.empty?

      items&.each_with_index do |item, i|
        errors << "Item #{i + 1}: product_id required" if item[:product_id].to_s.empty?
        errors << "Item #{i + 1}: quantity must be positive" if item[:quantity].to_i <= 0
        errors << "Item #{i + 1}: price required" if item[:price].to_f <= 0
      end

      {
        valid: errors.empty?,
        errors: errors.empty? ? nil : errors,
        validated_at: Time.now.iso8601
      }
    end

    def calculate_totals(items:, options:)
      subtotal = items.sum { |item| item[:quantity] * item[:price] }
      tax = subtotal * 0.08
      shipping = (options && options[:expedited]) ? 14.99 : 5.99
      total = subtotal + tax + shipping

      {
        subtotal: subtotal.round(2),
        tax: tax.round(2),
        shipping: shipping,
        total: total.round(2)
      }
    end
  end
end

# Inventory management service
module InventoryService
  STOCK = {
    "PROD-001" => { name: "Widget Pro", quantity: 100, price: 29.99 },
    "PROD-002" => { name: "Gadget Plus", quantity: 50, price: 49.99 },
    "PROD-003" => { name: "Gizmo Max", quantity: 0, price: 99.99 },
    "PROD-004" => { name: "Device Ultra", quantity: 25, price: 199.99 }
  }

  RESERVATIONS = {}

  class << self
    def check_availability(items:)
      available = []
      unavailable = []

      items.each do |item|
        stock = STOCK[item[:product_id]]
        if stock && stock[:quantity] >= item[:quantity]
          available << item[:product_id]
        else
          unavailable << {
            product_id: item[:product_id],
            requested: item[:quantity],
            available: stock&.dig(:quantity) || 0
          }
        end
      end

      {
        all_available: unavailable.empty?,
        available: available,
        unavailable: unavailable,
        checked_at: Time.now.iso8601
      }
    end

    def reserve(items:, order_id:)
      reservation_id = "RES-#{SecureRandom.hex(6).upcase}"

      items.each do |item|
        stock = STOCK[item[:product_id]]
        stock[:quantity] -= item[:quantity] if stock
      end

      RESERVATIONS[reservation_id] = {
        order_id: order_id,
        items: items,
        reserved_at: Time.now.iso8601
      }

      {
        id: reservation_id,
        order_id: order_id,
        items: items.size,
        reserved_at: Time.now.iso8601
      }
    end
  end
end

# Shipping service
module ShippingService
  class << self
    def create_shipment(order_id:, customer:, items:)
      tracking = "TRK#{SecureRandom.hex(8).upcase}"
      address = customer[:address] || {}

      {
        shipment_id: "SHIP-#{SecureRandom.hex(6).upcase}",
        order_id: order_id,
        tracking_number: tracking,
        carrier: "FastShip",
        destination: "#{address[:city]}, #{address[:state]}",
        estimated_delivery: (Date.today + 5).iso8601,
        created_at: Time.now.iso8601
      }
    end
  end
end

# Payment processing service
module PaymentService
  class << self
    def charge(payment:, amount:)
      token = payment[:token]

      # Simulate declined cards
      if token == "declined"
        raise "Card declined"
      end

      {
        success: true,
        payment_id: "PAY-#{SecureRandom.hex(8).upcase}",
        amount: amount,
        payment_method: payment[:method],
        processed_at: Time.now.iso8601
      }
    end
  end
end
