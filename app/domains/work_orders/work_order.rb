# frozen_string_literal: true

require "securerandom"
require_relative "../shared/entity"
require_relative "value_objects/work_order_status"
require_relative "line_item"

module WorkOrders
  class WorkOrder < Shared::Entity
    PROTOCOL_LENGTH = 8

    class InvalidTransition < StandardError; end

    attr_reader :customer_id, :vehicle_id, :problem_description, :status, :mechanic_id,
                :line_items, :protocol, :created_at, :updated_at, :executed_at, :completed_at,
                :delivered_at, :total_execution_time_minutes

    def initialize(id:, customer_id:, vehicle_id:, problem_description:,
                   status: :received, mechanic_id: nil, line_items: [],
                   protocol: nil, created_at: nil, updated_at: nil,
                   executed_at: nil, completed_at: nil, delivered_at: nil,
                   total_execution_time_minutes: nil)
      super(id: id)
      raise ArgumentError, "customer_id is required" if customer_id.nil?
      raise ArgumentError, "vehicle_id is required" if vehicle_id.nil?

      @customer_id = customer_id
      @vehicle_id = vehicle_id
      @problem_description = problem_description
      @status = ensure_status(status)
      @mechanic_id = mechanic_id
      @line_items = line_items
      @protocol = protocol || SecureRandom.alphanumeric(PROTOCOL_LENGTH).upcase
      @created_at = created_at
      @updated_at = updated_at
      @executed_at = executed_at
      @completed_at = completed_at
      @delivered_at = delivered_at
      @total_execution_time_minutes = total_execution_time_minutes
    end

    ValueObjects::WorkOrderStatus::STATES.each do |state|
      define_method("#{state}?") { status.value == state }
    end

    def service_line_items
      line_items.select(&:service?)
    end

    def all_services_ready?
      services = service_line_items
      services.any? && services.all?(&:ready?)
    end

    def assign(mechanic_id)
      raise ArgumentError, "mechanic_id is required" if mechanic_id.nil?

      @status = @status.transition_to(:diagnosing)
      @mechanic_id = mechanic_id
    end

    def add_line_item(line_item)
      raise "Line items can only be added during diagnosis (current status: #{status})" unless diagnosing?
      raise ArgumentError, "Expected a LineItem" unless line_item.is_a?(LineItem)

      @line_items << line_item
    end

    def diagnose
      raise "Cannot diagnose a work order without line items" if line_items.empty?

      @status = @status.transition_to(:awaiting_approval)
    end

    def approve
      @status = @status.transition_to(:approved)
    end

    def execute
      @status = @status.transition_to(:in_progress)
      @executed_at = Time.now
    end

    def complete
      raise InvalidTransition, "All services must be finished before completing" unless all_services_ready?

      @status = @status.transition_to(:completed)
      @completed_at = Time.now
      @total_execution_time_minutes = compute_total_execution_time_minutes
    end

    def average_service_duration_minutes
      durations = service_line_items.map(&:duration_minutes).compact
      return nil if durations.empty?

      (durations.sum / durations.size).round(2)
    end

    def deliver
      @status = @status.transition_to(:delivered)
      @delivered_at = Time.now
    end

    def reject
      @status = @status.transition_to(:rejected)
    end

    def cancel
      @status = @status.transition_to(:cancelled)
    end

    private

    def compute_total_execution_time_minutes
      durations = service_line_items.map(&:duration_minutes).compact
      return nil if durations.empty?

      durations.sum.round(2)
    end

    def ensure_status(value)
      value.is_a?(ValueObjects::WorkOrderStatus) ? value : ValueObjects::WorkOrderStatus.new(value)
    end
  end
end
