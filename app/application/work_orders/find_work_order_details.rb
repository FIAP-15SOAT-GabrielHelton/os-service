# frozen_string_literal: true

require_relative "../shared/result"
require_relative "../shared/use_case"

module WorkOrders
  class FindWorkOrderDetails < Shared::UseCase
    def initialize(work_order_repository:, customer_repository:, vehicle_repository:)
      @work_order_repository = work_order_repository
      @customer_repository = customer_repository
      @vehicle_repository = vehicle_repository
    end

    private

    def perform(id:)
      work_order = @work_order_repository.find(id)
      return Shared::Result.failure("Work order not found") unless work_order

      Shared::Result.success(
        work_order: work_order,
        customer: @customer_repository.find(work_order.customer_id),
        vehicle: @vehicle_repository.find(work_order.vehicle_id)
      )
    end
  end
end
