# frozen_string_literal: true

require "rails_helper"

RSpec.describe VerificationProviders::Github do
  subject(:provider) { described_class.new(build(:endpoint, verification_provider: "github", signing_secrets: secrets)) }

  let(:secrets) { "s3cret" }
  let(:body) { %({"zen":"Keep it logically awesome."}) }

  def request_with(signature)
    env = Rack::MockRequest.env_for("/webhooks/receive", method: "POST", input: body)
    env["HTTP_X_HUB_SIGNATURE_256"] = signature if signature
    ActionDispatch::Request.new(env)
  end

  def sign(secret, content = body)
    "sha256=#{OpenSSL::HMAC.hexdigest('sha256', secret, content)}"
  end

  it "is labelled GitHub" do
    expect(described_class.label).to eq("GitHub")
  end

  it "accepts a correct signature" do
    expect(provider.verified?(request_with(sign("s3cret")))).to be(true)
  end

  it "accepts an upper-case hex digest and surrounding spaces" do
    expect(provider.verified?(request_with(" #{sign('s3cret').upcase.sub('SHA256=', 'sha256=')} "))).to be(true)
  end

  it "rejects a signature made with another secret, over another body or without the prefix" do
    expect(provider.verified?(request_with(sign("other")))).to be(false)
    expect(provider.verified?(request_with(sign("s3cret", "#{body} ")))).to be(false)
    expect(provider.verified?(request_with(sign("s3cret").delete_prefix("sha256=")))).to be(false)
  end

  it "rejects a request without the header" do
    expect(provider.verified?(request_with(nil))).to be(false)
  end

  context "with several secrets" do
    let(:secrets) { "new\nold" }

    it "accepts a signature made with any of them" do
      expect(provider.verified?(request_with(sign("old")))).to be(true)
      expect(provider.verified?(request_with(sign("new")))).to be(true)
    end
  end

  context "with a non-ASCII body" do
    let(:body) { "caf\xC3\xA9".b }

    it "signs the raw body bytes" do
      expect(provider.verified?(request_with(sign("s3cret")))).to be(true)
    end
  end
end
