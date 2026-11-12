# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkOrders::ApproveWorkOrder do
  let(:part) do
    WorkOrders::LineItem.new(id: 1, item_type: :part, reference_id: 7, name_snapshot: "Oil filter",
                             price_snapshot: 4500, quantity: 2)
  end
  let(:service) do
    WorkOrders::LineItem.new(id: 2, item_type: :service, reference_id: 3, name_snapshot: "Oil change",
                             price_snapshot: 5000, quantity: 1)
  end
  let(:work_order) do
    WorkOrders::WorkOrder.new(id: 1, customer_id: 10, vehicle_id: 20, problem_description: "x",
                              status: :awaiting_approval, line_items: [ part, service ])
  end
  let(:repository) do
    double("WorkOrderRepository").tap do |repo| # rubocop:disable RSpec/VerifiedDoubles
      allow(repo).to receive(:find).with(1).and_return(work_order)
      allow(repo).to receive(:find).with(999).and_return(nil)
      allow(repo).to receive(:save) { |wo| wo }
    end
  end
  let(:decrease_quantity) { double("DecreaseQuantity", call: Shared::Result.success) } # rubocop:disable RSpec/VerifiedDoubles
  let(:notifier) { double("notifier", notify_status_changed: nil) } # rubocop:disable RSpec/VerifiedDoubles
  let(:cancel_work_order) { double("CancelWorkOrder", call: Shared::Result.success(:cancelled)) } # rubocop:disable RSpec/VerifiedDoubles
  let(:use_case) do
    described_class.new(work_order_repository: repository, decrease_quantity: decrease_quantity,
                        cancel_work_order: cancel_work_order, notifier: notifier)
  end

  it "approves the work order, decreases stock only for parts and notifies" do
    result = use_case.call(id: 1)

    expect(result.value.approved?).to be true
    expect(decrease_quantity).to have_received(:call).once.with(id: 7, amount: 2)
    expect(notifier).to have_received(:notify_status_changed).with(work_order)
  end

  it "fails when the work order does not exist" do
    expect(use_case.call(id: 999)).to be_failure
  end

  it "fails on an invalid transition without touching stock" do
    allow(repository).to receive(:find).with(1).and_return(
      WorkOrders::WorkOrder.new(id: 1, customer_id: 10, vehicle_id: 20, problem_description: "x")
    )

    expect(use_case.call(id: 1).error).to match(/Invalid transition/)
    expect(decrease_quantity).not_to have_received(:call)
  end

  it "cancels the work order instead of approving when stock is insufficient" do
    allow(decrease_quantity).to receive(:call).and_return(Shared::Result.failure("Insufficient stock"))

    result = use_case.call(id: 1)

    expect(result.value).to eq(:cancelled)
    expect(cancel_work_order).to have_received(:call).with(id: 1)
    expect(notifier).not_to have_received(:notify_status_changed)
  end
end
