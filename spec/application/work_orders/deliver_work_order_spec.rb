# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkOrders::DeliverWorkOrder do
  let(:work_order) do
    WorkOrders::WorkOrder.new(
      id: 1, customer_id: 10, vehicle_id: 20,
      problem_description: "x", status: :paid
    )
  end

  let(:repository) do
    double("WorkOrderRepository").tap do |repo|
      allow(repo).to receive(:find).with(1).and_return(work_order)
      allow(repo).to receive(:find).with(999).and_return(nil)
      allow(repo).to receive(:save) { |wo| wo }
    end
  end

  let(:use_case) { described_class.new(work_order_repository: repository) }

  describe "#call (happy path)" do
    it "transitions paid → delivered" do
      result = use_case.call(id: 1)

      expect(result).to be_success
      expect(result.value.delivered?).to be true
      expect(result.value.delivered_at).not_to be_nil
    end
  end

  describe "#call (errors)" do
    it "returns failure when work order not found" do
      result = use_case.call(id: 999)

      expect(result).to be_failure
      expect(result.error).to eq("Work order not found")
    end

    it "returns failure when work order is not completed" do
      allow(repository).to receive(:find).with(1).and_return(
        WorkOrders::WorkOrder.new(id: 1, customer_id: 10, vehicle_id: 20,
                                   problem_description: "x", status: :in_progress)
      )

      result = use_case.call(id: 1)

      expect(result).to be_failure
      expect(result.error).to match(/Invalid transition/)
    end
  end
end
