# frozen_string_literal: true

require "rails_helper"

RSpec.describe HttpClient do
  describe "#post" do
    let(:url) { "https://api.example.com/webhook" }
    let(:client) { described_class.new(url: url, timeout: 30) }
    let(:body) { '{"event": "test"}' }
    let(:headers) { { "Content-Type" => "application/json" } }

    context "with successful response" do
      before do
        stub_request(:post, url)
          .with(body: body, headers: headers)
          .to_return(status: 200, body: '{"status": "ok"}')
      end

      it "returns success result" do
        result = client.post(body: body, headers: headers)

        expect(result.success?).to be true
        expect(result.status_code).to eq(200)
        expect(result.body).to eq('{"status": "ok"}')
        expect(result.error).to be_nil
      end
    end

    context "with 4xx response" do
      before do
        stub_request(:post, url)
          .to_return(status: 400, body: '{"error": "Bad Request"}')
      end

      it "returns failure result" do
        result = client.post(body: body, headers: headers)

        expect(result.success?).to be false
        expect(result.status_code).to eq(400)
        expect(result.body).to eq('{"error": "Bad Request"}')
      end
    end

    context "with 5xx response" do
      before do
        stub_request(:post, url)
          .to_return(status: 500, body: '{"error": "Internal Server Error"}')
      end

      it "returns failure result" do
        result = client.post(body: body, headers: headers)

        expect(result.success?).to be false
        expect(result.status_code).to eq(500)
      end
    end

    context "with timeout" do
      before do
        stub_request(:post, url).to_timeout
      end

      it "returns failure result with timeout error" do
        result = client.post(body: body, headers: headers)

        expect(result.success?).to be false
        expect(result.status_code).to be_nil
        expect(result.error).to include("Timeout")
      end
    end

    context "with connection error" do
      before do
        stub_request(:post, url).to_raise(SocketError.new("Connection refused"))
      end

      it "returns failure result with connection error" do
        result = client.post(body: body, headers: headers)

        expect(result.success?).to be false
        expect(result.status_code).to be_nil
        expect(result.error).to include("Connection error")
      end
    end

    context "with very long response body" do
      before do
        long_body = "x" * 20_000
        stub_request(:post, url)
          .to_return(status: 200, body: long_body)
      end

      it "truncates the response body" do
        result = client.post(body: body, headers: headers)

        expect(result.body.length).to be <= 10_003 # 10000 + "..."
      end
    end

    context "with HTTP (non-SSL) URL" do
      let(:url) { "http://api.example.com/webhook" }

      before do
        stub_request(:post, url)
          .to_return(status: 200, body: '{"status": "ok"}')
      end

      it "works without SSL" do
        result = client.post(body: body, headers: headers)

        expect(result.success?).to be true
      end
    end

    context "with nil response body" do
      before do
        stub_request(:post, url)
          .to_return(status: 204, body: nil)
      end

      it "handles nil body gracefully" do
        result = client.post(body: body, headers: headers)

        expect(result.success?).to be true
        expect(result.body).to be_nil
      end
    end
  end
end
