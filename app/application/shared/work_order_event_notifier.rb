# frozen_string_literal: true

module Shared
  # Canal de mensageria — publica os eventos da Saga (RFC-005) a cada mudança de status.
  class WorkOrderEventNotifier
    EVENTS = { awaiting_approval: "work_order.diagnosed" }.freeze

    def initialize(publisher:)
      @publisher = publisher
    end

    def notify_status_changed(work_order)
      event = EVENTS[work_order.status.value]
      @publisher.publish(event, payload(work_order)) if event
    rescue StandardError => e
      # shortcut: publicação best-effort após o commit — se o broker estiver fora, o evento
      # se perde; trocar por transactional outbox se isso aparecer na prática.
      Rails.logger.error("[WorkOrderEventNotifier] Failed to publish #{event}: #{e.message}")
    end

    private

    def payload(work_order)
      {
        work_order_id: work_order.id,
        protocol: work_order.protocol,
        customer_id: work_order.customer_id,
        vehicle_id: work_order.vehicle_id,
        line_items: work_order.line_items.map { |item| line_item_payload(item) }
      }
    end

    def line_item_payload(item)
      {
        id: item.id,
        item_type: item.item_type.to_s,
        reference_id: item.reference_id,
        name: item.name_snapshot,
        unit_price_cents: item.price_snapshot.cents,
        quantity: item.quantity
      }
    end
  end
end
