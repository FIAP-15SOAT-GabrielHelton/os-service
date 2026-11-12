# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkOrders::CompleteWorkOrder do
  let(:service) do
    WorkOrders::LineItem.new(id: 1, item_type: :service, reference_id: 1, name_snapshot: "Oil",
                             price_snapshot: 5_000, quantity: 1)
  end
  let(:work_order) do
    WorkOrders::WorkOrder.new(id: 1, customer_id: 10, vehicle_id: 20, problem_description: "x",
                              status: :in_progress, line_items: [ service ])
  end
  let(:repository) do
    double("WorkOrderRepository").tap do |repo| # rubocop:disable RSpec/VerifiedDoubles
      allow(repo).to receive(:find).with(1).and_return(work_order)
      allow(repo).to receive(:find).with(999).and_return(nil)
      allow(repo).to receive(:save) { |wo| wo }
    end
  end
  let(:notifier) { double("notifier", notify_status_changed: nil) } # rubocop:disable RSpec/VerifiedDoubles
  let(:use_case) { described_class.new(work_order_repository: repository, notifier: notifier) }
  let(:items) do
    [ { "line_item_id" => 1, "started_at" => "2026-11-12T10:00:00Z", "finished_at" => "2026-11-12T10:30:00Z" } ]
  end

  it "records the service times reported by execution-service and completes the work order" do
    result = use_case.call(id: 1, items: items)

    expect(result.value.completed?).to be true
    expect(result.value.total_execution_time_minutes).to eq(30.0)
    expect(notifier).to have_received(:notify_status_changed).with(work_order)
  end

  it "fails when the work order does not exist" do
    expect(use_case.call(id: 999, items: items)).to be_failure
  end

  it "fails when a service of the work order has no reported times" do
    expect(use_case.call(id: 1, items: []).error).to match(/All services/)
  end

  it "fails when the event references an unknown line item" do
    result = use_case.call(id: 1, items: [ items.first.merge("line_item_id" => 99) ])

    expect(result.error).to match(/Line item 99 not found/)
  end
end
