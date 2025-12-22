# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Targets" do
  let(:auth_headers) do
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "changeme")
    { "HTTP_AUTHORIZATION" => credentials }
  end

  describe "GET /admin/targets" do
    it "requires authentication" do
      get "/admin/targets"

      expect(response).to have_http_status(:unauthorized)
    end

    it "lists targets when authenticated" do
      create(:target)

      get "/admin/targets", headers: auth_headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /admin/targets/new" do
    it "renders new target form" do
      get "/admin/targets/new", headers: auth_headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/targets" do
    let(:valid_params) do
      {
        target: {
          name: "Test Target",
          url: "https://example.com/webhook",
          active: true,
          timeout: 30
        }
      }
    end

    it "creates a new target" do
      expect {
        post "/admin/targets", params: valid_params, headers: auth_headers
      }.to change { Target.count }.by(1)
    end

    it "redirects to targets index" do
      post "/admin/targets", params: valid_params, headers: auth_headers

      expect(response).to redirect_to(admin_targets_path)
    end

    it "creates target with custom headers" do
      params_with_headers = {
        target: {
          name: "Test Target",
          url: "https://example.com/webhook",
          active: true,
          timeout: 30,
          custom_headers_keys: [ "Authorization", "X-Custom" ],
          custom_headers_values: [ "Bearer token", "value" ]
        }
      }

      post "/admin/targets", params: params_with_headers, headers: auth_headers

      target = Target.last
      expect(target.custom_headers).to eq({ "Authorization" => "Bearer token", "X-Custom" => "value" })
    end

    it "ignores blank custom header keys" do
      params_with_blank = {
        target: {
          name: "Test Target",
          url: "https://example.com/webhook",
          active: true,
          timeout: 30,
          custom_headers_keys: [ "Authorization", "" ],
          custom_headers_values: [ "Bearer token", "ignored" ]
        }
      }

      post "/admin/targets", params: params_with_blank, headers: auth_headers

      target = Target.last
      expect(target.custom_headers).to eq({ "Authorization" => "Bearer token" })
    end

    context "with invalid params" do
      let(:invalid_params) { { target: { name: "", url: "" } } }

      it "renders new form with errors" do
        post "/admin/targets", params: invalid_params, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /admin/targets/:id" do
    let(:target) { create(:target) }

    it "shows target details" do
      get "/admin/targets/#{target.id}", headers: auth_headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /admin/targets/:id/edit" do
    let(:target) { create(:target) }

    it "renders edit form" do
      get "/admin/targets/#{target.id}/edit", headers: auth_headers

      expect(response).to have_http_status(:ok)
    end

    it "renders edit form with existing filters" do
      target_with_filters = create(:target, :with_filter)

      get "/admin/targets/#{target_with_filters.id}/edit", headers: auth_headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /admin/targets/:id" do
    let(:target) { create(:target) }
    let(:update_params) { { target: { name: "Updated Name" } } }

    it "updates the target" do
      patch "/admin/targets/#{target.id}", params: update_params, headers: auth_headers

      expect(target.reload.name).to eq("Updated Name")
    end

    it "redirects to targets index" do
      patch "/admin/targets/#{target.id}", params: update_params, headers: auth_headers

      expect(response).to redirect_to(admin_targets_path)
    end

    context "with invalid params" do
      let(:invalid_params) { { target: { url: "not-a-url" } } }

      it "renders edit form with errors" do
        patch "/admin/targets/#{target.id}", params: invalid_params, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /admin/targets/:id" do
    let!(:target) { create(:target) }

    it "deletes the target" do
      expect {
        delete "/admin/targets/#{target.id}", headers: auth_headers
      }.to change { Target.count }.by(-1)
    end

    it "redirects to targets index" do
      delete "/admin/targets/#{target.id}", headers: auth_headers

      expect(response).to redirect_to(admin_targets_path)
    end
  end

  describe "POST /admin/targets/:id/test" do
    let(:target) { create(:target) }

    context "with successful test" do
      before do
        stub_request(:post, target.url)
          .to_return(status: 200, body: '{"status": "ok"}')
      end

      it "redirects with success notice" do
        post "/admin/targets/#{target.id}/test", headers: auth_headers

        expect(response).to redirect_to(admin_targets_path)
        expect(flash[:notice]).to include("Test successful")
      end
    end

    context "with failed test" do
      before do
        stub_request(:post, target.url)
          .to_return(status: 500, body: '{"error": "Server Error"}')
      end

      it "redirects with alert" do
        post "/admin/targets/#{target.id}/test", headers: auth_headers

        expect(response).to redirect_to(admin_targets_path)
        expect(flash[:alert]).to include("Test failed")
      end
    end
  end
end
