# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Health Check" do
  describe "GET /health" do
    it "returns ok status" do
      get "/health"

      expect(response).to have_http_status(:ok)
      expect(json_response["status"]).to eq("ok")
    end

    it "includes a timestamp" do
      get "/health"

      expect(json_response["timestamp"]).to be_present
    end

    it "reports database health" do
      get "/health"

      expect(json_response["database"]).to be true
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end
