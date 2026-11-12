# frozen_string_literal: true

require_relative "../shared/entity"
require_relative "../shared/money"

module WorkOrders
  class LineItem < Shared::Entity
    ITEM_TYPES = %i[service part].freeze

    class InvalidTransition < StandardError; end

    attr_reader :item_type, :reference_id, :name_snapshot, :price_snapshot, :quantity,
                :started_at, :finished_at

    def initialize(id:, item_type:, reference_id:, name_snapshot:, price_snapshot:, quantity:,
                   started_at: nil, finished_at: nil)
      super(id: id)
      @item_type = validate_item_type!(item_type)
      @reference_id = reference_id
      @name_snapshot = name_snapshot
      @price_snapshot = ensure_price(price_snapshot)
      @quantity = Integer(quantity)
      raise ArgumentError, "Quantity must be positive" unless @quantity.positive?

      @started_at = started_at
      @finished_at = finished_at
    end

    def service?
      item_type == :service
    end

    def part?
      item_type == :part
    end

    def pending?
      service? && started_at.nil?
    end

    def in_progress?
      service? && !started_at.nil? && finished_at.nil?
    end

    def ready?
      service? && !finished_at.nil?
    end

    # Os horários vêm do execution-service (evento execution.completed).
    def start!(at = Time.current)
      raise InvalidTransition, "Only service items can be started" unless service?
      raise InvalidTransition, "Service has already been started" unless pending?

      @started_at = at
    end

    def finish!(at = Time.current)
      raise InvalidTransition, "Only service items can be finished" unless service?
      raise InvalidTransition, "Service must be in progress to be finished" unless in_progress?

      @finished_at = at
    end

    def duration_minutes
      return nil unless ready?

      ((finished_at - started_at) / 60.0)
    end

    def subtotal
      price_snapshot * quantity
    end

    private

    def validate_item_type!(type)
      type = type.to_sym
      raise ArgumentError, "item_type must be one of: #{ITEM_TYPES.join(', ')}" unless ITEM_TYPES.include?(type)

      type
    end

    def ensure_price(price)
      price.is_a?(Shared::Money) ? price : Shared::Money.new(cents: price)
    end
  end
end
