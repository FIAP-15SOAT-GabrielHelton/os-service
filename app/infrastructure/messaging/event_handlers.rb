# frozen_string_literal: true

module Messaging
  # Eventos da Saga (RFC-005) que este serviço consome.
  module EventHandlers
    QUEUE = "os-service"

    def self.build
      {
        "quote.approved" => ->(data) { run(approve_work_order, data) },
        "quote.rejected" => ->(data) { run(reject_work_order, data) }
      }
    end

    def self.run(use_case, data)
      result = use_case.call(id: data.fetch("work_order_id"))
      raise result.error if result.failure?
    end

    def self.approve_work_order
      WorkOrders::ApproveWorkOrder.new(
        work_order_repository: work_order_repository,
        decrease_quantity: Inventory::DecreaseQuantity.new(
          inventory_item_repository: Persistence::Inventory::ActiveRecordInventoryItemRepository.new
        ),
        notifier: notifier
      )
    end

    def self.reject_work_order
      WorkOrders::RejectWorkOrder.new(work_order_repository: work_order_repository, notifier: notifier)
    end

    def self.work_order_repository
      Persistence::WorkOrders::ActiveRecordWorkOrderRepository.new
    end

    def self.notifier
      Shared::WorkOrderNotifier.new(
        notifiers: [
          Shared::WorkOrderEmailNotifier.new(
            customer_repository: Persistence::Registrations::ActiveRecordCustomerRepository.new
          ),
          Shared::WorkOrderMetricsNotifier.new,
          (Shared::WorkOrderEventNotifier.new(publisher: RabbitmqPublisher.new) if ENV["RABBITMQ_URL"])
        ].compact
      )
    end
  end
end
