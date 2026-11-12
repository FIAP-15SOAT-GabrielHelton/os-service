# frozen_string_literal: true

require "rails_helper"

RSpec.describe Messaging::RabbitmqConsumer do
  let(:queue) { double("queue", bind: nil) } # rubocop:disable RSpec/VerifiedDoubles
  let(:channel) do
    double("channel", prefetch: nil, topic: :exchange, queue: queue, ack: nil, reject: nil) # rubocop:disable RSpec/VerifiedDoubles
  end
  let(:connection) { double("connection", create_channel: channel) } # rubocop:disable RSpec/VerifiedDoubles
  let(:received) { [] }
  let(:handlers) { { "work_order.diagnosed" => ->(data) { received << data } } }
  let(:consumer) { described_class.new(queue: "os-service", handlers: handlers, connection: connection) }

  def deliver(body:, redelivered: false)
    delivery = double("delivery", routing_key: "work_order.diagnosed", delivery_tag: 7, redelivered?: redelivered) # rubocop:disable RSpec/VerifiedDoubles
    allow(queue).to receive(:subscribe).and_yield(delivery, nil, body)
    consumer.start
  end

  it "binds the queue to each handled event and acks after handling" do
    deliver(body: { data: { "work_order_id" => 1 } }.to_json)

    expect(queue).to have_received(:bind).with(:exchange, routing_key: "work_order.diagnosed")
    expect(received).to eq([ { "work_order_id" => 1 } ])
    expect(channel).to have_received(:ack).with(7)
  end

  it "requeues once when the handler fails" do
    deliver(body: "not json")

    expect(channel).to have_received(:reject).with(7, true)
  end

  it "drops the message when it fails again after redelivery" do
    deliver(body: "not json", redelivered: true)

    expect(channel).to have_received(:reject).with(7, false)
  end
end
