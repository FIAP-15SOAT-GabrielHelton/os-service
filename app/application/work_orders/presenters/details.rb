# frozen_string_literal: true

module WorkOrders
  module Presenters
    module Details
      module_function

      def call(details)
        WorkOrder.call(details[:work_order]).merge(
          customer: customer(details[:customer]),
          vehicle: vehicle(details[:vehicle]),
          quote: details[:quote]
        )
      end

      def customer(customer)
        return nil unless customer

        {
          id: customer.id,
          name: customer.name,
          document: Registrations::Presenters::Document.call(customer.document),
          email: customer.email,
          phone: customer.phone
        }
      end

      def vehicle(vehicle)
        return nil unless vehicle

        {
          id: vehicle.id,
          license_plate: vehicle.license_plate.value,
          make: vehicle.make,
          model: vehicle.model,
          year: vehicle.year,
          color: vehicle.color
        }
      end
    end
  end
end
