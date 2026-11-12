# frozen_string_literal: true

module WorkOrderSteps
  def api(method, path, params = {})
    if method == :get
      get "/api/v1/#{path}", headers: auth_headers
    else
      send(method, "/api/v1/#{path}", params: params, headers: auth_headers, as: :json)
    end
    response.parsed_body
  end

  def saga_event(name, extra = {})
    Messaging::EventHandlers.build.fetch(name).call({ "work_order_id" => @work_order_id }.merge(extra))
  end

  step "um cliente com um veículo cadastrado" do
    # O publisher real precisa do broker; aqui só registramos o que seria publicado.
    @publisher = instance_double(Messaging::RabbitmqPublisher, publish: nil)
    allow(Messaging::RabbitmqPublisher).to receive(:new).and_return(@publisher)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("RABBITMQ_URL").and_return("amqp://test")

    @customer_id = api(:post, "customers", person_type: "individual", document: "52998224725", name: "Maria Silva",
                                           email: "maria@example.com", phone: "+5511999999999",
                                           address: { zip_code: "01310100", street: "Av. Paulista", number: "1000",
                                                      city: "São Paulo", state: "SP" })["id"]
    @vehicle_id = api(:post, "vehicles", customer_id: @customer_id, license_plate: "ABC1D23", make: "Honda",
                                         model: "Civic", year: 2020, color: "black")["id"]
  end

  step "um serviço :name de :price reais" do |name, price|
    @service_id = api(:post, "services", name: name, description: name, base_price: price.to_i * 100,
                                         estimated_duration_minutes: 30)["id"]
  end

  step "uma peça :name com :quantity unidades em estoque" do |name, quantity|
    @part_id = api(:post, "inventory_items", name: name, code: "BDD-001", unit_price: 4500, quantity: quantity.to_i)["id"]
  end

  step "uma ordem de serviço aberta com o serviço e :quantity unidades da peça" do |quantity|
    @work_order_id = api(:post, "work_orders", customer_id: @customer_id, vehicle_id: @vehicle_id,
                                               problem_description: "Barulho no motor")["id"]
    api(:patch, "work_orders/#{@work_order_id}/assign", mechanic_id: default_test_mechanic.id)
    api(:post, "work_orders/#{@work_order_id}/line_items", item_type: "service", reference_id: @service_id, quantity: 1)
    api(:post, "work_orders/#{@work_order_id}/line_items", item_type: "part", reference_id: @part_id,
                                                           quantity: quantity.to_i)
  end

  step "o mecânico conclui o diagnóstico" do
    api(:patch, "work_orders/#{@work_order_id}/diagnose")
  end

  step "o Billing informa que o orçamento foi aprovado" do
    saga_event("quote.approved")
  end

  step "o Billing informa que o pagamento foi aprovado" do
    saga_event("payment.approved")
  end

  step "o Execution informa que a execução começou" do
    saga_event("execution.started")
  end

  step "o Execution informa que a execução terminou" do
    services = api(:get, "work_orders/#{@work_order_id}")["line_items"].select { |item| item["item_type"] == "service" }
    saga_event("execution.completed", "items" => services.map do |item|
      { "line_item_id" => item["id"], "started_at" => "2026-11-12T10:00:00Z", "finished_at" => "2026-11-12T10:45:00Z" }
    end)
  end

  step "o Execution informa que a execução falhou" do
    saga_event("execution.failed", "reason" => "Elevador quebrado")
  end

  step "o atendente registra a entrega" do
    api(:patch, "work_orders/#{@work_order_id}/deliver")
  end

  step "a ordem de serviço fica :status" do |status|
    expect(api(:get, "work_orders/#{@work_order_id}")["status"]).to eq(status)
  end

  step "o estoque da peça passa a ser :quantity" do |quantity|
    expect(api(:get, "inventory_items/#{@part_id}")["quantity"]).to eq(quantity.to_i)
  end

  step "o evento :event é publicado" do |event|
    expect(@publisher).to have_received(:publish).with(event, hash_including(work_order_id: @work_order_id))
  end

  step "a entrega é recusada por falta de pagamento" do
    api(:patch, "work_orders/#{@work_order_id}/deliver")
    expect(response).to have_http_status(:unprocessable_content)
  end
end
