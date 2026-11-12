# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1 authentication guard", type: :request do
  context "when no Authorization header is sent" do
    it "returns 401 on customers" do
      get "/api/v1/customers", as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 on inventory_items" do
      get "/api/v1/inventory_items", as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 on services" do
      get "/api/v1/services", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "when an invalid token is sent" do
    it "returns 401" do
      get "/api/v1/customers", headers: { "Authorization" => "Bearer not-a-real-token" }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "when calling the public tracking endpoint" do
    it "remains accessible without a token" do
      get "/api/v1/tracking/UNKNOWN1", as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
