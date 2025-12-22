# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Dispatches" do
  let(:auth_headers) do
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "changeme")
    { "HTTP_AUTHORIZATION" => credentials }
  end

  describe "GET /admin/dispatches" do
    it "requires authentication" do
      get "/admin/dispatches"

      expect(response).to have_http_status(:unauthorized)
    end

    it "lists deliveries when authenticated" do
      webhook = create(:webhook)
      target = create(:target)
      create(:delivery, webhook: webhook, target: target)

      get "/admin/dispatches", headers: auth_headers

      expect(response).to have_http_status(:ok)
    end

    it "filters by status" do
      webhook = create(:webhook)
      target = create(:target)
      create(:delivery, webhook: webhook, target: target, status: :success)
      create(:delivery, webhook: webhook, target: target, status: :failed)

      get "/admin/dispatches", params: { status: "failed" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
    end

    it "filters by target" do
      webhook = create(:webhook)
      target1 = create(:target)
      target2 = create(:target)
      create(:delivery, webhook: webhook, target: target1)
      create(:delivery, webhook: webhook, target: target2)

      get "/admin/dispatches", params: { target_id: target1.id }, headers: auth_headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /admin/dispatches/:id" do
    let(:delivery) { create(:delivery) }

    it "shows delivery details" do
      get "/admin/dispatches/#{delivery.id}", headers: auth_headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/dispatches/:id/retry" do
    let(:webhook) { create(:webhook) }
    let(:target) { create(:target) }

    context "with retryable delivery" do
      let(:delivery) { create(:delivery, webhook: webhook, target: target, status: :failed, attempts: 1) }

      it "resets status to pending" do
        post "/admin/dispatches/#{delivery.id}/retry", headers: auth_headers

        expect(delivery.reload.status).to eq("pending")
      end

      it "enqueues a dispatch job" do
        expect {
          post "/admin/dispatches/#{delivery.id}/retry", headers: auth_headers
        }.to have_enqueued_job(DispatchJob)
      end

      it "redirects to dispatch show" do
        post "/admin/dispatches/#{delivery.id}/retry", headers: auth_headers

        expect(response).to redirect_to(admin_dispatch_path(delivery))
      end
    end

    context "with non-retryable delivery" do
      let(:delivery) { create(:delivery, webhook: webhook, target: target, status: :success) }

      it "shows alert and does not retry" do
        post "/admin/dispatches/#{delivery.id}/retry", headers: auth_headers

        expect(response).to redirect_to(admin_dispatch_path(delivery))
        expect(flash[:alert]).to be_present
      end
    end
  end
end
