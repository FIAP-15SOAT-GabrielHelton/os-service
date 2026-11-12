# frozen_string_literal: true

# Simula a chegada dos eventos do billing-service, sem broker.
module SagaHelpers
  def approve_via_event(work_order_id)
    Messaging::EventHandlers.build.fetch("quote.approved").call({ "work_order_id" => work_order_id })
  end
end

RSpec.configure do |config|
  config.include SagaHelpers, type: :request
end
