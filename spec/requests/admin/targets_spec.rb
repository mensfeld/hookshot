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

    it "summarizes grouped filters" do
      target = create(:target)
      create(:filter, target: target, group_key: "ci-fail", field: "X-GitHub-Event")
      create(:filter, target: target, group_key: "ci-fail", field: "X-Hub-Signature")
      create(:filter, target: target, group_key: "approved", field: "X-Api-Key")

      get "/admin/targets", headers: auth_headers

      expect(response.body).to include("3 filters in 2 groups")
      expect(response.body).to include(
        "Delivers if [approved] (Header &#39;X-Api-Key&#39; must exist) OR " \
        "[ci-fail] (Header &#39;X-GitHub-Event&#39; must exist AND Header &#39;X-Hub-Signature&#39; must exist)"
      )
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

    context "with grouped filters" do
      let(:grouped_params) do
        {
          target: {
            name: "Reconciler",
            url: "https://example.com/webhook",
            active: true,
            timeout: 30,
            filters_attributes: {
              "0" => { group_key: "ci-fail", filter_type: "header", field: "X-GitHub-Event", operator: "equals", value: "check_suite" },
              "1" => { group_key: "ci-fail", filter_type: "payload", field: "$.check_suite.conclusion", operator: "equals", value: "failure" },
              "2" => { group_key: " approved ", filter_type: "payload", field: "$.review.state", operator: "equals", value: "approved" },
              "3" => { group_key: "", filter_type: "header", field: "X-Api-Key", operator: "exists", value: "" },
              "1000" => { group_key: "ci-fail", filter_type: "header", field: "", operator: "exists", value: "" }
            }
          }
        }
      end

      it "persists each filter with its group" do
        post "/admin/targets", params: grouped_params, headers: auth_headers

        target = Target.last
        expect(target.filters.order(:id).pluck(:group_key, :field)).to eq([
          [ "ci-fail", "X-GitHub-Event" ],
          [ "ci-fail", "$.check_suite.conclusion" ],
          [ "approved", "$.review.state" ],
          [ "default", "X-Api-Key" ]
        ])
        expect(target.filter_groups.keys).to eq(%w[approved ci-fail default])
      end

      it "rejects rows with a blank field instead of failing validation" do
        post "/admin/targets", params: grouped_params, headers: auth_headers

        expect(response).to redirect_to(admin_targets_path)
        expect(Target.last.filters.count).to eq(4)
      end

      it "creates the target when the only filter row is blank" do
        params = grouped_params.deep_dup
        params[:target][:filters_attributes] = {
          "0" => { group_key: "default", filter_type: "header", field: "", operator: "exists", value: "" }
        }

        expect {
          post "/admin/targets", params: params, headers: auth_headers
        }.to change(Target, :count).by(1)
        expect(Target.last.filters).to be_empty
      end

      it "renders errors for an incomplete filter row" do
        params = grouped_params.deep_dup
        params[:target][:filters_attributes] = {
          "0" => { group_key: "ci-fail", filter_type: "header", field: "X-GitHub-Event", operator: "equals", value: "" }
        }

        post "/admin/targets", params: params, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('value="ci-fail"')
      end
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

    it "renders filters grouped as an OR of ANDs" do
      create(:filter, target: target, group_key: "ci-fail", filter_type: :header, field: "X-GitHub-Event",
        operator: :equals, value: "check_suite")
      create(:filter, target: target, group_key: "ci-fail", filter_type: :payload, field: "$.check_suite.conclusion",
        operator: :equals, value: "failure")
      create(:filter, target: target, group_key: "copilot-comment", filter_type: :payload,
        field: "$.comment.user.login", operator: :matches, value: "*copilot*")

      get "/admin/targets/#{target.id}", headers: auth_headers

      body = response.body
      expect(body).to include("group: ci-fail", "group: copilot-comment")
      expect(body).to include("Delivers if <strong>ANY</strong> group matches")
      expect(body.index("group: ci-fail")).to be < body.index("group: copilot-comment")
      expect(body).to include("Payload &#39;$.comment.user.login&#39; matches &#39;*copilot*&#39;")
    end

    it "renders a single group as a plain AND" do
      create(:filter, target: target)

      get "/admin/targets/#{target.id}", headers: auth_headers

      expect(response.body).to include("Delivers if <strong>ALL</strong> filters match")
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

    it "renders a group input for each filter and the new-row template" do
      create(:filter, target: target, group_key: "ci-fail")

      get "/admin/targets/#{target.id}/edit", headers: auth_headers

      expect(response.body).to include('name="target[filters_attributes][0][group_key]"')
      expect(response.body).to include('value="ci-fail"')
      expect(response.body).to include('name="target[filters_attributes][NEW_INDEX][group_key]"')
      expect(response.body).to include("Deliver if ANY group matches")
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

  describe "PATCH /admin/targets/:id with grouped filters" do
    let(:target) { create(:target) }
    let!(:ci_filter) do
      create(:filter, target: target, group_key: "ci-fail", filter_type: :header, field: "X-GitHub-Event",
        operator: :equals, value: "check_suite")
    end
    let!(:default_filter) { create(:filter, target: target) }

    it "moves filters between groups, adds new ones and removes deleted ones" do
      params = {
        target: {
          filters_attributes: {
            "0" => { id: ci_filter.id, group_key: "ci-failure" },
            "1" => { id: default_filter.id, _destroy: "true" },
            "1000" => { group_key: "ci-failure", filter_type: "payload", field: "$.check_suite.conclusion",
                        operator: "equals", value: "failure" },
            "1001" => { group_key: "ci-failure", filter_type: "header", field: "", operator: "exists", value: "" }
          }
        }
      }

      patch "/admin/targets/#{target.id}", params: params, headers: auth_headers

      expect(response).to redirect_to(admin_targets_path)
      expect(target.reload.filters.order(:id).pluck(:group_key, :field)).to eq([
        [ "ci-failure", "X-GitHub-Event" ],
        [ "ci-failure", "$.check_suite.conclusion" ]
      ])
    end

    it "rejects blanking the field of an existing filter" do
      params = { target: { filters_attributes: { "0" => { id: ci_filter.id, field: "" } } } }

      patch "/admin/targets/#{target.id}", params: params, headers: auth_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ci_filter.reload.field).to eq("X-GitHub-Event")
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
