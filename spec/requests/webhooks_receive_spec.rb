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

    context "with multi-byte UTF-8 characters in the payload" do
      let(:message) { "explicit [git] name/email) — use as-is, don't overwrite." }
      let(:payload) { { message: message }.to_json }

      it "creates the webhook without raising an encoding error" do
        expect {
          post "/webhooks/receive", params: payload, headers: { "CONTENT_TYPE" => "application/json" }
        }.to change(Webhook, :count).by(1)

        expect(response).to have_http_status(:ok)
      end

      it "preserves the multi-byte characters" do
        post "/webhooks/receive", params: payload, headers: { "CONTENT_TYPE" => "application/json" }

        expect(Webhook.last.payload).to include("—")
      end
    end

    context "with invalid UTF-8 byte sequences in the raw body" do
      # Content-Type is deliberately not application/json here: Rails parses
      # JSON bodies into params before the action runs, so an invalid-encoding
      # payload would 400 out at that layer rather than exercising the
      # controller's own raw_post handling.
      let(:invalid_payload) { "note: broken \xE2 sequence".b }

      it "does not raise an encoding error" do
        expect {
          post "/webhooks/receive", params: invalid_payload, headers: { "CONTENT_TYPE" => "application/octet-stream" }
        }.not_to raise_error
      end

      it "stores the payload with invalid bytes scrubbed" do
        post "/webhooks/receive", params: invalid_payload, headers: { "CONTENT_TYPE" => "application/octet-stream" }

        expect(response).to have_http_status(:ok)
        expect(Webhook.last.payload).to be_valid_encoding
      end
    end

    context "with invalid UTF-8 byte sequences in a header value" do
      let(:invalid_header) { "broken \xE2 header".b }

      it "does not raise an encoding error" do
        expect {
          post "/webhooks/receive", params: payload, headers: {
            "CONTENT_TYPE" => "application/json",
            "HTTP_X_CUSTOM" => invalid_header
          }
        }.not_to raise_error

        expect(response).to have_http_status(:ok)
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
