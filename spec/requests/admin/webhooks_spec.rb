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

    context "text search" do
      it "finds webhooks by payload content" do
        matching = create(:webhook, payload: '{"event":"user.created","user_id":123}')
        non_matching = create(:webhook, payload: '{"event":"order.completed"}')

        get "/admin/webhooks", params: { q: "user.created" }, headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(matching.id.to_s)
        expect(response.body).not_to include("webhook-#{non_matching.id}")
      end

      it "finds webhooks by header content" do
        matching = create(:webhook, headers: { "HTTP_X_API_KEY" => "secret-key-123" })
        non_matching = create(:webhook, headers: { "HTTP_X_API_KEY" => "other-key" })

        get "/admin/webhooks", params: { q: "secret-key-123" }, headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(matching.id.to_s)
        expect(response.body).not_to include("webhook-#{non_matching.id}")
      end

      it "performs case-insensitive search" do
        webhook = create(:webhook, payload: '{"Event":"USER.CREATED"}')

        get "/admin/webhooks", params: { q: "user.created" }, headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(webhook.id.to_s)
      end

      it "searches both headers and payload" do
        webhook_with_header = create(:webhook,
          headers: { "HTTP_X_SEARCH" => "findme" },
          payload: '{"event":"test"}')
        webhook_with_payload = create(:webhook,
          headers: { "HTTP_X_API" => "key" },
          payload: '{"data":"findme"}')
        non_matching = create(:webhook)

        get "/admin/webhooks", params: { q: "findme" }, headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(webhook_with_header.id.to_s)
        expect(response.body).to include(webhook_with_payload.id.to_s)
        expect(response.body).not_to include("webhook-#{non_matching.id}")
      end

      it "returns all webhooks when search term is empty" do
        create_list(:webhook, 3)

        get "/admin/webhooks", params: { q: "" }, headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to match(/webhook/i)
      end

      it "combines with date filters" do
        old_matching = create(:webhook,
          received_at: 10.days.ago,
          payload: '{"search":"term"}')
        new_matching = create(:webhook,
          received_at: 1.day.ago,
          payload: '{"search":"term"}')
        new_non_matching = create(:webhook,
          received_at: 1.day.ago,
          payload: '{"other":"data"}')

        get "/admin/webhooks",
          params: { q: "search", date_from: 5.days.ago.to_date },
          headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(new_matching.id.to_s)
        expect(response.body).not_to include("webhook-#{old_matching.id}")
        expect(response.body).not_to include("webhook-#{new_non_matching.id}")
      end

      it "handles special characters safely" do
        webhook = create(:webhook, payload: '{"data":"test%value"}')

        get "/admin/webhooks", params: { q: "test%" }, headers: auth_headers

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /admin/webhooks/:id" do
    let(:webhook) { create(:webhook) }

    it "shows webhook details" do
      get "/admin/webhooks/#{webhook.id}", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(webhook.source_ip)
    end

    it "shows a body that is not valid UTF-8 with invalid bytes replaced and a note" do
      webhook = create(:webhook, content_type: "application/octet-stream", payload: "caf\xE9".b)

      get "/admin/webhooks/#{webhook.id}", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body.dup.force_encoding(Encoding::UTF_8)).to be_valid_encoding
      expect(response.body).to include("caf\uFFFD")
      expect(response.body).to include("Not valid UTF-8: shown with invalid bytes replaced. Targets get the original 4 bytes.")
    end

    it "pretty-prints a UTF-8 JSON body without the note" do
      webhook = create(:webhook, content_type: "application/json", payload: %({"m":"x — y"}).b)

      get "/admin/webhooks/#{webhook.id}", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(JSON.pretty_generate("m" => "x — y")))
      expect(response.body).not_to include("Not valid UTF-8")
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
      expect(flash[:notice]).to eq("Webhook queued for replay to the active targets of endpoint Default")
    end

    it "replays only to the current targets of the webhook's endpoint" do
      deploys = create(:endpoint, name: "Deploys", slug: "deploys")
      deploys_target = create(:target, endpoints: [ deploys ])
      deploys_webhook = create(:webhook, endpoint: deploys)

      post "/admin/webhooks/#{deploys_webhook.id}/replay", headers: auth_headers

      expect(Delivery.where(webhook: deploys_webhook).pluck(:target_id)).to eq([ deploys_target.id ])
      expect(flash[:notice]).to include("endpoint Deploys")
    end

    it "refuses to replay a webhook whose endpoint was deleted" do
      orphan = create(:webhook, endpoint: nil)

      expect { post "/admin/webhooks/#{orphan.id}/replay", headers: auth_headers }.not_to change(Delivery, :count)
      expect(flash[:alert]).to eq("This webhook's endpoint was deleted, so it cannot be replayed")
    end
  end

  describe "endpoints on the webhook pages" do
    let(:deploys) { create(:endpoint, name: "Deploys", slug: "deploys") }
    let!(:deploys_webhook) { create(:webhook, endpoint: deploys, payload: '{"from":"deploys"}') }
    let!(:default_webhook) { create(:webhook, payload: '{"from":"default"}') }
    let!(:orphan_webhook) { create(:webhook, endpoint: nil, payload: '{"from":"orphan"}') }

    def row_ids
      Nokogiri::HTML(response.body).css("tbody tr td:first-child").map { |cell| cell.text.strip.to_i }
    end

    it "lists the endpoint of each webhook" do
      get "/admin/webhooks", headers: auth_headers

      expect(response.body).to include("Deploys", "Default", "(deleted)")
    end

    it "filters webhooks by endpoint" do
      get "/admin/webhooks", params: { endpoint_id: deploys.id }, headers: auth_headers

      expect(row_ids).to eq([ deploys_webhook.id ])
      expect(Nokogiri::HTML(response.body).at_css("select[name='endpoint_id'] option[selected]").text).to eq("Deploys")
    end

    it "combines the endpoint filter with search" do
      get "/admin/webhooks", params: { endpoint_id: deploys.id, q: "default" }, headers: auth_headers

      expect(row_ids).to be_empty
    end

    it "shows the endpoint on the webhook page" do
      get "/admin/webhooks/#{deploys_webhook.id}", headers: auth_headers

      expect(Nokogiri::HTML(response.body).at_css("a[href='/admin/endpoints/#{deploys.id}']").text).to eq("Deploys")
    end
  end
end
