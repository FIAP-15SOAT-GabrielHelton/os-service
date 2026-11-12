# frozen_string_literal: true

# Simula a chegada dos eventos dos outros serviços, sem broker.
module SagaHelpers
  def approve_via_event(work_order_id)
    Messaging::EventHandlers.build.fetch("quote.approved").call({ "work_order_id" => work_order_id })
  end

  def start_execution_via_event(work_order_id)
    Messaging::EventHandlers.build.fetch("execution.started").call({ "work_order_id" => work_order_id })
  end
end

RSpec.configure do |config|
  config.include SagaHelpers, type: :request
end
