# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkOrders::CancelWorkOrder do
  let(:part) do
    WorkOrders::LineItem.new(id: 1, item_type: :part, reference_id: 7, name_snapshot: "Oil filter",
                             price_snapshot: 4500, quantity: 2)
  end
  let(:service) do
    WorkOrders::LineItem.new(id: 2, item_type: :service, reference_id: 3, name_snapshot: "Oil change",
                             price_snapshot: 5000, quantity: 1)
  end
  let(:repository) do
    double("WorkOrderRepository").tap do |repo| # rubocop:disable RSpec/VerifiedDoubles
      allow(repo).to receive(:find).with(999).and_return(nil)
      allow(repo).to receive(:save) { |wo| wo }
    end
  end
  let(:add_quantity) { double("AddQuantity", call: Shared::Result.success) } # rubocop:disable RSpec/VerifiedDoubles
  let(:notifier) { double("notifier", notify_status_changed: nil) } # rubocop:disable RSpec/VerifiedDoubles
  let(:use_case) do
    described_class.new(work_order_repository: repository, add_quantity: add_quantity, notifier: notifier)
  end

  def stub_work_order(status)
    work_order = WorkOrders::WorkOrder.new(id: 1, customer_id: 10, vehicle_id: 20, problem_description: "x",
                                           status: status, line_items: [ part, service ])
    allow(repository).to receive(:find).with(1).and_return(work_order)
    work_order
  end

  %i[approved in_progress].each do |status|
    it "cancels a work order that is #{status} and returns its parts to stock" do
      work_order = stub_work_order(status)

      result = use_case.call(id: 1)

      expect(result.value.cancelled?).to be true
      expect(add_quantity).to have_received(:call).once.with(id: 7, amount: 2)
      expect(notifier).to have_received(:notify_status_changed).with(work_order)
    end
  end

  it "cancels a work order awaiting approval without touching stock (nothing was taken yet)" do
    stub_work_order(:awaiting_approval)

    expect(use_case.call(id: 1).value.cancelled?).to be true
    expect(add_quantity).not_to have_received(:call)
  end

  it "fails when the work order does not exist" do
    expect(use_case.call(id: 999)).to be_failure
  end

  it "fails for a work order that can no longer be cancelled" do
    stub_work_order(:completed)

    expect(use_case.call(id: 1).error).to match(/Invalid transition/)
    expect(notifier).not_to have_received(:notify_status_changed)
  end

  it "fails without notifying when the stock cannot be restored" do
    stub_work_order(:approved)
    allow(add_quantity).to receive(:call).and_return(Shared::Result.failure("Inventory item not found"))

    expect(use_case.call(id: 1).error).to eq("Inventory item not found")
    expect(notifier).not_to have_received(:notify_status_changed)
  end
end
