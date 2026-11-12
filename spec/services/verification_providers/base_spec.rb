# frozen_string_literal: true

require "rails_helper"

RSpec.describe VerificationProviders::Base do
  subject(:provider) { described_class.new(build(:endpoint, signing_secrets: "a\nb")) }

  it "names the provider after its class" do
    expect(described_class.label).to eq("Base")
  end

  it "requires subclasses to implement #verified?" do
    expect { provider.verified?(nil) }.to raise_error(NotImplementedError, /must implement #verified\?/)
  end

  it "computes an HMAC over the parts in order" do
    expect(provider.send(:hmac, "sha256", "k", "a", "bc")).to eq(OpenSSL::HMAC.digest("sha256", "k", "abc"))
  end

  it "matches a signature against any expected one" do
    expect(provider.send(:secure_match?, %w[x y], "y")).to be(true)
    expect(provider.send(:secure_match?, %w[x y], "z")).to be(false)
  end

  it "reads the endpoint's secrets" do
    expect(provider.send(:secrets)).to eq(%w[a b])
  end
end
