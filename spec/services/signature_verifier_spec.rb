# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignatureVerifier do
  include ActiveSupport::Testing::TimeHelpers

  subject(:verifier) { described_class.new(endpoint) }

  let(:body) { "{\"event\":\"push\",\"name\":\"Jos\xE9\"}".b }
  let(:secret) { "s3cret" }
  let(:now) { Time.current.to_i }

  def request_with(headers, raw_body = body)
    env = headers.transform_keys { |name| "HTTP_#{name.upcase.tr('-', '_')}" }
    ActionDispatch::Request.new(Rack::MockRequest.env_for("/webhooks/receive", method: "POST", input: raw_body, **env))
  end

  def hmac(content, key = secret, algorithm = "sha256")
    OpenSSL::HMAC.hexdigest(algorithm, key, content)
  end

  def build_endpoint(preset, **settings)
    create(:endpoint, signature_preset: preset, signing_secrets: secret, **settings)
  end

  describe "GitHub preset" do
    let(:endpoint) { build_endpoint("github") }

    it "accepts a signature over the raw body bytes" do
      expect(verifier.verified?(request_with("X-Hub-Signature-256" => "sha256=#{hmac(body)}"))).to be(true)
    end

    it "accepts an uppercase hex signature" do
      expect(verifier.verified?(request_with("X-Hub-Signature-256" => "sha256=#{hmac(body).upcase}"))).to be(true)
    end

    it "rejects a signature made with another secret" do
      expect(verifier.verified?(request_with("X-Hub-Signature-256" => "sha256=#{hmac(body, 'other')}"))).to be(false)
    end

    it "rejects a signature of another body" do
      expect(verifier.verified?(request_with("X-Hub-Signature-256" => "sha256=#{hmac('{}')}"))).to be(false)
    end

    it "rejects a request without the signature header" do
      expect(verifier.verified?(request_with({}))).to be(false)
    end
  end

  describe "Stripe preset" do
    let(:endpoint) { build_endpoint("stripe") }

    def stripe_header(timestamp, *signatures)
      ([ "t=#{timestamp}" ] + signatures.map { |signature| "v1=#{signature}" }).join(",")
    end

    it "accepts a v1 signature over {timestamp}.{body}" do
      header = stripe_header(now, hmac("#{now}.".b + body))

      expect(verifier.verified?(request_with("Stripe-Signature" => header))).to be(true)
    end

    it "accepts the header when any of several v1 signatures matches" do
      header = stripe_header(now, hmac("other"), hmac("#{now}.".b + body))

      expect(verifier.verified?(request_with("Stripe-Signature" => header))).to be(true)
    end

    it "rejects a timestamp outside the tolerance" do
      old = now - 301
      header = stripe_header(old, hmac("#{old}.".b + body))

      expect(verifier.verified?(request_with("Stripe-Signature" => header))).to be(false)
    end

    it "rejects a header without a timestamp" do
      expect(verifier.verified?(request_with("Stripe-Signature" => "v1=#{hmac(".".b + body)}"))).to be(false)
    end

    it "rejects a header without a v1 signature" do
      expect(verifier.verified?(request_with("Stripe-Signature" => "t=#{now},v0=#{hmac("#{now}.".b + body)}"))).to be(false)
    end
  end

  describe "Slack preset" do
    let(:endpoint) { build_endpoint("slack") }

    it "accepts a v0 signature over v0:{timestamp}:{body}" do
      headers = { "X-Slack-Request-Timestamp" => now.to_s, "X-Slack-Signature" => "v0=#{hmac("v0:#{now}:".b + body)}" }

      expect(verifier.verified?(request_with(headers))).to be(true)
    end

    it "accepts a timestamp at the edge of the tolerance" do
      travel_to(Time.current) do
        edge = Time.current.to_i + 300
        headers = { "X-Slack-Request-Timestamp" => edge.to_s, "X-Slack-Signature" => "v0=#{hmac("v0:#{edge}:".b + body)}" }

        expect(verifier.verified?(request_with(headers))).to be(true)
      end
    end

    it "rejects a timestamp further in the future than the tolerance" do
      travel_to(Time.current) do
        ahead = Time.current.to_i + 301
        headers = { "X-Slack-Request-Timestamp" => ahead.to_s, "X-Slack-Signature" => "v0=#{hmac("v0:#{ahead}:".b + body)}" }

        expect(verifier.verified?(request_with(headers))).to be(false)
      end
    end

    it "rejects a replayed request older than the tolerance" do
      old = now - 600
      headers = { "X-Slack-Request-Timestamp" => old.to_s, "X-Slack-Signature" => "v0=#{hmac("v0:#{old}:".b + body)}" }

      expect(verifier.verified?(request_with(headers))).to be(false)
    end

    it "rejects a non-numeric timestamp" do
      headers = { "X-Slack-Request-Timestamp" => "soon", "X-Slack-Signature" => "v0=#{hmac('v0:soon:'.b + body)}" }

      expect(verifier.verified?(request_with(headers))).to be(false)
    end
  end

  describe "Shopify preset" do
    let(:endpoint) { build_endpoint("shopify") }

    it "accepts a base64 signature over the body" do
      signature = [ OpenSSL::HMAC.digest("sha256", secret, body) ].pack("m0")

      expect(verifier.verified?(request_with("X-Shopify-Hmac-Sha256" => signature))).to be(true)
    end

    it "rejects the hex form of the signature" do
      expect(verifier.verified?(request_with("X-Shopify-Hmac-Sha256" => hmac(body)))).to be(false)
    end
  end

  describe "Generic HMAC" do
    let(:endpoint) do
      build_endpoint(
        "generic", signature_header: "X-Signature", signature_algorithm: "sha512", signature_encoding: "hex",
        signed_payload_template: "{header:X-Delivery}|{body}"
      )
    end

    it "signs the content built from the template" do
      headers = { "X-Delivery" => "abc", "X-Signature" => hmac("abc|".b + body, secret, "sha512") }

      expect(verifier.verified?(request_with(headers))).to be(true)
    end

    it "rejects a request missing a header the template names" do
      expect(verifier.verified?(request_with("X-Signature" => hmac("|".b + body, secret, "sha512")))).to be(false)
    end

    it "supports SHA-1" do
      endpoint.update!(signature_algorithm: "sha1", signed_payload_template: "{body}")

      expect(verifier.verified?(request_with("X-Signature" => hmac(body, secret, "sha1")))).to be(true)
    end

    it "verifies a request whose header names were entered with surrounding spaces" do
      endpoint.update!(signature_header: " X-Signature ", signed_payload_template: "{body}", timestamp_header: "X-T ",
        timestamp_tolerance: 60)

      expect(verifier.verified?(request_with("X-Signature" => hmac(body, secret, "sha512"), "X-T" => now.to_s))).to be(true)
    end

    it "checks a timestamp header against the tolerance without signing it" do
      endpoint.update!(signed_payload_template: "{body}", timestamp_header: "X-Timestamp", timestamp_tolerance: 60)
      signature = hmac(body, secret, "sha512")

      expect(verifier.verified?(request_with("X-Signature" => signature, "X-Timestamp" => now.to_s))).to be(true)
      expect(verifier.verified?(request_with("X-Signature" => signature, "X-Timestamp" => (now - 61).to_s))).to be(false)
      expect(verifier.verified?(request_with("X-Signature" => signature))).to be(false)
    end
  end

  describe "secret rotation" do
    let(:endpoint) { build_endpoint("github", signing_secrets: "new-secret\n  old-secret  \n\n") }

    it "accepts a signature made with any configured secret" do
      %w[new-secret old-secret].each do |key|
        expect(verifier.verified?(request_with("X-Hub-Signature-256" => "sha256=#{hmac(body, key)}"))).to be(true)
      end
    end

    it "rejects a secret that was removed" do
      endpoint.update!(signing_secrets: "new-secret")

      expect(verifier.verified?(request_with("X-Hub-Signature-256" => "sha256=#{hmac(body, 'old-secret')}"))).to be(false)
    end
  end
end
