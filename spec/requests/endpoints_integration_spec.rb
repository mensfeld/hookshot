# frozen_string_literal: true

require "rails_helper"

# End-to-end: one sending app posts identical payloads to different endpoint URLs, and each endpoint forwards to its
# own targets. Endpoints and targets are configured through the admin, webhooks are received and dispatched for real.
RSpec.describe "Endpoints end-to-end" do
  include ActiveJob::TestHelper

  let(:auth_headers) do
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "changeme") }
  end
  let(:payload) { { event: "card.updated", id: 42 }.to_json }

  let!(:legacy_stub) { stub_request(:post, "https://legacy.example.com/hook").to_return(status: 200) }
  let!(:deploy_stub) { stub_request(:post, "https://deploy.example.com/hook").to_return(status: 200) }
  let!(:tracker_stub) { stub_request(:post, "https://tracker.example.com/hook").to_return(status: 200) }
  let!(:audit_stub) { stub_request(:post, "https://audit.example.com/hook").to_return(status: 200) }

  def create_target(name, url, endpoint_ids)
    post "/admin/targets", headers: auth_headers,
      params: { target: { name: name, url: url, active: true, timeout: 30, endpoint_ids: [ "", *endpoint_ids ] } }
    Target.find_by!(name: name)
  end

  def create_endpoint(name, slug)
    post "/admin/endpoints", headers: auth_headers, params: { endpoint: { name: name, slug: slug, active: "1" } }
    Endpoint.find_by!(slug: slug)
  end

  def send_webhook(path)
    perform_enqueued_jobs do
      post path, params: payload, headers: { "CONTENT_TYPE" => "application/json" }
    end
    response
  end

  before do
    deploys = create_endpoint("Deploys", "deploys")
    tracker = create_endpoint("Tracker", "tracker")
    create_target("Legacy", "https://legacy.example.com/hook", [ Endpoint.default.id ])
    create_target("Deploy bot", "https://deploy.example.com/hook", [ deploys.id ])
    create_target("Tracker", "https://tracker.example.com/hook", [ tracker.id ])
    create_target("Audit log", "https://audit.example.com/hook", [ deploys.id, tracker.id ])
  end

  it "forwards the same payload to different targets depending on the URL it was sent to" do
    expect(send_webhook("/webhooks/receive/deploys")).to have_http_status(:ok)

    expect(deploy_stub).to have_been_requested.once
    expect(audit_stub).to have_been_requested.once
    expect(tracker_stub).not_to have_been_requested
    expect(legacy_stub).not_to have_been_requested

    expect(send_webhook("/webhooks/receive/tracker")).to have_http_status(:ok)

    expect(tracker_stub).to have_been_requested.once
    expect(audit_stub).to have_been_requested.twice
    expect(deploy_stub).to have_been_requested.once
    expect(WebMock).to have_requested(:post, "https://tracker.example.com/hook").with(body: payload)
  end

  it "keeps the old URL working for the targets on the default endpoint" do
    expect(send_webhook("/webhooks/receive")).to have_http_status(:ok)

    expect(legacy_stub).to have_been_requested.once
    [ deploy_stub, tracker_stub, audit_stub ].each { |stub| expect(stub).not_to have_been_requested }
  end

  it "records which endpoint received each webhook" do
    send_webhook("/webhooks/receive/deploys")
    send_webhook("/webhooks/receive")

    expect(Webhook.order(:id).map { |webhook| webhook.endpoint.slug }).to eq(%w[deploys default])
  end

  it "stops accepting webhooks once an endpoint is deactivated or deleted" do
    tracker = Endpoint.find_by!(slug: "tracker")
    patch "/admin/endpoints/#{tracker.id}", headers: auth_headers, params: { endpoint: { active: "0" } }
    expect(send_webhook("/webhooks/receive/tracker")).to have_http_status(:not_found)

    deploys = Endpoint.find_by!(slug: "deploys")
    delete "/admin/endpoints/#{deploys.id}", headers: auth_headers
    expect(send_webhook("/webhooks/receive/deploys")).to have_http_status(:not_found)

    [ deploy_stub, tracker_stub, audit_stub ].each { |stub| expect(stub).not_to have_been_requested }
  end

  it "re-routes future webhooks when a target is moved to another endpoint" do
    deploy_bot = Target.find_by!(name: "Deploy bot")
    patch "/admin/targets/#{deploy_bot.id}", headers: auth_headers,
      params: { target: { endpoint_ids: [ "", Endpoint.find_by!(slug: "tracker").id ] } }

    send_webhook("/webhooks/receive/tracker")

    expect(deploy_stub).to have_been_requested.once
  end
end
