# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Endpoints" do
  let(:auth_headers) do
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "changeme") }
  end
  let!(:reconciler) { create(:target, name: "Reconciler", url: "https://reconciler.example.com/hook", endpoints: []) }
  let!(:logger) { create(:target, name: "Logger", url: "https://logger.example.com/hook", endpoints: []) }

  def html
    Nokogiri::HTML(response.body)
  end

  it "requires authentication" do
    get "/admin/endpoints"

    expect(response).to have_http_status(:unauthorized)
  end

  describe "GET /admin/endpoints" do
    it "lists endpoints with their receive URLs and targets" do
      deploys = create(:endpoint, name: "Deploys", slug: "deploys", targets: [ reconciler ])
      Endpoint.default

      get "/admin/endpoints", headers: auth_headers

      expect(response).to have_http_status(:ok)
      deploys_card = html.at_css("[data-endpoint='deploys']")
      expect(deploys_card.text).to include("Deploys", "http://www.example.com/webhooks/receive/deploys", "Reconciler")
      expect(deploys_card.at_css("[data-clipboard-text-value]")["data-clipboard-text-value"])
        .to eq("http://www.example.com/webhooks/receive/deploys")
      expect(html.at_css("[data-endpoint='default']").text).to include("http://www.example.com/webhooks/receive", "default")
      expect(deploys.reload.targets).to eq([ reconciler ])
    end

    it "warns about endpoints without targets and hides deleting the default endpoint" do
      Endpoint.default

      get "/admin/endpoints", headers: auth_headers

      default_card = html.at_css("[data-endpoint='default']")
      expect(default_card.text).to include("No targets – webhooks are stored but not forwarded")
      expect(default_card.at_css("form[method='post'] input[value='delete']")).to be_nil
    end
  end

  describe "GET /admin/endpoints/:id" do
    it "shows the URL, targets and recent activity" do
      endpoint = create(:endpoint, name: "Deploys", slug: "deploys", description: "Posted by the deploy bot", targets: [ logger ])
      create(:webhook, endpoint: endpoint, received_at: 1.hour.ago)

      get "/admin/endpoints/#{endpoint.id}", headers: auth_headers

      expect(response.body).to include("http://www.example.com/webhooks/receive/deploys", "Posted by the deploy bot", "Logger")
      expect(html.at_css("a[href='/admin/webhooks?endpoint_id=#{endpoint.id}']").text).to eq("1")
    end

    it "explains that an inactive endpoint rejects requests" do
      endpoint = create(:endpoint, :inactive)

      get "/admin/endpoints/#{endpoint.id}", headers: auth_headers

      expect(response.body).to include("This endpoint is inactive: requests to its URL get 404")
    end
  end

  describe "GET /admin/endpoints/new" do
    it "renders the form with every target to choose from" do
      get "/admin/endpoints/new", headers: auth_headers

      labels = html.css("input[name='endpoint[target_ids][]'][type='checkbox']").map { |input| input["value"] }
      expect(labels).to contain_exactly(reconciler.id.to_s, logger.id.to_s)
    end
  end

  describe "POST /admin/endpoints" do
    it "creates an endpoint attached to the selected targets" do
      post "/admin/endpoints", headers: auth_headers, params: {
        endpoint: { name: "GitHub Deploys", slug: "", description: "deploy bot", active: "1", target_ids: [ "", reconciler.id ] }
      }

      endpoint = Endpoint.find_by!(slug: "github-deploys")
      expect(response).to redirect_to(admin_endpoint_path(endpoint))
      expect(endpoint.targets).to eq([ reconciler ])
      expect(endpoint.description).to eq("deploy bot")
    end

    it "re-renders the form with errors for an invalid slug" do
      expect {
        post "/admin/endpoints", headers: auth_headers, params: { endpoint: { name: "Bad", slug: "bad/slug" } }
      }.not_to change(Endpoint, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("may only contain lowercase letters, digits and single dashes")
    end

    it "rejects a duplicate slug" do
      create(:endpoint, slug: "deploys")

      post "/admin/endpoints", headers: auth_headers, params: { endpoint: { name: "Deploys again", slug: "Deploys" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Slug has already been taken")
    end
  end

  describe "PATCH /admin/endpoints/:id" do
    let(:endpoint) { create(:endpoint, slug: "deploys", targets: [ reconciler ]) }

    it "replaces the attached targets" do
      patch "/admin/endpoints/#{endpoint.id}", headers: auth_headers,
        params: { endpoint: { target_ids: [ "", logger.id ] } }

      expect(response).to redirect_to(admin_endpoint_path(endpoint))
      expect(endpoint.reload.targets).to eq([ logger ])
    end

    it "detaches every target when all are unchecked" do
      patch "/admin/endpoints/#{endpoint.id}", headers: auth_headers, params: { endpoint: { target_ids: [ "" ] } }

      expect(endpoint.reload.targets).to be_empty
    end

    it "does not change the default endpoint's slug" do
      default_endpoint = Endpoint.default

      patch "/admin/endpoints/#{default_endpoint.id}", headers: auth_headers, params: { endpoint: { slug: "legacy" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(default_endpoint.reload.slug).to eq("default")
    end

    it "renders the default endpoint's slug field disabled" do
      get "/admin/endpoints/#{Endpoint.default.id}/edit", headers: auth_headers

      expect(html.at_css("input[name='endpoint[slug]']")["disabled"]).not_to be_nil
    end

    it "can deactivate an endpoint" do
      patch "/admin/endpoints/#{endpoint.id}", headers: auth_headers, params: { endpoint: { active: "0" } }

      expect(endpoint.reload).not_to be_active
    end
  end

  describe "DELETE /admin/endpoints/:id" do
    it "deletes an endpoint and keeps its webhooks" do
      endpoint = create(:endpoint, targets: [ reconciler ])
      webhook = create(:webhook, endpoint: endpoint)

      delete "/admin/endpoints/#{endpoint.id}", headers: auth_headers

      expect(response).to redirect_to(admin_endpoints_path)
      expect(Endpoint.exists?(endpoint.id)).to be false
      expect(webhook.reload.endpoint).to be_nil
      expect(reconciler.reload).to be_persisted
    end

    it "refuses to delete the default endpoint" do
      default_endpoint = Endpoint.default

      delete "/admin/endpoints/#{default_endpoint.id}", headers: auth_headers

      expect(response).to redirect_to(admin_endpoint_path(default_endpoint))
      expect(flash[:alert]).to eq("The default endpoint cannot be deleted")
      expect(Endpoint.exists?(default_endpoint.id)).to be true
    end
  end
end
