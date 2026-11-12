# frozen_string_literal: true

require "rails_helper"

RSpec.describe Messaging::RabbitmqPublisher do
  let(:exchange) { double("exchange", publish: nil) } # rubocop:disable RSpec/VerifiedDoubles
  let(:channel) { double("channel", topic: exchange, close: nil) } # rubocop:disable RSpec/VerifiedDoubles
  let(:connection) { double("connection", create_channel: channel) } # rubocop:disable RSpec/VerifiedDoubles

  it "publishes a persistent JSON envelope routed by event name and closes the channel" do
    described_class.new(connection: connection).publish("work_order.diagnosed", { work_order_id: 1 })

    expect(channel).to have_received(:topic).with("oficina.events", durable: true)
    expect(exchange).to have_received(:publish) do |body, options|
      expect(JSON.parse(body)).to include("event" => "work_order.diagnosed", "data" => { "work_order_id" => 1 })
      expect(options).to include(routing_key: "work_order.diagnosed", persistent: true)
    end
    expect(channel).to have_received(:close)
  end
end
