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

    context "with a malformed JSON body" do
      let(:malformed_payload) { '{"broken": ' }

      it "stores the body unchanged and answers 200" do
        expect {
          post "/webhooks/receive", params: malformed_payload, headers: { "CONTENT_TYPE" => "application/json" }
        }.to change(Webhook, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(Webhook.last.payload).to eq(malformed_payload)
        expect(Webhook.last.content_type).to eq("application/json")
      end
    end

    context "with a malformed form or multipart body" do
      {
        "an invalid percent-escape" => [ "a=%zz", "application/x-www-form-urlencoded" ],
        "an invalid UTF-8 percent-escape" => [ "a=%FF", "application/x-www-form-urlencoded" ],
        "parameters nested too deep" => [ "a#{"[b]" * 101}=1", "application/x-www-form-urlencoded" ],
        "a broken multipart boundary" => [ "--xyz\r\nbroken", "multipart/form-data; boundary=xyz" ]
      }.each do |kind, (body, content_type)|
        it "stores the body unchanged and answers 200 for #{kind}" do
          expect {
            post "/webhooks/receive", params: body, headers: { "CONTENT_TYPE" => content_type }
          }.to change(Webhook, :count).by(1)

          expect(response).to have_http_status(:ok)
          expect(Webhook.last.payload).to eq(body)
          expect(Webhook.last.content_type).to eq(content_type)
        end
      end

      it "stores the body unchanged and answers 200 for a malformed query string" do
        expect {
          post "/webhooks/receive",
            params: "a=1",
            headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" },
            env: { "QUERY_STRING" => "a=%zz" }
        }.to change(Webhook, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(Webhook.last.payload).to eq("a=1")
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

  describe "endpoints" do
    let(:payload) { { action: "opened" }.to_json }
    let(:json) { { "CONTENT_TYPE" => "application/json" } }
    let(:deploys) { create(:endpoint, name: "Deploys", slug: "deploys") }
    let(:issues) { create(:endpoint, name: "Issues", slug: "issues") }
    let!(:legacy_target) { create(:target, name: "Legacy") }
    let!(:deploys_target) { create(:target, name: "Deploy bot", endpoints: [ deploys ]) }
    let!(:issues_target) { create(:target, name: "Issue tracker", endpoints: [ issues ]) }

    def delivered_target_names
      Delivery.where(webhook: Webhook.last).map { |delivery| delivery.target.name }
    end

    it "routes the plain receive URL to the default endpoint's targets" do
      post "/webhooks/receive", params: payload, headers: json

      expect(response).to have_http_status(:ok)
      expect(Webhook.last.endpoint).to eq(Endpoint.default)
      expect(delivered_target_names).to eq([ "Legacy" ])
    end

    it "routes an endpoint URL only to that endpoint's targets" do
      post "/webhooks/receive/deploys", params: payload, headers: json

      expect(response).to have_http_status(:ok)
      expect(Webhook.last.endpoint).to eq(deploys)
      expect(delivered_target_names).to eq([ "Deploy bot" ])
    end

    it "routes identical payloads differently depending on the URL" do
      post "/webhooks/receive/deploys", params: payload, headers: json
      post "/webhooks/receive/issues", params: payload, headers: json

      expect(Delivery.joins(:target).pluck("targets.name")).to contain_exactly("Deploy bot", "Issue tracker")
    end

    it "accepts the default endpoint by its slug too" do
      post "/webhooks/receive/default", params: payload, headers: json

      expect(delivered_target_names).to eq([ "Legacy" ])
    end

    it "answers 404 for an unknown endpoint and stores nothing" do
      expect { post "/webhooks/receive/nope", params: payload, headers: json }
        .not_to change(Webhook, :count)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Unknown endpoint")
    end

    it "answers 404 for an inactive endpoint and stores nothing" do
      deploys.update!(active: false)

      expect { post "/webhooks/receive/deploys", params: payload, headers: json }
        .not_to change(Webhook, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 on the plain URL when the default endpoint is inactive" do
      Endpoint.default.update!(active: false)

      expect { post "/webhooks/receive", params: payload, headers: json }.not_to change(Webhook, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "still rejects oversized payloads before looking up the endpoint" do
      stub_const("Webhooks::ReceiveController::MAX_PAYLOAD_SIZE", 10)

      post "/webhooks/receive/nope", params: payload, headers: json

      expect(response).to have_http_status(:payload_too_large)
    end

    it "matches slugs the way they are normalized (case-insensitive, underscores as dashes)" do
      post "/webhooks/receive/Deploys", params: payload, headers: json
      expect(response).to have_http_status(:ok)
      expect(Webhook.last.endpoint).to eq(deploys)

      create(:endpoint, slug: "issue-comments")
      post "/webhooks/receive/issue_comments", params: payload, headers: json
      expect(response).to have_http_status(:ok)
    end

    it "still applies each target's filters" do
      create(:filter, target: deploys_target, filter_type: :payload, field: "$.action", operator: :equals, value: "closed")

      post "/webhooks/receive/deploys", params: payload, headers: json

      expect(Delivery.find_by(target: deploys_target)).to be_filtered
    end

    it "ignores an endpoint_slug key in the body of the plain URL" do
      post "/webhooks/receive", params: { endpoint_slug: "deploys" }.to_json, headers: json

      expect(response).to have_http_status(:ok)
      expect(Webhook.last.endpoint).to eq(Endpoint.default)
      expect(delivered_target_names).to eq([ "Legacy" ])
    end

    it "ignores an unknown endpoint_slug key in the body of the plain URL" do
      expect { post "/webhooks/receive", params: { endpoint_slug: "nope" }.to_json, headers: json }
        .to change(Webhook, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(Webhook.last.endpoint).to eq(Endpoint.default)
    end

    it "ignores an endpoint_slug form field on the plain URL" do
      post "/webhooks/receive", params: { endpoint_slug: "deploys" }

      expect(response).to have_http_status(:ok)
      expect(Webhook.last.endpoint).to eq(Endpoint.default)
    end

    it "ignores an endpoint_slug query parameter on the plain URL" do
      post "/webhooks/receive?endpoint_slug=deploys", params: payload, headers: json

      expect(response).to have_http_status(:ok)
      expect(Webhook.last.endpoint).to eq(Endpoint.default)
      expect(delivered_target_names).to eq([ "Legacy" ])
    end

    it "takes the endpoint from the URL path over a body or query endpoint_slug" do
      post "/webhooks/receive/deploys?endpoint_slug=issues", params: { endpoint_slug: "issues" }.to_json, headers: json

      expect(response).to have_http_status(:ok)
      expect(Webhook.last.endpoint).to eq(deploys)
      expect(delivered_target_names).to eq([ "Deploy bot" ])
    end

    it "stores and forwards a malformed JSON body on an endpoint URL" do
      post "/webhooks/receive/deploys", params: '{"broken": ', headers: json

      expect(response).to have_http_status(:ok)
      expect(Webhook.last.payload).to eq('{"broken": ')
      expect(delivered_target_names).to eq([ "Deploy bot" ])
    end

    it "stores and forwards a malformed form body on an endpoint URL" do
      post "/webhooks/receive/deploys", params: "a=%zz", headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

      expect(response).to have_http_status(:ok)
      expect(Webhook.last.payload).to eq("a=%zz")
      expect(Webhook.last.endpoint).to eq(deploys)
      expect(delivered_target_names).to eq([ "Deploy bot" ])
    end

    it "stores webhooks for an endpoint without targets without forwarding them" do
      create(:endpoint, slug: "quiet")

      expect { post "/webhooks/receive/quiet", params: payload, headers: json }.to change(Webhook, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(Delivery.where(webhook: Webhook.last)).to be_empty
    end
  end

  describe "on a database built from the schema (no default endpoint yet)" do
    it "creates the default endpoint on first use of the plain URL" do
      expect(Endpoint.count).to eq(0)

      expect { post "/webhooks/receive", params: "{}", headers: { "CONTENT_TYPE" => "application/json" } }
        .to change(Endpoint, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(Webhook.last.endpoint).to be_default
    end
  end
end
