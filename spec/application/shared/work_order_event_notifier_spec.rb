# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shared::WorkOrderEventNotifier do
  let(:publisher) { double("publisher", publish: nil) } # rubocop:disable RSpec/VerifiedDoubles
  let(:notifier) { described_class.new(publisher: publisher) }
  let(:line_item) do
    WorkOrders::LineItem.new(id: 5, item_type: :part, reference_id: 7, name_snapshot: "Oil filter",
                             price_snapshot: Shared::Money.new(cents: 4_500), quantity: 2)
  end

  def work_order(status:)
    WorkOrders::WorkOrder.new(id: 1, customer_id: 10, vehicle_id: 20, problem_description: "Engine noise",
                              status: status, protocol: "ABC12345", line_items: [ line_item ])
  end

  it "publishes work_order.diagnosed with items and prices when awaiting approval" do
    notifier.notify_status_changed(work_order(status: :awaiting_approval))

    expect(publisher).to have_received(:publish).with(
      "work_order.diagnosed",
      { work_order_id: 1, protocol: "ABC12345", customer_id: 10, vehicle_id: 20,
        line_items: [ { id: 5, item_type: "part", reference_id: 7, name: "Oil filter",
                        unit_price_cents: 4_500, quantity: 2 } ] }
    )
  end

  it "publishes work_order.approved when approved" do
    notifier.notify_status_changed(work_order(status: :approved))

    expect(publisher).to have_received(:publish).with("work_order.approved", hash_including(work_order_id: 1))
  end

  it "does not publish for statuses without a saga event" do
    notifier.notify_status_changed(work_order(status: :diagnosing))

    expect(publisher).not_to have_received(:publish)
  end

  it "logs and swallows publisher failures" do
    allow(publisher).to receive(:publish).and_raise(StandardError, "broker down")
    allow(Rails.logger).to receive(:error)

    expect { notifier.notify_status_changed(work_order(status: :awaiting_approval)) }.not_to raise_error
    expect(Rails.logger).to have_received(:error).with(/broker down/)
  end
end
