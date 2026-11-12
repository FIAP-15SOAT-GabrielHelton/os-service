# frozen_string_literal: true

module Messaging
  # Eventos da Saga (RFC-005) que este serviço consome.
  module EventHandlers
    QUEUE = "os-service"

    def self.build
      {
        "quote.approved" => ->(data) { run(approve_work_order, data) },
        "quote.rejected" => ->(data) { run(reject_work_order, data) },
        "execution.started" => ->(data) { run(WorkOrders::ExecuteService.new(work_order_repository: work_order_repository), data) },
        "execution.completed" => ->(data) { run(complete_work_order, data, items: data.fetch("items")) },
        "execution.failed" => ->(data) { run(cancel_work_order, data) },
        "payment.approved" => ->(data) { run(WorkOrders::PayWorkOrder.new(work_order_repository: work_order_repository, notifier: notifier), data) }
      }
    end

    def self.run(use_case, data, **extra)
      result = use_case.call(id: data.fetch("work_order_id"), **extra)
      raise result.error if result.failure?
    end

    def self.complete_work_order
      WorkOrders::CompleteWorkOrder.new(work_order_repository: work_order_repository, notifier: notifier)
    end

    def self.approve_work_order
      WorkOrders::ApproveWorkOrder.new(
        work_order_repository: work_order_repository,
        decrease_quantity: Inventory::DecreaseQuantity.new(inventory_item_repository: inventory_item_repository),
        cancel_work_order: cancel_work_order,
        notifier: notifier
      )
    end

    def self.cancel_work_order
      WorkOrders::CancelWorkOrder.new(
        work_order_repository: work_order_repository,
        add_quantity: Inventory::AddQuantity.new(inventory_item_repository: inventory_item_repository),
        notifier: notifier
      )
    end

    def self.inventory_item_repository
      Persistence::Inventory::ActiveRecordInventoryItemRepository.new
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
