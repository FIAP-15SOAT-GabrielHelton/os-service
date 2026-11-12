# frozen_string_literal: true

require_relative "../shared/result"
require_relative "../shared/use_case"

module WorkOrders
  # Disparado pelo evento execution.started.
  class ExecuteService < Shared::UseCase
    def initialize(work_order_repository:)
      @repository = work_order_repository
    end

    private

    def perform(id:)
      work_order = @repository.find(id)
      return Shared::Result.failure("Work order not found") unless work_order

      work_order.execute
      Shared::Result.success(@repository.save(work_order))
    end
  end
end
