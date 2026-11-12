# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::WorkOrders", type: :request do
  let(:customer_params) do
    {
      person_type: "individual",
      document: "52998224725",
      name: "John Doe",
      email: "john@example.com",
      phone: "+5511999999999",
      address: {
        zip_code: "01310100",
        street: "Av. Paulista",
        number: "1000",
        city: "São Paulo",
        state: "SP"
      }
    }
  end

  let(:vehicle_params) do
    {
      license_plate: "ABC1D23",
      make: "Honda",
      model: "Civic",
      year: 2020,
      color: "black"
    }
  end

  def create_customer
    post "/api/v1/customers", params: customer_params, headers: auth_headers, as: :json
    response.parsed_body["id"]
  end

  def create_vehicle(customer_id)
    post "/api/v1/vehicles", params: vehicle_params.merge(customer_id: customer_id), headers: auth_headers, as: :json
    response.parsed_body["id"]
  end

  describe "POST /api/v1/work_orders" do
    it "creates a work order with valid references" do
      customer_id = create_customer
      vehicle_id = create_vehicle(customer_id)

      post "/api/v1/work_orders",
           params: {
             customer_id: customer_id,
             vehicle_id: vehicle_id,
             problem_description: "Engine noise"
           },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["status"]).to eq("received")
      expect(body["problem_description"]).to eq("Engine noise")
      expect(body["line_items"]).to eq([])
    end

    it "creates a work order already with line_items, starting in diagnosing" do
      customer_id = create_customer
      vehicle_id = create_vehicle(customer_id)
      service_id = create_service
      item_id = create_inventory_item

      create_work_order_with_line_items(customer_id, vehicle_id, [
        { item_type: "service", reference_id: service_id, quantity: 1 },
        { item_type: "part", reference_id: item_id, quantity: 2 }
      ])

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["status"]).to eq("diagnosing")
      expect(body["line_items"].size).to eq(2)
      expect(body["line_items"].map { |li| li["item_type"] }).to contain_exactly("service", "part")
    end

    it "returns 422 when customer does not exist" do
      customer_id = create_customer
      vehicle_id = create_vehicle(customer_id)

      post "/api/v1/work_orders",
           params: { customer_id: 999_999, vehicle_id: vehicle_id, problem_description: "x" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("Customer not found")
    end

    it "returns 422 when vehicle does not exist" do
      customer_id = create_customer

      post "/api/v1/work_orders",
           params: { customer_id: customer_id, vehicle_id: 999_999, problem_description: "x" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("Vehicle not found")
    end

    it "returns 422 when problem_description is missing" do
      customer_id = create_customer
      vehicle_id = create_vehicle(customer_id)

      post "/api/v1/work_orders",
           params: { customer_id: customer_id, vehicle_id: vehicle_id },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/v1/work_orders/:id" do
    it "returns the work order" do
      customer_id = create_customer
      vehicle_id = create_vehicle(customer_id)
      post "/api/v1/work_orders",
           params: { customer_id: customer_id, vehicle_id: vehicle_id, problem_description: "x" },
           headers: auth_headers, as: :json
      wo_id = response.parsed_body["id"]

      get "/api/v1/work_orders/#{wo_id}", headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(wo_id)
    end

    it "returns 404 when work order not found" do
      get "/api/v1/work_orders/999999", headers: auth_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  def create_service(**overrides)
    base = { name: "Oil Change", description: "Full oil change", base_price: 5000, estimated_duration_minutes: 30 }
    post "/api/v1/services", params: base.merge(overrides), headers: auth_headers, as: :json
    response.parsed_body["id"]
  end

  def create_inventory_item(**overrides)
    base = { name: "Brake Pad", code: "BP-001", unit_price: 2000, quantity: 5 }
    post "/api/v1/inventory_items", params: base.merge(overrides), headers: auth_headers, as: :json
    response.parsed_body["id"]
  end

  def create_work_order(customer_id, vehicle_id)
    post "/api/v1/work_orders",
         params: { customer_id: customer_id, vehicle_id: vehicle_id, problem_description: "x" },
         headers: auth_headers, as: :json
    response.parsed_body["id"]
  end

  def create_work_order_with_line_items(customer_id, vehicle_id, line_items)
    post "/api/v1/work_orders",
         params: {
           customer_id: customer_id, vehicle_id: vehicle_id,
           problem_description: "Engine noise", line_items: line_items
         },
         headers: auth_headers, as: :json
  end

  describe "POST /api/v1/work_orders/:id/line_items" do
    it "adds a service line item with current price as snapshot" do
      customer_id = create_customer
      vehicle_id = create_vehicle(customer_id)
      wo_id = create_work_order(customer_id, vehicle_id)
      service_id = create_service
      patch "/api/v1/work_orders/#{wo_id}/assign", params: { mechanic_id: default_test_mechanic.id }, headers: auth_headers, as: :json

      post "/api/v1/work_orders/#{wo_id}/line_items",
           params: { item_type: "service", reference_id: service_id, quantity: 1 },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      item = response.parsed_body["line_items"].last
      expect(item["item_type"]).to eq("service")
      expect(item["name_snapshot"]).to eq("Oil Change")
      expect(item["price_snapshot"]).to eq("R$ 50.00")
    end

    it "adds a part line item from inventory" do
      customer_id = create_customer
      vehicle_id = create_vehicle(customer_id)
      wo_id = create_work_order(customer_id, vehicle_id)
      item_id = create_inventory_item
      patch "/api/v1/work_orders/#{wo_id}/assign", params: { mechanic_id: default_test_mechanic.id }, headers: auth_headers, as: :json

      post "/api/v1/work_orders/#{wo_id}/line_items",
           params: { item_type: "part", reference_id: item_id, quantity: 2 },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      item = response.parsed_body["line_items"].last
      expect(item["item_type"]).to eq("part")
      expect(item["price_snapshot"]).to eq("R$ 20.00")
    end

    it "preserves price snapshot after catalog price change" do
      customer_id = create_customer
      vehicle_id = create_vehicle(customer_id)
      wo_id = create_work_order(customer_id, vehicle_id)
      service_id = create_service
      patch "/api/v1/work_orders/#{wo_id}/assign", params: { mechanic_id: default_test_mechanic.id }, headers: auth_headers, as: :json

      post "/api/v1/work_orders/#{wo_id}/line_items",
           params: { item_type: "service", reference_id: service_id, quantity: 1 },
           headers: auth_headers, as: :json
      patch "/api/v1/services/#{service_id}", params: { base_price: 9000 }, headers: auth_headers, as: :json

      get "/api/v1/work_orders/#{wo_id}", headers: auth_headers, as: :json

      item = response.parsed_body["line_items"].last
      expect(item["price_snapshot"]).to eq("R$ 50.00")
    end

    it "returns 422 when work order is still in received" do
      customer_id = create_customer
      vehicle_id = create_vehicle(customer_id)
      wo_id = create_work_order(customer_id, vehicle_id)
      service_id = create_service

      post "/api/v1/work_orders/#{wo_id}/line_items",
           params: { item_type: "service", reference_id: service_id, quantity: 1 },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/work_orders/:id/diagnose" do
    it "returns 403 forbidden when accessed by a customer" do
      customer_id = create_customer
      vehicle_id = create_vehicle(customer_id)
      wo_id = create_work_order(customer_id, vehicle_id)

      patch "/api/v1/work_orders/#{wo_id}/diagnose", headers: customer_auth_headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "moves to awaiting_approval after items are added" do
      customer_id = create_customer
      vehicle_id = create_vehicle(customer_id)
      wo_id = create_work_order(customer_id, vehicle_id)
      service_id = create_service
      patch "/api/v1/work_orders/#{wo_id}/assign", params: { mechanic_id: default_test_mechanic.id }, headers: auth_headers, as: :json
      post "/api/v1/work_orders/#{wo_id}/line_items",
           params: { item_type: "service", reference_id: service_id, quantity: 1 },
           headers: auth_headers, as: :json

      patch "/api/v1/work_orders/#{wo_id}/diagnose", headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("awaiting_approval")
    end

    it "returns 422 when there are no line items" do
      customer_id = create_customer
      vehicle_id = create_vehicle(customer_id)
      wo_id = create_work_order(customer_id, vehicle_id)
      patch "/api/v1/work_orders/#{wo_id}/assign", params: { mechanic_id: default_test_mechanic.id }, headers: auth_headers, as: :json

      patch "/api/v1/work_orders/#{wo_id}/diagnose", headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  def setup_approved_work_order
    customer_id = create_customer
    vehicle_id = create_vehicle(customer_id)
    wo_id = create_work_order(customer_id, vehicle_id)
    service_id = create_service
    patch "/api/v1/work_orders/#{wo_id}/assign", params: { mechanic_id: default_test_mechanic.id }, headers: auth_headers, as: :json
    post "/api/v1/work_orders/#{wo_id}/line_items",
         params: { item_type: "service", reference_id: service_id, quantity: 1 }, headers: auth_headers, as: :json
    patch "/api/v1/work_orders/#{wo_id}/diagnose", headers: auth_headers, as: :json
    approve_via_event(wo_id)
    { wo_id: wo_id, vehicle_id: vehicle_id }
  end

  describe "saga driven by the other services' events" do
    it "goes approved -> in_progress -> completed and can then be delivered" do
      wo_id = setup_approved_work_order[:wo_id]
      get "/api/v1/work_orders/#{wo_id}", headers: auth_headers, as: :json
      line_item_id = response.parsed_body["line_items"].first["id"]

      start_execution_via_event(wo_id)
      Messaging::EventHandlers.build.fetch("execution.completed").call(
        { "work_order_id" => wo_id,
          "items" => [ { "line_item_id" => line_item_id, "started_at" => "2026-11-12T10:00:00Z",
                         "finished_at" => "2026-11-12T10:45:00Z" } ] }
      )
      patch "/api/v1/work_orders/#{wo_id}/deliver", headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("status" => "delivered", "total_execution_time_minutes" => 45.0)
    end
  end

  describe "PATCH /api/v1/work_orders/:id/reject" do
    it "rejects a work order in received status" do
      customer_id = create_customer
      vehicle_id = create_vehicle(customer_id)
      wo_id = create_work_order(customer_id, vehicle_id)

      patch "/api/v1/work_orders/#{wo_id}/reject", headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("rejected")
    end

    it "rejects a work order in diagnosing status" do
      customer_id = create_customer
      vehicle_id = create_vehicle(customer_id)
      wo_id = create_work_order(customer_id, vehicle_id)
      patch "/api/v1/work_orders/#{wo_id}/assign", params: { mechanic_id: default_test_mechanic.id }, headers: auth_headers, as: :json

      patch "/api/v1/work_orders/#{wo_id}/reject", headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("rejected")
    end

    it "returns 422 when rejecting from an invalid status (in_progress)" do
      result = setup_approved_work_order
      wo_id  = result[:wo_id]
      start_execution_via_event(wo_id)

      patch "/api/v1/work_orders/#{wo_id}/reject", headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
