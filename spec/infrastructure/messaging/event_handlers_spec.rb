# frozen_string_literal: true

require "rails_helper"

RSpec.describe Messaging::EventHandlers do
  let(:use_case) { double("use_case", call: Shared::Result.success) } # rubocop:disable RSpec/VerifiedDoubles

  it "approves the work order on quote.approved" do
    allow(WorkOrders::ApproveWorkOrder).to receive(:new).and_return(use_case)

    described_class.build.fetch("quote.approved").call({ "work_order_id" => 42 })

    expect(use_case).to have_received(:call).with(id: 42)
  end

  it "rejects the work order on quote.rejected" do
    allow(WorkOrders::RejectWorkOrder).to receive(:new).and_return(use_case)

    described_class.build.fetch("quote.rejected").call({ "work_order_id" => 42 })

    expect(use_case).to have_received(:call).with(id: 42)
  end

  it "starts the work order on execution.started" do
    allow(WorkOrders::ExecuteService).to receive(:new).and_return(use_case)

    described_class.build.fetch("execution.started").call({ "work_order_id" => 42 })

    expect(use_case).to have_received(:call).with(id: 42)
  end

  it "completes the work order on execution.completed, passing the service times" do
    allow(WorkOrders::CompleteWorkOrder).to receive(:new).and_return(use_case)

    described_class.build.fetch("execution.completed").call({ "work_order_id" => 42, "items" => [ { "line_item_id" => 1 } ] })

    expect(use_case).to have_received(:call).with(id: 42, items: [ { "line_item_id" => 1 } ])
  end

  it "cancels the work order on execution.failed" do
    allow(WorkOrders::CancelWorkOrder).to receive(:new).and_return(use_case)

    described_class.build.fetch("execution.failed").call({ "work_order_id" => 42, "reason" => "x" })

    expect(use_case).to have_received(:call).with(id: 42)
  end

  it "raises when the use case fails so the message is not acked" do
    expect { described_class.build.fetch("quote.approved").call({ "work_order_id" => 999_999 }) }
      .to raise_error(RuntimeError, /not found/)
  end
end
