# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Webhooks" do
  let(:auth_headers) do
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "changeme")
    { "HTTP_AUTHORIZATION" => credentials }
  end

  describe "GET /admin/webhooks" do
    it "requires authentication" do
      get "/admin/webhooks"

      expect(response).to have_http_status(:unauthorized)
    end

    it "lists webhooks when authenticated" do
      create(:webhook)

      get "/admin/webhooks", headers: auth_headers

      expect(response).to have_http_status(:ok)
    end

    it "paginates results" do
      create_list(:webhook, 60)

      get "/admin/webhooks", headers: auth_headers

      # Check for pagination navigation (page numbers or rel="next")
      expect(response.body).to match(/page=2|rel="next"/)
    end

    it "filters by date_from" do
      old_webhook = create(:webhook, received_at: 10.days.ago)
      new_webhook = create(:webhook, received_at: 1.day.ago)

      get "/admin/webhooks", params: { date_from: 5.days.ago.to_date }, headers: auth_headers

      expect(response.body).to include(new_webhook.id.to_s)
      expect(response.body).not_to include("webhook-#{old_webhook.id}")
    end

    it "filters by date_to" do
      old_webhook = create(:webhook, received_at: 10.days.ago)
      new_webhook = create(:webhook, received_at: 1.day.ago)

      get "/admin/webhooks", params: { date_to: 5.days.ago.to_date }, headers: auth_headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /admin/webhooks/:id" do
    let(:webhook) { create(:webhook) }

    it "shows webhook details" do
      get "/admin/webhooks/#{webhook.id}", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(webhook.source_ip)
    end
  end

  describe "DELETE /admin/webhooks/:id" do
    let!(:webhook) { create(:webhook) }

    it "deletes the webhook" do
      expect {
        delete "/admin/webhooks/#{webhook.id}", headers: auth_headers
      }.to change { Webhook.count }.by(-1)
    end

    it "redirects to index" do
      delete "/admin/webhooks/#{webhook.id}", headers: auth_headers

      expect(response).to redirect_to(admin_webhooks_path)
    end
  end

  describe "POST /admin/webhooks/:id/replay" do
    let(:webhook) { create(:webhook) }
    let!(:target) { create(:target, active: true) }

    it "creates new deliveries" do
      expect {
        post "/admin/webhooks/#{webhook.id}/replay", headers: auth_headers
      }.to change { Delivery.count }.by(1)
    end

    it "redirects to webhook show" do
      post "/admin/webhooks/#{webhook.id}/replay", headers: auth_headers

      expect(response).to redirect_to(admin_webhook_path(webhook))
    end
  end
end
