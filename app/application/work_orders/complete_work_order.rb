# frozen_string_literal: true

require_relative "../shared/result"
require_relative "../shared/use_case"
require_relative "../shared/work_order_notifier"

module WorkOrders
  # Disparado pelo evento execution.completed.
  class CompleteWorkOrder < Shared::UseCase
    def initialize(work_order_repository:, notifier: Shared::NullNotifier.new)
      @repository = work_order_repository
      @notifier = notifier
    end

    private

    # items: horários de cada serviço, como enviados pelo execution-service.
    def perform(id:, items:)
      work_order = @repository.find(id)
      return Shared::Result.failure("Work order not found") unless work_order

      items.each { |item| record_service_times(work_order, item) }
      work_order.complete
      saved = @repository.save(work_order)
      @notifier.notify_status_changed(saved)
      Shared::Result.success(saved)
    end

    def record_service_times(work_order, item)
      line_item = work_order.line_items.find { |li| li.id == item.fetch("line_item_id") }
      raise "Line item #{item['line_item_id']} not found in work order #{work_order.id}" unless line_item

      line_item.start!(Time.zone.parse(item.fetch("started_at")))
      line_item.finish!(Time.zone.parse(item.fetch("finished_at")))
    end
  end
end
