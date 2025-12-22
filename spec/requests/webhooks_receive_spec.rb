# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /webhooks/receive" do
  describe "webhook reception" do
    let(:payload) { { event: "test.event", data: { id: 1 } }.to_json }

    it "creates a webhook record" do
      expect {
        post "/webhooks/receive", params: payload, headers: { "CONTENT_TYPE" => "application/json" }
      }.to change(Webhook, :count).by(1)

      expect(response).to have_http_status(:ok)
    end

    it "stores the payload" do
      post "/webhooks/receive", params: payload, headers: { "CONTENT_TYPE" => "application/json" }

      webhook = Webhook.last
      expect(webhook.payload).to eq(payload)
    end

    it "stores the content type" do
      post "/webhooks/receive", params: payload, headers: { "CONTENT_TYPE" => "application/json" }

      webhook = Webhook.last
      expect(webhook.content_type).to eq("application/json")
    end

    it "stores the source IP" do
      post "/webhooks/receive", params: payload, headers: { "CONTENT_TYPE" => "application/json" }

      webhook = Webhook.last
      expect(webhook.source_ip).to be_present
    end

    it "stores headers" do
      post "/webhooks/receive", params: payload, headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_API_KEY" => "test-key"
      }

      webhook = Webhook.last
      expect(webhook.headers).to include("HTTP_X_API_KEY" => "test-key")
    end

    context "with active targets" do
      let!(:target) { create(:target, active: true) }

      it "creates pending deliveries" do
        expect {
          post "/webhooks/receive", params: payload, headers: { "CONTENT_TYPE" => "application/json" }
        }.to change(Delivery, :count).by(1)

        delivery = Delivery.last
        expect(delivery.status).to eq("pending")
        expect(delivery.target).to eq(target)
      end

      it "enqueues dispatch jobs" do
        expect {
          post "/webhooks/receive", params: payload, headers: { "CONTENT_TYPE" => "application/json" }
        }.to have_enqueued_job(DispatchJob)
      end
    end

    context "with inactive targets" do
      let!(:target) { create(:target, :inactive) }

      it "does not create deliveries for inactive targets" do
        expect {
          post "/webhooks/receive", params: payload, headers: { "CONTENT_TYPE" => "application/json" }
        }.not_to change(Delivery, :count)
      end
    end

    context "with target filters" do
      let!(:target) { create(:target, active: true) }

      before do
        create(:filter, :header_equals, target: target, field: "X-Api-Key", value: "secret")
      end

      it "creates filtered delivery when filter fails" do
        post "/webhooks/receive", params: payload, headers: {
          "CONTENT_TYPE" => "application/json",
          "HTTP_X_API_KEY" => "wrong-key"
        }

        delivery = Delivery.last
        expect(delivery.status).to eq("filtered")
      end

      it "creates pending delivery when filter passes" do
        post "/webhooks/receive", params: payload, headers: {
          "CONTENT_TYPE" => "application/json",
          "HTTP_X_API_KEY" => "secret"
        }

        delivery = Delivery.last
        expect(delivery.status).to eq("pending")
      end
    end

    context "with oversized payload" do
      before do
        stub_const("Webhooks::ReceiveController::MAX_PAYLOAD_SIZE", 100)
      end

      it "rejects the request" do
        large_payload = "x" * 200
        post "/webhooks/receive", params: large_payload, headers: { "CONTENT_TYPE" => "text/plain" }

        expect(response).to have_http_status(:payload_too_large)
      end
    end
  end
end
