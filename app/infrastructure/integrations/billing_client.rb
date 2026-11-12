# frozen_string_literal: true

require "net/http"
require "json"

module Integrations
  # API Composition (RFC-005): busca no billing-service o orçamento de uma OS,
  # repassando o JWT de quem fez a requisição (token relay) — é o Billing que autoriza.
  class BillingClient
    OPEN_TIMEOUT = 1
    READ_TIMEOUT = 2

    def initialize(base_url: ENV["BILLING_SERVICE_URL"])
      @base_url = base_url
    end

    # Retorna o orçamento (Hash) ou nil. Nunca levanta exceção: o detalhe da OS
    # deve responder mesmo com o Billing fora do ar.
    def quote_for(work_order_id, authorization:)
      return nil if @base_url.blank? || authorization.blank?

      uri = URI.join(@base_url, "/api/v1/work_orders/#{Integer(work_order_id)}/quote")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                     open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.get(uri.path, "Authorization" => authorization, "Accept" => "application/json")
      end

      response.is_a?(Net::HTTPSuccess) ? JSON.parse(response.body) : nil
    rescue StandardError => e
      Rails.logger.warn("[BillingClient] quote lookup failed for work order #{work_order_id}: #{e.message}")
      nil
    end
  end
end
