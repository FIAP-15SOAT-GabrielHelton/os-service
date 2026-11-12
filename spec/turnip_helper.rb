# frozen_string_literal: true

require "rails_helper"
require_relative "features/steps/work_order_steps"

RSpec.configure do |config|
  # Passo sem definição falha o cenário, em vez de ficar pendente sem ninguém notar.
  config.raise_error_for_unimplemented_steps = true
  # Os cenários BDD exercitam a API HTTP e os handlers de eventos, como os request specs.
  config.include RSpec::Rails::RequestExampleGroup, turnip: true
  config.include AuthHelpers, turnip: true
  config.include SagaHelpers, turnip: true
  config.include WorkOrderSteps, turnip: true
end
