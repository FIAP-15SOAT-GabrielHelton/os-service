# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkOrders::FindWorkOrderDetails do
  let(:work_order_repository) { instance_double(Persistence::WorkOrders::ActiveRecordWorkOrderRepository) }
  let(:customer_repository) { instance_double(Persistence::Registrations::ActiveRecordCustomerRepository) }
  let(:vehicle_repository) { instance_double(Persistence::Registrations::ActiveRecordVehicleRepository) }
  let(:use_case) do
    described_class.new(
      work_order_repository: work_order_repository,
      customer_repository: customer_repository,
      vehicle_repository: vehicle_repository
    )
  end
  let(:work_order) do
    WorkOrders::WorkOrder.new(id: 1, customer_id: 10, vehicle_id: 20, problem_description: "x")
  end

  it "returns failure when work order is missing" do
    allow(work_order_repository).to receive(:find).and_return(nil)

    result = use_case.call(id: 999)

    expect(result).to be_failure
    expect(result.error).to eq("Work order not found")
  end

  it "loads work_order, customer and vehicle" do
    customer = double("customer")
    vehicle = double("vehicle")
    allow(work_order_repository).to receive(:find).with(1).and_return(work_order)
    allow(customer_repository).to receive(:find).with(10).and_return(customer)
    allow(vehicle_repository).to receive(:find).with(20).and_return(vehicle)

    result = use_case.call(id: 1)

    expect(result).to be_success
    expect(result.value).to eq(work_order: work_order, customer: customer, vehicle: vehicle)
  end
end
