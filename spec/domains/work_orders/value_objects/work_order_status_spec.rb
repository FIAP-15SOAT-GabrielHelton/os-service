# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../app/domains/work_orders/value_objects/work_order_status"

describe WorkOrders::ValueObjects::WorkOrderStatus do
  describe ".new" do
    it "defaults to :received" do
      expect(described_class.new.value).to eq(:received)
    end

    it "accepts all known states" do
      described_class::STATES.each do |state|
        expect(described_class.new(state).value).to eq(state)
      end
    end

    it "rejects unknown states" do
      expect { described_class.new(:bogus) }.to raise_error(ArgumentError, /Invalid status/)
    end
  end

  describe "#can_transition_to?" do
    it "allows received → diagnosing" do
      expect(described_class.new(:received).can_transition_to?(:diagnosing)).to be true
    end

    it "allows received → rejected" do
      expect(described_class.new(:received).can_transition_to?(:rejected)).to be true
    end

    it "allows diagnosing → awaiting_approval" do
      expect(described_class.new(:diagnosing).can_transition_to?(:awaiting_approval)).to be true
    end

    it "allows awaiting_approval → approved" do
      expect(described_class.new(:awaiting_approval).can_transition_to?(:approved)).to be true
    end

    it "allows approved → in_progress" do
      expect(described_class.new(:approved).can_transition_to?(:in_progress)).to be true
    end

    it "allows in_progress → completed" do
      expect(described_class.new(:in_progress).can_transition_to?(:completed)).to be true
    end

    it "rejects received → in_progress (skipping diagnosis)" do
      expect(described_class.new(:received).can_transition_to?(:in_progress)).to be false
    end

    it "allows cancelling from awaiting_approval, approved and in_progress (saga compensation)" do
      %i[awaiting_approval approved in_progress].each do |state|
        expect(described_class.new(state).can_transition_to?(:cancelled)).to be true
      end
    end

    it "does not allow cancelling a completed work order, and cancelled is terminal" do
      expect(described_class.new(:completed).can_transition_to?(:cancelled)).to be false
      expect(described_class.new(:cancelled).terminal?).to be true
    end

    it "rejects approved → rejected (customer cannot un-approve after committing)" do
      expect(described_class.new(:approved).can_transition_to?(:rejected)).to be false
    end

    it "rejects in_progress → rejected (can't reject while executing)" do
      expect(described_class.new(:in_progress).can_transition_to?(:rejected)).to be false
    end

    it "rejects any transition from completed (terminal)" do
      expect(described_class.new(:completed).can_transition_to?(:in_progress)).to be false
    end

    it "rejects any transition from rejected (terminal)" do
      expect(described_class.new(:rejected).can_transition_to?(:in_progress)).to be false
    end
  end

  describe "#transition_to" do
    it "returns a new status when valid" do
      status = described_class.new(:received)

      new_status = status.transition_to(:diagnosing)

      expect(new_status.value).to eq(:diagnosing)
      expect(status.value).to eq(:received)
    end

    it "raises on invalid transition" do
      status = described_class.new(:received)

      expect { status.transition_to(:completed) }.to raise_error(/Invalid transition/)
    end
  end

  describe "#terminal?" do
    it "returns true for delivered" do
      expect(described_class.new(:delivered).terminal?).to be true
    end

    it "returns true for rejected" do
      expect(described_class.new(:rejected).terminal?).to be true
    end

    it "returns false for completed (can still transition to delivered)" do
      expect(described_class.new(:completed).terminal?).to be false
    end

    it "returns false for intermediate states" do
      expect(described_class.new(:received).terminal?).to be false
      expect(described_class.new(:in_progress).terminal?).to be false
    end
  end

  describe "equality" do
    it "is equal when values match" do
      a = described_class.new(:received)
      b = described_class.new(:received)

      expect(a).to eq(b)
    end

    it "is not equal when values differ" do
      expect(described_class.new(:received)).not_to eq(described_class.new(:diagnosing))
    end
  end
end
