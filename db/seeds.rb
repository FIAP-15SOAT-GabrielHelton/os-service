# frozen_string_literal: true

# Idempotent demo seed for the oficina_mecanica project.
#
# Creates users, customers, vehicles, the service catalog, the inventory and a
# small set of WorkOrders distributed across the lifecycle (`received`,
# `awaiting_approval`, `in_progress`, `completed`) so the application can be
# demonstrated end-to-end without manual setup. All writes go through the
# Application use cases — running this seed doubles as an integration smoke test.
#
# Skipped in the test environment: tests rely on factories and an empty database.
# Override credentials with SEED_ADMIN_PASSWORD / SEED_MECHANIC_PASSWORD.

if Rails.env.test?
  puts "Seed: skipped in test environment."
  return
end

# === Helpers ===============================================================

def seed_call!(use_case, **args)
  result = use_case.call(**args)
  raise "Seed failed: #{result.error}" unless result.success?

  result.value
end

# === Repositories ==========================================================

user_repo       = Persistence::Accounts::ActiveRecordUserRepository.new
customer_repo   = Persistence::Registrations::ActiveRecordCustomerRepository.new
vehicle_repo    = Persistence::Registrations::ActiveRecordVehicleRepository.new
service_repo    = Persistence::Registrations::ActiveRecordServiceRepository.new
inventory_repo  = Persistence::Inventory::ActiveRecordInventoryItemRepository.new
work_order_repo = Persistence::WorkOrders::ActiveRecordWorkOrderRepository.new

# === Users =================================================================

register_user = Accounts::RegisterUser.new(user_repository: user_repo)

users_to_seed = [
  {
    role: :admin,
    email: ENV.fetch("SEED_ADMIN_EMAIL", "admin@oficina.local"),
    password: ENV.fetch("SEED_ADMIN_PASSWORD", "oficina123"),
    name: ENV.fetch("SEED_ADMIN_NAME", "Administrator")
  },
  {
    role: :mechanic,
    email: ENV.fetch("SEED_MECHANIC_EMAIL", "mechanic@oficina.local"),
    password: ENV.fetch("SEED_MECHANIC_PASSWORD", "oficina123"),
    name: ENV.fetch("SEED_MECHANIC_NAME", "Default Mechanic")
  }
]

users = {}
users_to_seed.each do |attrs|
  if (existing = user_repo.find_by_email(attrs[:email]))
    puts "Seed: user '#{attrs[:email]}' already exists, skipping."
    users[attrs[:role]] = existing
    next
  end

  users[attrs[:role]] = seed_call!(register_user, **attrs)
  puts "Seed: created #{attrs[:role]} user '#{attrs[:email]}'."
end

mechanic = users[:mechanic]

# === Customers =============================================================

register_customer = Registrations::RegisterCustomer.new(customer_repository: customer_repo)

customers_to_seed = [
  {
    key: :joao,
    person_type: :individual,
    document: "12345678909",
    name: "João Silva",
    email: "joao.silva@example.com",
    phone: "(11) 99999-1111",
    address: {
      zip_code: "01310-100", street: "Avenida Paulista", number: "1000",
      complement: "Apto 51", city: "São Paulo", state: "SP"
    }
  },
  {
    key: :maria,
    person_type: :individual,
    document: "11144477735",
    name: "Maria Souza",
    email: "maria.souza@example.com",
    phone: "(11) 98888-2222",
    address: {
      zip_code: "04023-062", street: "Rua Vergueiro", number: "500",
      city: "São Paulo", state: "SP"
    }
  },
  {
    key: :acme,
    person_type: :company,
    document: "11222333000181",
    name: "Transportadora ACME LTDA",
    email: "contato@acme.com.br",
    phone: "(11) 3333-4444",
    address: {
      zip_code: "07034-911", street: "Rodovia Fernão Dias", number: "Km 80",
      complement: "Galpão 3", city: "Guarulhos", state: "SP"
    }
  }
]

customers = {}
customers_to_seed.each do |spec|
  key = spec[:key]
  attrs = spec.except(:key)
  if (existing = customer_repo.find_by_document(attrs[:document]))
    puts "Seed: customer '#{attrs[:name]}' already exists, skipping."
    customers[key] = existing
    next
  end

  customers[key] = seed_call!(register_customer, **attrs)
  puts "Seed: created customer '#{attrs[:name]}'."
end

# === Vehicles ==============================================================

register_vehicle = Registrations::RegisterVehicle.new(
  vehicle_repository: vehicle_repo,
  customer_repository: customer_repo
)

vehicles_to_seed = [
  { key: :uno,      owner: :joao,  license_plate: "ABC-1234", make: "Fiat",          model: "Uno",      year: 2018, color: "Branco" },
  { key: :civic,    owner: :joao,  license_plate: "DEF-5678", make: "Honda",         model: "Civic",    year: 2020, color: "Prata"  },
  { key: :corolla,  owner: :maria, license_plate: "GHI-9012", make: "Toyota",        model: "Corolla",  year: 2022, color: "Preto"  },
  { key: :sprinter, owner: :acme,  license_plate: "JKL-3456", make: "Mercedes-Benz", model: "Sprinter", year: 2019, color: "Branco" },
  { key: :cargo,    owner: :acme,  license_plate: "MNO-7890", make: "Ford",          model: "Cargo",    year: 2017, color: "Azul"   }
]

vehicles = {}
vehicles_to_seed.each do |spec|
  key = spec[:key]
  owner = spec[:owner]
  attrs = spec.except(:key, :owner)
  if (existing = vehicle_repo.find_by_license_plate(attrs[:license_plate]))
    puts "Seed: vehicle '#{attrs[:license_plate]}' already exists, skipping."
    vehicles[key] = existing
    next
  end

  vehicles[key] = seed_call!(register_vehicle, customer_id: customers[owner].id, **attrs)
  puts "Seed: created vehicle '#{attrs[:license_plate]}' (#{attrs[:make]} #{attrs[:model]})."
end

# === Service catalog =======================================================

register_service = Registrations::RegisterService.new(service_repository: service_repo)

services_to_seed = [
  { key: :oil,      name: "Troca de óleo e filtro",           description: "Troca completa do óleo do motor e filtro de óleo.",                         base_price: 18_000, estimated_duration_minutes: 60  },
  { key: :align,    name: "Alinhamento e balanceamento",      description: "Alinhamento da direção e balanceamento das 4 rodas.",                       base_price: 15_000, estimated_duration_minutes: 90  },
  { key: :brakes,   name: "Troca de pastilhas de freio",      description: "Substituição das pastilhas de freio (par dianteiro ou traseiro).",          base_price: 22_000, estimated_duration_minutes: 120 },
  { key: :revision, name: "Revisão completa (30 mil km)",     description: "Revisão preventiva completa: óleo, filtros, freios, suspensão, eletrônica.", base_price: 80_000, estimated_duration_minutes: 240 },
  { key: :scanner,  name: "Diagnóstico eletrônico (scanner)", description: "Leitura do computador de bordo para identificar falhas eletrônicas.",        base_price: 9_000,  estimated_duration_minutes: 30  },
  { key: :battery,  name: "Troca de bateria",                 description: "Substituição da bateria do veículo, incluindo descarte da antiga.",          base_price: 6_000,  estimated_duration_minutes: 20  },
  { key: :shocks,   name: "Substituição de amortecedores",    description: "Troca dos amortecedores (par dianteiro ou traseiro).",                       base_price: 35_000, estimated_duration_minutes: 180 },
  { key: :belt,     name: "Troca de correia dentada",         description: "Substituição da correia dentada e tensores.",                                base_price: 60_000, estimated_duration_minutes: 300 }
]

services = {}
services_to_seed.each do |spec|
  key = spec[:key]
  attrs = spec.except(:key)
  if (existing = service_repo.find_by_name(attrs[:name]))
    puts "Seed: service '#{attrs[:name]}' already exists, skipping."
    services[key] = existing
    next
  end

  services[key] = seed_call!(register_service, **attrs)
  puts "Seed: created service '#{attrs[:name]}' (#{services[key].base_price.format})."
end

# === Inventory items =======================================================

register_item = Inventory::RegisterInventoryItem.new(inventory_item_repository: inventory_repo)

inventory_to_seed = [
  { key: :oil_5w30,    code: "OLE-5W30",    name: "Óleo motor 5W30 (1L)",         description: "Óleo lubrificante sintético 5W30, embalagem 1 litro.", unit_price: 4_500,  quantity: 50, minimum_quantity: 10 },
  { key: :oil_filter,  code: "FIL-OLE-001", name: "Filtro de óleo",               description: "Filtro de óleo universal (linha leve).",                unit_price: 3_500,  quantity: 30, minimum_quantity: 5  },
  { key: :air_filter,  code: "FIL-AR-001",  name: "Filtro de ar",                 description: "Filtro de ar do motor.",                                unit_price: 4_500,  quantity: 25, minimum_quantity: 5  },
  { key: :fuel_filter, code: "FIL-COM-001", name: "Filtro de combustível",        description: "Filtro de combustível.",                                unit_price: 6_000,  quantity: 20, minimum_quantity: 4  },
  { key: :pad_front,   code: "PAS-FRE-DIA", name: "Pastilha de freio dianteira",  description: "Par de pastilhas de freio dianteiras.",                 unit_price: 18_000, quantity: 15, minimum_quantity: 3  },
  { key: :pad_rear,    code: "PAS-FRE-TRA", name: "Pastilha de freio traseira",   description: "Par de pastilhas de freio traseiras.",                  unit_price: 16_000, quantity: 15, minimum_quantity: 3  },
  { key: :battery,     code: "BAT-60AH",    name: "Bateria 60Ah",                 description: "Bateria automotiva 60Ah, livre de manutenção.",         unit_price: 35_000, quantity: 8,  minimum_quantity: 2  },
  { key: :spark_plug,  code: "VEL-IGN-001", name: "Vela de ignição",              description: "Vela de ignição (unidade).",                            unit_price: 2_800,  quantity: 60, minimum_quantity: 12 },
  { key: :h7_lamp,     code: "LAM-H7",      name: "Lâmpada H7",                   description: "Lâmpada de farol H7 (unidade).",                        unit_price: 3_500,  quantity: 40, minimum_quantity: 8  },
  { key: :timing_belt, code: "COR-DEN-001", name: "Correia dentada",              description: "Correia dentada do motor.",                             unit_price: 22_000, quantity: 10, minimum_quantity: 2  },
  { key: :shock_front, code: "AMO-DIA-001", name: "Amortecedor dianteiro",        description: "Amortecedor dianteiro (unidade).",                      unit_price: 28_000, quantity: 12, minimum_quantity: 3  },
  { key: :wiper,       code: "LIM-PAR-001", name: "Limpador de para-brisa",       description: "Palheta limpador de para-brisa (par).",                 unit_price: 4_000,  quantity: 30, minimum_quantity: 5  }
]

inventory = {}
inventory_to_seed.each do |spec|
  key = spec[:key]
  attrs = spec.except(:key)
  if (existing = inventory_repo.find_by_code(attrs[:code]))
    puts "Seed: inventory item '#{attrs[:code]}' already exists, skipping."
    inventory[key] = existing
    next
  end

  inventory[key] = seed_call!(register_item, **attrs)
  puts "Seed: created inventory item '#{attrs[:code]}' (#{attrs[:name]}, qty=#{attrs[:quantity]})."
end

# === Work orders ===========================================================

work_orders_summary = []

if Persistence::WorkOrders::WorkOrderRecord.exists?
  puts "Seed: work orders already present, skipping work order seeding."
  work_order_repo.all.each do |wo|
    customer = customer_repo.find(wo.customer_id)
    vehicle = vehicle_repo.find(wo.vehicle_id)
    work_orders_summary << { wo: wo, customer: customer, vehicle: vehicle }
  end
else
  # Aprovação: em produção vem do evento quote.approved (billing-service).
  approve_wo     = WorkOrders::ApproveWorkOrder.new(
    work_order_repository: work_order_repo,
    decrease_quantity: Inventory::DecreaseQuantity.new(inventory_item_repository: inventory_repo),
    cancel_work_order: WorkOrders::CancelWorkOrder.new(
      work_order_repository: work_order_repo,
      add_quantity: Inventory::AddQuantity.new(inventory_item_repository: inventory_repo)
    )
  )

  create_wo      = WorkOrders::CreateWorkOrder.new(
    work_order_repository: work_order_repo,
    customer_repository: customer_repo,
    vehicle_repository: vehicle_repo
  )
  assign_wo      = WorkOrders::AssignWorkOrder.new(work_order_repository: work_order_repo, user_repository: user_repo)
  add_line_item  = WorkOrders::AddLineItem.new(
    work_order_repository: work_order_repo,
    service_repository: service_repo,
    inventory_item_repository: inventory_repo
  )
  diagnose_wo    = WorkOrders::DiagnoseWorkOrder.new(work_order_repository: work_order_repo)
  execute_wo     = WorkOrders::ExecuteService.new(work_order_repository: work_order_repo)
  # Conclusão: em produção vem do evento execution.completed (execution-service).
  complete_wo    = WorkOrders::CompleteWorkOrder.new(work_order_repository: work_order_repo)

  # ---- WO #1 — received -----------------------------------------------------
  wo1 = seed_call!(create_wo,
    customer_id: customers[:maria].id,
    vehicle_id: vehicles[:corolla].id,
    problem_description: "Carro morrendo no semáforo, possível problema na injeção eletrônica."
  )
  work_orders_summary << { wo: wo1, customer: customers[:maria], vehicle: vehicles[:corolla] }
  puts "Seed: created WO #{wo1.protocol} (received)."

  # ---- WO #2 — awaiting_approval -------------------------------------------
  wo2 = seed_call!(create_wo,
    customer_id: customers[:joao].id,
    vehicle_id: vehicles[:uno].id,
    problem_description: "Barulho ao frear, principalmente nos freios dianteiros."
  )
  seed_call!(assign_wo, id: wo2.id, mechanic_id: mechanic.id)
  seed_call!(add_line_item, work_order_id: wo2.id, item_type: :service, reference_id: services[:brakes].id, quantity: 1)
  seed_call!(add_line_item, work_order_id: wo2.id, item_type: :part,    reference_id: inventory[:pad_front].id, quantity: 1)
  seed_call!(diagnose_wo, id: wo2.id)
  wo2 = work_order_repo.find(wo2.id)
  work_orders_summary << { wo: wo2, customer: customers[:joao], vehicle: vehicles[:uno] }
  puts "Seed: created WO #{wo2.protocol} (awaiting_approval)."

  # ---- WO #3 — in_progress (one service started, none finished) ------------
  wo3 = seed_call!(create_wo,
    customer_id: customers[:acme].id,
    vehicle_id: vehicles[:sprinter].id,
    problem_description: "Revisão preventiva 60 mil km."
  )
  seed_call!(assign_wo, id: wo3.id, mechanic_id: mechanic.id)
  seed_call!(add_line_item, work_order_id: wo3.id, item_type: :service, reference_id: services[:revision].id,  quantity: 1)
  seed_call!(add_line_item, work_order_id: wo3.id, item_type: :service, reference_id: services[:oil].id,       quantity: 1)
  seed_call!(add_line_item, work_order_id: wo3.id, item_type: :part,    reference_id: inventory[:oil_5w30].id, quantity: 5)
  seed_call!(add_line_item, work_order_id: wo3.id, item_type: :part,    reference_id: inventory[:oil_filter].id, quantity: 1)
  seed_call!(add_line_item, work_order_id: wo3.id, item_type: :part,    reference_id: inventory[:air_filter].id, quantity: 1)
  seed_call!(diagnose_wo, id: wo3.id)
  seed_call!(approve_wo, id: wo3.id)
  seed_call!(execute_wo, id: wo3.id)
  refreshed3 = work_order_repo.find(wo3.id)
  oil_item = refreshed3.line_items.find { |li| li.service? && li.name_snapshot == services[:oil].name }

  # Mark one service as started 30 minutes ago
  Persistence::WorkOrders::LineItemRecord.find(oil_item.id).update(
    started_at: 30.minutes.ago
  )

  wo3 = work_order_repo.find(wo3.id)
  work_orders_summary << { wo: wo3, customer: customers[:acme], vehicle: vehicles[:sprinter] }
  puts "Seed: created WO #{wo3.protocol} (in_progress)."

  # ---- WO #4 — completed (full lifecycle) ----------------------------------
  wo4 = seed_call!(create_wo,
    customer_id: customers[:joao].id,
    vehicle_id: vehicles[:civic].id,
    problem_description: "Bateria descarregada após viagem longa."
  )
  seed_call!(assign_wo, id: wo4.id, mechanic_id: mechanic.id)
  seed_call!(add_line_item, work_order_id: wo4.id, item_type: :service, reference_id: services[:battery].id, quantity: 1)
  seed_call!(add_line_item, work_order_id: wo4.id, item_type: :service, reference_id: services[:scanner].id, quantity: 1)
  seed_call!(add_line_item, work_order_id: wo4.id, item_type: :part,    reference_id: inventory[:battery].id, quantity: 1)
  seed_call!(diagnose_wo, id: wo4.id)
  seed_call!(approve_wo, id: wo4.id)
  seed_call!(execute_wo, id: wo4.id)
  refreshed4 = work_order_repo.find(wo4.id)
  # Each service with a realistic duration (20-40 minutes), as execution-service would report
  started_at = 2.hours.ago
  service_times = refreshed4.service_line_items.each_with_index.map do |item, idx|
    { "line_item_id" => item.id, "started_at" => started_at.iso8601,
      "finished_at" => (started_at + (20 + idx * 10).minutes).iso8601 }
  end
  seed_call!(complete_wo, id: wo4.id, items: service_times)
  wo4 = work_order_repo.find(wo4.id)
  work_orders_summary << { wo: wo4, customer: customers[:joao], vehicle: vehicles[:civic] }
  puts "Seed: created WO #{wo4.protocol} (#{wo4.status})."
end

# === Summary ===============================================================

puts ""
puts "=" * 64
puts "  Oficina Mecânica — Seed Summary"
puts "=" * 64

puts ""
puts "CREDENCIAIS"
users.each do |role, user|
  password = role == :admin ?
    ENV.fetch("SEED_ADMIN_PASSWORD", "oficina123") :
    ENV.fetch("SEED_MECHANIC_PASSWORD", "oficina123")
  puts "  #{user.email.address.ljust(28)} senha: #{password}  (#{role})"
end

puts ""
puts "CUSTOMERS (#{customers.size})"
customers.each_value do |c|
  puts "  [#{c.id.to_s.rjust(3)}] #{c.name.ljust(36)} #{c.document.formatted}"
end

puts ""
puts "VEHICLES (#{vehicles.size})"
vehicles.each_value do |v|
  owner = customers.values.find { |c| c.id == v.customer_id }
  puts "  [#{v.id.to_s.rjust(3)}] #{v.license_plate.formatted.ljust(10)} #{v.make} #{v.model} #{v.year}  (#{owner&.name})"
end

puts ""
puts "CATÁLOGO"
puts "  Services:        #{Persistence::Registrations::ServiceRecord.count} cadastrados"
puts "  InventoryItems:  #{Persistence::Inventory::InventoryItemRecord.count} cadastrados (estoque total: #{Persistence::Inventory::InventoryItemRecord.sum(:quantity)} unidades)"

unless work_orders_summary.empty?
  puts ""
  puts "WORK ORDERS (#{work_orders_summary.size})"
  puts "  PROTOCOL    STATUS              CUSTOMER                  VEHICLE"
  work_orders_summary.each do |entry|
    wo = entry[:wo]
    puts "  #{wo.protocol.ljust(11)} #{wo.status.to_s.ljust(19)} #{entry[:customer].name.ljust(25)} #{entry[:vehicle].make} #{entry[:vehicle].model}"
  end
end

puts ""
puts "DEMO AO VIVO — para criar uma OS nova do zero, use:"
puts "  customer_id = #{customers[:maria].id}  (#{customers[:maria].name})"
puts "  vehicle_id  = #{vehicles[:corolla].id}  (#{vehicles[:corolla].license_plate.formatted} #{vehicles[:corolla].make} #{vehicles[:corolla].model})"
puts "  Veja README → 'Demo Walkthrough' para o passo-a-passo HTTP."
puts "=" * 64
