# frozen_string_literal: true

require_relative "../shared/result"
require_relative "../shared/use_case"
require_relative "../shared/work_order_notifier"

module WorkOrders
  # Disparado pelo evento payment.approved: libera a entrega.
  class PayWorkOrder < Shared::UseCase
    def initialize(work_order_repository:, notifier: Shared::NullNotifier.new)
      @repository = work_order_repository
      @notifier = notifier
    end

    private

    def perform(id:)
      work_order = @repository.find(id)
      return Shared::Result.failure("Work order not found") unless work_order

      # Idempotência: o Mercado Pago pode notificar o mesmo pagamento mais de uma vez.
      return Shared::Result.success(work_order) if work_order.paid? || work_order.delivered?

      work_order.pay
      saved = @repository.save(work_order)
      @notifier.notify_status_changed(saved)
      Shared::Result.success(saved)
    end
  end
end
