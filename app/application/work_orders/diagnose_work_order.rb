# frozen_string_literal: true

require_relative "../shared/result"
require_relative "../shared/use_case"
require_relative "../shared/work_order_notifier"

module WorkOrders
  class DiagnoseWorkOrder < Shared::UseCase
    def initialize(work_order_repository:, notifier: Shared::NullNotifier.new)
      @repository = work_order_repository
      @notifier = notifier
    end

    private

    def perform(id:)
      work_order = @repository.find(id)
      return Shared::Result.failure("Work order not found") unless work_order

      work_order.diagnose
      saved = @repository.save(work_order)

      # O orçamento é gerado pelo billing-service ao receber work_order.diagnosed.
      @notifier.notify_status_changed(saved)
      Shared::Result.success(saved)
    end
  end
end
