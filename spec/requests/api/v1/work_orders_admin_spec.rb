# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::WorkOrders admin views", type: :request do
  let(:customer_params) do
    {
      person_type: "individual", document: "52998224725", name: "John",
      email: "j@e.com", phone: "+5511999999999",
      address: { zip_code: "01310100", street: "Av. Paulista", number: "1000",
                 city: "São Paulo", state: "SP" }
    }
  end
  let(:vehicle_params) do
    { license_plate: "ABC1D23", make: "Honda", model: "Civic",
      year: 2020, color: "black" }
  end
  let(:service_params) do
    { name: "Oil Change", description: "Full oil change", base_price: 5000, estimated_duration_minutes: 30 }
  end
  let(:inventory_params) { { name: "Brake Pad", code: "BP-01", unit_price: 2000, quantity: 5 } }

  def create_diagnosed_work_order
    post "/api/v1/customers", params: customer_params, headers: auth_headers, as: :json
    customer_id = response.parsed_body["id"]
    post "/api/v1/vehicles", params: vehicle_params.merge(customer_id: customer_id),
                             headers: auth_headers, as: :json
    vehicle_id = response.parsed_body["id"]
    post "/api/v1/services", params: service_params, headers: auth_headers, as: :json
    service_id = response.parsed_body["id"]
    post "/api/v1/inventory_items", params: inventory_params, headers: auth_headers, as: :json
    item_id = response.parsed_body["id"]
    post "/api/v1/work_orders",
         params: { customer_id: customer_id, vehicle_id: vehicle_id, problem_description: "Engine noise" },
         headers: auth_headers, as: :json
    wo_id = response.parsed_body["id"]
    patch "/api/v1/work_orders/#{wo_id}/assign", params: { mechanic_id: default_test_mechanic.id }, headers: auth_headers, as: :json
    post "/api/v1/work_orders/#{wo_id}/line_items",
         params: { item_type: "service", reference_id: service_id, quantity: 1 },
         headers: auth_headers, as: :json
    post "/api/v1/work_orders/#{wo_id}/line_items",
         params: { item_type: "part", reference_id: item_id, quantity: 1 },
         headers: auth_headers, as: :json
    patch "/api/v1/work_orders/#{wo_id}/diagnose", headers: auth_headers, as: :json
    { id: wo_id, customer_id: customer_id }
  end

  describe "GET /api/v1/work_orders" do
    it "requires authentication" do
      get "/api/v1/work_orders", as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns paginated work orders" do
      create_diagnosed_work_order

      get "/api/v1/work_orders", headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["data"].size).to eq(1)
      expect(body["pagination"]).to include("page" => 1, "per_page" => 20, "total" => 1, "total_pages" => 1)
    end

    it "filters by status" do
      create_diagnosed_work_order

      get "/api/v1/work_orders", params: { status: "received" }, headers: auth_headers
      expect(response.parsed_body["data"]).to be_empty

      get "/api/v1/work_orders", params: { status: "awaiting_approval" }, headers: auth_headers
      expect(response.parsed_body["data"].size).to eq(1)
    end

    it "filters by customer_id" do
      wo = create_diagnosed_work_order

      get "/api/v1/work_orders", params: { customer_id: wo[:customer_id] }, headers: auth_headers
      expect(response.parsed_body["data"].size).to eq(1)

      get "/api/v1/work_orders", params: { customer_id: 999_999 }, headers: auth_headers
      expect(response.parsed_body["data"]).to be_empty
    end

    it "filters by mechanic_id" do
      create_diagnosed_work_order

      get "/api/v1/work_orders", params: { mechanic_id: default_test_mechanic.id }, headers: auth_headers
      expect(response.parsed_body["data"].size).to eq(1)

      get "/api/v1/work_orders", params: { mechanic_id: 999 }, headers: auth_headers
      expect(response.parsed_body["data"]).to be_empty
    end

    it "respects per_page" do
      create_diagnosed_work_order

      get "/api/v1/work_orders", params: { per_page: 5 }, headers: auth_headers

      expect(response.parsed_body["pagination"]["per_page"]).to eq(5)
    end
  end

  describe "GET /api/v1/work_orders/:id (enriched)" do
    it "returns work order with embedded customer, vehicle and the quote composed from billing" do
      wo = create_diagnosed_work_order
      billing = instance_double(Integrations::BillingClient)
      allow(Integrations::BillingClient).to receive(:new).and_return(billing)
      allow(billing).to receive(:quote_for).with(wo[:id], authorization: auth_headers["Authorization"])
                                           .and_return({ "id" => 5, "status" => "created" })

      get "/api/v1/work_orders/#{wo[:id]}", headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include(
        "id" => wo[:id],
        "customer" => hash_including("name" => "John"),
        "vehicle" => hash_including("license_plate" => "ABC1D23"),
        "quote" => { "id" => 5, "status" => "created" }
      )
      expect(body["line_items"].size).to eq(2)
    end

    it "returns 404 for unknown id" do
      get "/api/v1/work_orders/999999", headers: auth_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
