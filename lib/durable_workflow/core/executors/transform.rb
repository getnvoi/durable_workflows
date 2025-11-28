# frozen_string_literal: true

module DurableWorkflow
  module Core
    module Executors
      class Transform < Base
        Registry.register('transform', self)

        OPS = {
          'map' => lambda { |d, a|
            if d.is_a?(Array)
              d.map { |i| a.is_a?(String) ? Transform.dig(i, a) : i }
            else
              d
            end
          },
          'select' => ->(d, a) { d.is_a?(Array) ? d.select { |i| Transform.match?(i, a) } : d },
          'reject' => ->(d, a) { d.is_a?(Array) ? d.reject { |i| Transform.match?(i, a) } : d },
          'pluck' => ->(d, a) { d.is_a?(Array) ? d.map { |i| Transform.dig(i, a) } : d },
          'first' => ->(d, a) { d.is_a?(Array) ? d.first(a || 1) : d },
          'last' => ->(d, a) { d.is_a?(Array) ? d.last(a || 1) : d },
          'flatten' => ->(d, a) { d.is_a?(Array) ? d.flatten(a || 1) : d },
          'compact' => ->(d, _) { d.is_a?(Array) ? d.compact : d },
          'uniq' => ->(d, _) { d.is_a?(Array) ? d.uniq : d },
          'reverse' => ->(d, _) { d.is_a?(Array) ? d.reverse : d },
          'sort' => lambda { |d, a|
            if d.is_a?(Array)
              a ? d.sort_by { |i| Transform.dig(i, a) } : d.sort
            else
              d
            end
          },
          'count' => ->(d, _) { d.respond_to?(:size) ? d.size : 1 },
          'sum' => lambda { |d, a|
            if d.is_a?(Array)
              a ? d.sum { |i| Transform.dig(i, a).to_f } : d.sum(&:to_f)
            else
              d
            end
          },
          'keys' => ->(d, _) { d.is_a?(Hash) ? d.keys : [] },
          'values' => ->(d, _) { d.is_a?(Hash) ? d.values : [] },
          'pick' => ->(d, a) { d.is_a?(Hash) ? d.slice(*Array(a).map(&:to_sym)) : d },
          'omit' => ->(d, a) { d.is_a?(Hash) ? d.except(*Array(a).map(&:to_sym)) : d },
          'merge' => ->(d, a) { d.is_a?(Hash) && a.is_a?(Hash) ? d.merge(a) : d }
        }.freeze

        def call(state)
          input = config.input ? resolve(state, "$#{config.input}") : state.ctx.dup
          expr = config.expression

          result = expr.reduce(input) do |data, (op, arg)|
            OPS.fetch(op.to_s) { ->(d, _) { d } }.call(data, arg)
          end

          state = store(state, config.output, result)
          continue(state, output: result)
        end

        def self.dig(obj, key)
          keys = key.to_s.split('.')
          keys.reduce(obj) { |o, k| o.is_a?(Hash) ? Utils.fetch(o, k) : nil }
        end

        def self.match?(obj, conditions)
          conditions.all? { |k, v| dig(obj, k) == v }
        end
      end
    end
  end
end
