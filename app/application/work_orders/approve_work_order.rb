# frozen_string_literal: true

require_relative "../shared/result"
require_relative "../shared/use_case"
require_relative "../shared/work_order_notifier"

module WorkOrders
  # Disparado pelo evento quote.approved: aprova a OS e baixa as peças do estoque.
  class ApproveWorkOrder < Shared::UseCase
    def initialize(work_order_repository:, decrease_quantity:, notifier: Shared::NullNotifier.new)
      @repository = work_order_repository
      @decrease_quantity = decrease_quantity
      @notifier = notifier
    end

    private

    def perform(id:)
      work_order = @repository.find(id)
      return Shared::Result.failure("Work order not found") unless work_order

      saved = ActiveRecord::Base.transaction do
        work_order.approve
        @repository.save(work_order).tap { |wo| decrement_parts(wo.line_items) }
      end

      @notifier.notify_status_changed(saved)
      Shared::Result.success(saved)
    end

    def decrement_parts(line_items)
      line_items.select(&:part?).each do |item|
        result = @decrease_quantity.call(id: item.reference_id, amount: item.quantity)
        raise result.error unless result.success?
      end
    end
  end
end
