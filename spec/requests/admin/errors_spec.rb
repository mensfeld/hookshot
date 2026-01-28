# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Errors" do
  let(:auth_headers) do
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "changeme")
    { "HTTP_AUTHORIZATION" => credentials }
  end

  describe "GET /errors" do
    it "requires authentication" do
      get "/errors"

      expect(response).to have_http_status(:unauthorized)
    end

    it "lists errors when authenticated" do
      create(:error_record)

      get "/errors", headers: auth_headers

      expect(response).to have_http_status(:ok)
    end

    context "with tab parameter" do
      let!(:unresolved_error) { create(:error_record) }
      let!(:resolved_error) { create(:error_record, :resolved) }

      it "defaults to unresolved tab" do
        get "/errors", headers: auth_headers

        expect(response.body).to include(unresolved_error.error_class)
        expect(response.body).not_to include(resolved_error.error_class)
      end

      it "filters by resolved tab" do
        get "/errors?tab=resolved", headers: auth_headers

        expect(response.body).to include(resolved_error.error_class)
        expect(response.body).not_to include(unresolved_error.error_class)
      end

      it "shows all errors in all tab" do
        get "/errors?tab=all", headers: auth_headers

        expect(response.body).to include(unresolved_error.error_class)
        expect(response.body).to include(resolved_error.error_class)
      end
    end
  end

  describe "GET /errors/:id" do
    let(:error_record) { create(:error_record) }

    it "requires authentication" do
      get "/errors/#{error_record.id}"

      expect(response).to have_http_status(:unauthorized)
    end

    it "shows error details when authenticated" do
      get "/errors/#{error_record.id}", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(error_record.error_class)
      expect(response.body).to include(error_record.message)
    end
  end

  describe "POST /errors/:id/resolve" do
    let(:error_record) { create(:error_record) }

    it "requires authentication" do
      post "/errors/#{error_record.id}/resolve"

      expect(response).to have_http_status(:unauthorized)
    end

    it "marks error as resolved" do
      post "/errors/#{error_record.id}/resolve", headers: auth_headers

      expect(error_record.reload.resolved?).to be true
    end

    it "redirects to error page" do
      post "/errors/#{error_record.id}/resolve", headers: auth_headers

      expect(response).to redirect_to(error_path(error_record))
    end
  end

  describe "POST /errors/:id/unresolve" do
    let(:error_record) { create(:error_record, :resolved) }

    it "requires authentication" do
      post "/errors/#{error_record.id}/unresolve"

      expect(response).to have_http_status(:unauthorized)
    end

    it "marks error as unresolved" do
      post "/errors/#{error_record.id}/unresolve", headers: auth_headers

      expect(error_record.reload.resolved?).to be false
    end

    it "redirects to error page" do
      post "/errors/#{error_record.id}/unresolve", headers: auth_headers

      expect(response).to redirect_to(error_path(error_record))
    end
  end

  describe "DELETE /errors/:id" do
    let!(:error_record) { create(:error_record) }

    it "requires authentication" do
      delete "/errors/#{error_record.id}"

      expect(response).to have_http_status(:unauthorized)
    end

    it "deletes the error" do
      expect {
        delete "/errors/#{error_record.id}", headers: auth_headers
      }.to change { ErrorRecord.count }.by(-1)
    end

    it "redirects to errors index" do
      delete "/errors/#{error_record.id}", headers: auth_headers

      expect(response).to redirect_to(errors_path)
    end
  end

  describe "DELETE /errors/destroy_all" do
    let!(:unresolved_error) { create(:error_record) }
    let!(:resolved_error1) { create(:error_record, :resolved) }
    let!(:resolved_error2) { create(:error_record, :resolved) }

    it "requires authentication" do
      delete "/errors/destroy_all"

      expect(response).to have_http_status(:unauthorized)
    end

    it "deletes only resolved errors" do
      expect {
        delete "/errors/destroy_all", headers: auth_headers
      }.to change { ErrorRecord.count }.from(3).to(1)

      expect(ErrorRecord.exists?(unresolved_error.id)).to be true
      expect(ErrorRecord.exists?(resolved_error1.id)).to be false
      expect(ErrorRecord.exists?(resolved_error2.id)).to be false
    end

    it "redirects to errors index" do
      delete "/errors/destroy_all", headers: auth_headers

      expect(response).to redirect_to(errors_path)
    end

    it "shows count in flash" do
      delete "/errors/destroy_all", headers: auth_headers

      expect(flash[:notice]).to include("Deleted 2 resolved error")
    end
  end
end
