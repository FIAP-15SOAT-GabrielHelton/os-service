# frozen_string_literal: true

require_relative "../shared/result"
require_relative "../shared/use_case"
require_relative "../shared/work_order_notifier"

module WorkOrders
  # Compensação da Saga (RFC-005): cancela a OS e, se as peças já tinham sido
  # baixadas na aprovação, devolve ao estoque. A notificação publica
  # work_order.cancelled, que faz o billing-service cancelar o orçamento.
  class CancelWorkOrder < Shared::UseCase
    def initialize(work_order_repository:, add_quantity:, notifier: Shared::NullNotifier.new)
      @repository = work_order_repository
      @add_quantity = add_quantity
      @notifier = notifier
    end

    private

    def perform(id:)
      work_order = @repository.find(id)
      return Shared::Result.failure("Work order not found") unless work_order

      stock_was_taken = work_order.approved? || work_order.in_progress?
      saved = ActiveRecord::Base.transaction do
        work_order.cancel
        @repository.save(work_order).tap { |wo| restore_parts(wo.line_items) if stock_was_taken }
      end

      @notifier.notify_status_changed(saved)
      Shared::Result.success(saved)
    end

    def restore_parts(line_items)
      line_items.select(&:part?).each do |item|
        result = @add_quantity.call(id: item.reference_id, amount: item.quantity)
        raise result.error unless result.success?
      end
    end
  end
end
