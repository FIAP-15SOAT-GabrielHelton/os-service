# frozen_string_literal: true

module Api
  module V1
    class WorkOrdersController < Api::V1::ApplicationController
      before_action :require_staff!, only: %i[reject add_line_item]
      before_action :require_receptionist!, only: %i[assign deliver]
      before_action :require_mechanic!, only: %i[diagnose]

      def index
        result = list_work_orders.call(**list_params)

        render json: {
          data: result.value[:entries].map { |wo| WorkOrders::Presenters::WorkOrder.call(wo) },
          pagination: {
            page: result.value[:page],
            per_page: result.value[:per_page],
            total: result.value[:total],
            total_pages: result.value[:total_pages]
          }
        }
      end

      def show
        result = find_work_order_details.call(id: params[:id], authorization: request.headers["Authorization"])

        if result.success?
          return render_forbidden if forbidden_for_customer?(result.value[:work_order].customer_id)

          render json: WorkOrders::Presenters::Details.call(result.value)
        else
          render json: { error: result.error }, status: :not_found
        end
      end

      def create
        result = create_work_order.call(**create_params)

        if result.success?
          render json: WorkOrders::Presenters::WorkOrder.call(result.value), status: :created
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      def assign
        result = assign_work_order.call(id: params[:id], mechanic_id: params[:mechanic_id])

        if result.success?
          render json: WorkOrders::Presenters::WorkOrder.call(result.value)
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      def add_line_item
        result = add_line_item_use_case.call(
          work_order_id: params[:id],
          item_type: params[:item_type],
          reference_id: params[:reference_id],
          quantity: params[:quantity]
        )

        if result.success?
          render json: WorkOrders::Presenters::WorkOrder.call(result.value), status: :created
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      def diagnose
        result = diagnose_work_order.call(id: params[:id])

        if result.success?
          render json: WorkOrders::Presenters::WorkOrder.call(result.value)
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      def reject
        result = reject_work_order.call(id: params[:id])

        if result.success?
          render json: WorkOrders::Presenters::WorkOrder.call(result.value)
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      def deliver
        result = deliver_work_order.call(id: params[:id])

        if result.success?
          render json: WorkOrders::Presenters::WorkOrder.call(result.value)
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      private

      def work_order_repository
        @work_order_repository ||= Persistence::WorkOrders::ActiveRecordWorkOrderRepository.new
      end

      def customer_repository
        @customer_repository ||= Persistence::Registrations::ActiveRecordCustomerRepository.new
      end

      def vehicle_repository
        @vehicle_repository ||= Persistence::Registrations::ActiveRecordVehicleRepository.new
      end

      def user_repository
        @user_repository ||= Persistence::Accounts::ActiveRecordUserRepository.new
      end

      def create_work_order
        WorkOrders::CreateWorkOrder.new(
          work_order_repository: work_order_repository,
          customer_repository: customer_repository,
          vehicle_repository: vehicle_repository,
          service_repository: Persistence::Registrations::ActiveRecordServiceRepository.new,
          inventory_item_repository: Persistence::Inventory::ActiveRecordInventoryItemRepository.new
        )
      end

      def find_work_order_details
        WorkOrders::FindWorkOrderDetails.new(
          work_order_repository: work_order_repository,
          customer_repository: customer_repository,
          vehicle_repository: vehicle_repository,
          billing_client: Integrations::BillingClient.new
        )
      end

      def list_work_orders
        WorkOrders::ListWorkOrders.new(work_order_repository: work_order_repository)
      end

      def assign_work_order
        WorkOrders::AssignWorkOrder.new(
          work_order_repository: work_order_repository,
          user_repository: user_repository
        )
      end

      def diagnose_work_order
        WorkOrders::DiagnoseWorkOrder.new(
          work_order_repository: work_order_repository,
          notifier: notifier
        )
      end

      def add_line_item_use_case
        WorkOrders::AddLineItem.new(
          work_order_repository: work_order_repository,
          service_repository: Persistence::Registrations::ActiveRecordServiceRepository.new,
          inventory_item_repository: Persistence::Inventory::ActiveRecordInventoryItemRepository.new
        )
      end

      def reject_work_order
        WorkOrders::RejectWorkOrder.new(work_order_repository: work_order_repository)
      end

      def deliver_work_order
        WorkOrders::DeliverWorkOrder.new(work_order_repository: work_order_repository, notifier: notifier)
      end

      def notifier
        @notifier ||= Shared::WorkOrderNotifier.new(
          notifiers: [
            Shared::WorkOrderEmailNotifier.new(customer_repository: customer_repository),
            Shared::WorkOrderMetricsNotifier.new,
            (Shared::WorkOrderEventNotifier.new(publisher: Messaging::RabbitmqPublisher.new) if ENV["RABBITMQ_URL"])
          ].compact
        )
      end

      def create_params
        p = params.permit(:customer_id, :vehicle_id, :problem_description,
                          line_items: [ :item_type, :reference_id, :quantity ])
                  .to_h.deep_symbolize_keys
        p[:customer_id] = current_customer.id if customer?
        p
      end

      def list_params
        p = params.permit(:status, :customer_id, :mechanic_id, :start_date, :end_date, :page, :per_page)
                  .to_h.symbolize_keys
        p[:customer_id] = current_customer.id if customer?
        p
      end
    end
  end
end
