# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::BillingClient do
  let(:client) { described_class.new(base_url: "http://billing:3000") }
  let(:http) { instance_double(Net::HTTP) }

  def stub_response(klass, body: "{}")
    response = klass.new("1.1", "200", "x")
    allow(response).to receive(:body).and_return(body)
    allow(http).to receive(:get).and_return(response)
    allow(Net::HTTP).to receive(:start).and_yield(http)
  end

  it "returns the quote, relaying the caller's token" do
    stub_response(Net::HTTPOK, body: { id: 5, status: "sent" }.to_json)

    expect(client.quote_for(42, authorization: "Bearer t")).to eq("id" => 5, "status" => "sent")
    expect(http).to have_received(:get).with("/api/v1/work_orders/42/quote", hash_including("Authorization" => "Bearer t"))
    expect(Net::HTTP).to have_received(:start).with("billing", 3000, hash_including(open_timeout: 1, read_timeout: 2))
  end

  it "returns nil when billing answers with an error (404, 403)" do
    stub_response(Net::HTTPNotFound)

    expect(client.quote_for(42, authorization: "Bearer t")).to be_nil
  end

  it "returns nil when billing is unreachable" do
    allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

    expect(client.quote_for(42, authorization: "Bearer t")).to be_nil
  end

  it "does not call billing without a base URL or token" do
    allow(Net::HTTP).to receive(:start)

    expect(described_class.new(base_url: nil).quote_for(42, authorization: "Bearer t")).to be_nil
    expect(client.quote_for(42, authorization: nil)).to be_nil
    expect(Net::HTTP).not_to have_received(:start)
  end
end
