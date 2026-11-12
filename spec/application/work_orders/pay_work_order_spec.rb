# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkOrders::PayWorkOrder do
  let(:work_order) { instance_double(WorkOrders::WorkOrder, paid?: false, delivered?: false, pay: nil) }
  let(:repository) { instance_double(Persistence::WorkOrders::ActiveRecordWorkOrderRepository, find: work_order) }
  let(:notifier) { instance_double(Shared::WorkOrderNotifier, notify_status_changed: nil) }
  let(:use_case) { described_class.new(work_order_repository: repository, notifier: notifier) }

  before { allow(repository).to receive(:save).and_return(work_order) }

  it "marks the work order as paid and notifies" do
    expect(use_case.call(id: 1)).to be_success
    expect(work_order).to have_received(:pay)
    expect(notifier).to have_received(:notify_status_changed).with(work_order)
  end

  it "is idempotent when the payment event is delivered twice" do
    allow(work_order).to receive(:paid?).and_return(true)

    expect(use_case.call(id: 1)).to be_success
    expect(work_order).not_to have_received(:pay)
  end

  it "fails when the work order does not exist" do
    allow(repository).to receive(:find).and_return(nil)

    expect(use_case.call(id: 1).error).to eq("Work order not found")
  end
end
