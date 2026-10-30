# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP server" do
  let(:auth_headers) do
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "changeme")
    { "HTTP_AUTHORIZATION" => credentials, "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json, text/event-stream" }
  end

  def rpc(method, params = {}, id: 1, headers: auth_headers)
    post "/mcp", params: { jsonrpc: "2.0", id: id, method: method, params: params }.to_json, headers: headers
    response.parsed_body
  end

  def call_tool(name, arguments = {})
    result = rpc("tools/call", { name: name, arguments: arguments })["result"]
    [ JSON.parse(result["content"].first["text"]), result["isError"] ]
  end

  describe "transport" do
    it "requires authentication" do
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "ping" }.to_json, headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects requests from another origin" do
      rpc("ping", headers: auth_headers.merge("HTTP_ORIGIN" => "https://evil.example"))

      expect(response).to have_http_status(:forbidden)
    end

    it "accepts requests from its own origin" do
      rpc("ping", headers: auth_headers.merge("HTTP_ORIGIN" => "http://www.example.com"))

      expect(response).to have_http_status(:ok)
    end

    it "answers GET with 405 because it opens no stream" do
      get "/mcp", headers: auth_headers

      expect(response).to have_http_status(:method_not_allowed)
    end

    it "answers malformed JSON with a parse error" do
      post "/mcp", params: "{not json", headers: auth_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]["code"]).to eq(-32_700)
    end

    it "accepts notifications with 202 and no body" do
      post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json, headers: auth_headers

      expect(response).to have_http_status(:accepted)
      expect(response.body).to be_empty
    end

    it "rejects messages that are not JSON-RPC 2.0 requests" do
      post "/mcp", params: [ { jsonrpc: "2.0", id: 1, method: "ping" } ].to_json, headers: auth_headers

      expect(response.parsed_body["error"]["code"]).to eq(-32_600)
    end
  end

  describe "initialize" do
    it "agrees on a supported protocol version and announces tools" do
      body = rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "spec", version: "1" } })

      expect(body["id"]).to eq(1)
      expect(body["result"]["protocolVersion"]).to eq("2025-06-18")
      expect(body["result"]["capabilities"]).to eq("tools" => { "listChanged" => false })
      expect(body["result"]["serverInfo"]).to eq("name" => "hookshot", "version" => Hookshot::VERSION)
    end

    it "offers its latest version when the requested one is unsupported" do
      body = rpc("initialize", { protocolVersion: "1999-01-01" })

      expect(body["result"]["protocolVersion"]).to eq(Mcp::Server::PROTOCOL_VERSIONS.first)
    end
  end

  it "answers ping" do
    expect(rpc("ping", id: "abc")).to eq("jsonrpc" => "2.0", "id" => "abc", "result" => {})
  end

  it "reports unknown methods" do
    expect(rpc("resources/list")["error"]["code"]).to eq(-32_601)
  end

  describe "tools/list" do
    it "lists every tool with an object input schema" do
      tools = rpc("tools/list")["result"]["tools"]

      expect(tools.map { |tool| tool["name"] }).to eq(Mcp::Tools::DEFINITIONS.keys)
      expect(tools).to all(include("description" => be_present, "inputSchema" => include("type" => "object")))
      expect(tools.find { |tool| tool["name"] == "retry_dispatch" }["inputSchema"]["required"]).to eq([ "id" ])
    end
  end

  describe "tools/call" do
    let!(:target) { create(:target, name: "Alpha", custom_headers: { "Authorization" => "Bearer secret" }) }
    let!(:webhook) { create(:webhook) }

    it "reports unknown tools as invalid params" do
      expect(rpc("tools/call", { name: "drop_database" })["error"]["code"]).to eq(-32_602)
    end

    it "reports missing arguments as a tool error" do
      data, error = call_tool("get_webhook")

      expect(error).to be true
      expect(data["error"]).to eq("Missing arguments: id")
    end

    it "reports missing records as a tool error" do
      data, error = call_tool("get_webhook", { id: 0 })

      expect(error).to be true
      expect(data["error"]).to include("Couldn't find Webhook")
    end

    it "reports non-integer ids as a tool error" do
      data, error = call_tool("get_webhook", { id: "abc" })

      expect(error).to be true
      expect(data["error"]).to eq("id must be an integer")
    end

    describe "list_endpoints" do
      it "lists endpoints with their target ids" do
        data, error = call_tool("list_endpoints")

        expect(error).to be false
        expect(data).to contain_exactly(include("slug" => "default", "active" => true, "target_ids" => [ target.id ]))
      end
    end

    describe "list_targets" do
      it "lists targets without their custom headers" do
        data, = call_tool("list_targets")

        expect(data).to contain_exactly(include("id" => target.id, "name" => "Alpha", "endpoint_slugs" => [ "default" ]))
        expect(data.first).not_to have_key("custom_headers")
      end
    end

    describe "set_target_active" do
      it "deactivates a target" do
        data, error = call_tool("set_target_active", { id: target.id, active: false })

        expect(error).to be false
        expect(data).to include("id" => target.id, "active" => false)
        expect(target.reload.active).to be false
      end

      it "requires a boolean" do
        data, error = call_tool("set_target_active", { id: target.id, active: "no" })

        expect(error).to be true
        expect(data["error"]).to eq("active must be true or false")
        expect(target.reload.active).to be true
      end
    end

    describe "list_webhooks" do
      let!(:other_endpoint) { create(:endpoint) }
      let!(:other_webhook) { create(:webhook, endpoint: other_endpoint, payload: { event: "order.paid" }.to_json, received_at: 1.hour.ago) }

      it "lists webhooks newest first" do
        data, = call_tool("list_webhooks")

        expect(data.map { |row| row["id"] }).to eq([ webhook.id, other_webhook.id ])
        expect(data.first).to include("endpoint_slug" => "default", "dispatch_stats" => { "success" => 0, "total" => 0 })
      end

      it "filters by endpoint, search text and limit" do
        expect(call_tool("list_webhooks", { endpoint_id: other_endpoint.id }).first.map { |row| row["id"] }).to eq([ other_webhook.id ])
        expect(call_tool("list_webhooks", { query: "order.paid" }).first.map { |row| row["id"] }).to eq([ other_webhook.id ])
        expect(call_tool("list_webhooks", { limit: 1 }).first.size).to eq(1)
      end
    end

    describe "get_webhook" do
      it "shows the webhook with headers, payload and deliveries" do
        delivery = create(:delivery, :failed, webhook: webhook, target: target)

        data, = call_tool("get_webhook", { id: webhook.id })

        expect(data).to include("id" => webhook.id, "headers" => webhook.headers, "payload" => webhook.payload, "payload_truncated" => false)
        expect(data["deliveries"]).to contain_exactly(include("id" => delivery.id, "status" => "failed", "target_name" => "Alpha"))
      end

      it "truncates large payloads" do
        large = create(:webhook, payload: "a" * (Mcp::Tools::PAYLOAD_PREVIEW_BYTES + 1))

        data, = call_tool("get_webhook", { id: large.id })

        expect(data["payload"].bytesize).to eq(Mcp::Tools::PAYLOAD_PREVIEW_BYTES)
        expect(data["payload_truncated"]).to be true
      end
    end

    describe "replay_webhook" do
      it "dispatches the webhook to the endpoint's active targets" do
        data = nil

        expect { data, = call_tool("replay_webhook", { id: webhook.id }) }.to have_enqueued_job(DispatchJob)
        expect(data).to eq("id" => webhook.id, "replayed_to_endpoint" => "default")
      end

      it "refuses webhooks whose endpoint was deleted" do
        webhook.update!(endpoint: nil)

        data, error = call_tool("replay_webhook", { id: webhook.id })

        expect(error).to be true
        expect(data["error"]).to include("its endpoint was deleted")
      end
    end

    describe "list_dispatches" do
      let!(:failed) { create(:delivery, :failed, webhook: webhook, target: target) }
      let!(:succeeded) { create(:delivery, :success, webhook: webhook, target: create(:target)) }

      it "filters by status and target" do
        expect(call_tool("list_dispatches", { status: "failed" }).first.map { |row| row["id"] }).to eq([ failed.id ])
        expect(call_tool("list_dispatches", { target_id: target.id }).first.map { |row| row["id"] }).to eq([ failed.id ])
        expect(call_tool("list_dispatches").first.size).to eq(2)
      end

      it "rejects unknown statuses" do
        data, error = call_tool("list_dispatches", { status: "lost" })

        expect(error).to be true
        expect(data["error"]).to eq("Unknown status: lost")
      end
    end

    describe "retry_dispatch" do
      it "queues a retryable delivery" do
        delivery = create(:delivery, :retryable, webhook: webhook, target: target)
        data = nil

        expect { data, = call_tool("retry_dispatch", { id: delivery.id }) }.to have_enqueued_job(DispatchJob).with(delivery.id)
        expect(data).to eq("id" => delivery.id, "queued" => true)
        expect(delivery.reload).to be_pending
      end

      it "refuses deliveries that cannot be retried" do
        delivery = create(:delivery, :success, webhook: webhook, target: target)

        data, error = call_tool("retry_dispatch", { id: delivery.id })

        expect(error).to be true
        expect(data["error"]).to include("cannot be retried")
      end
    end
  end
end
