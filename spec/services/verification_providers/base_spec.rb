# frozen_string_literal: true

require "rails_helper"

RSpec.describe VerificationProviders::Base do
  let(:endpoint) { build(:endpoint, signing_secrets: "a\nb") }
  let(:hmac_provider) do
    Class.new(described_class) do
      def verified?(request)
        expected = secrets.map { |secret| hmac("sha256", secret, "x", request.raw_post).unpack1("H*") }
        secure_match?(expected, request.headers["X-Sig"].to_s)
      end
    end
  end

  def request_with(signature)
    env = Rack::MockRequest.env_for("/webhooks/receive", method: "POST", input: "yz")
    env["HTTP_X_SIG"] = signature
    ActionDispatch::Request.new(env)
  end

  it "names the provider after its class" do
    expect(described_class.label).to eq("Base")
  end

  it "requires subclasses to implement #verified?" do
    expect { described_class.new(endpoint).verified?(nil) }.to raise_error(NotImplementedError, /must implement #verified\?/)
  end

  it "accepts an HMAC over the parts in order made with any of the endpoint's secrets" do
    provider = hmac_provider.new(endpoint)

    expect(provider.verified?(request_with(OpenSSL::HMAC.hexdigest("sha256", "a", "xyz")))).to be(true)
    expect(provider.verified?(request_with(OpenSSL::HMAC.hexdigest("sha256", "b", "xyz")))).to be(true)
  end

  it "rejects an HMAC made with another secret or over other content" do
    provider = hmac_provider.new(endpoint)

    expect(provider.verified?(request_with(OpenSSL::HMAC.hexdigest("sha256", "c", "xyz")))).to be(false)
    expect(provider.verified?(request_with(OpenSSL::HMAC.hexdigest("sha256", "a", "yz")))).to be(false)
  end
end
