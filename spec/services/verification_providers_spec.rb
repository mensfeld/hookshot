# frozen_string_literal: true

require "rails_helper"

RSpec.describe VerificationProviders do
  let(:custom) { Class.new(VerificationProviders::Base) { def self.label = "Custom" } }

  after { described_class.instance_variable_get(:@providers).delete("custom") }

  it "ships the GitHub provider" do
    expect(described_class.all).to eq("github" => VerificationProviders::Github)
  end

  it "registers a provider under a string key" do
    described_class.register(:custom, custom)

    expect(described_class.fetch("custom")).to eq(custom)
    expect(described_class.all.keys).to eq(%w[github custom])
  end

  it "returns nil for an unknown or blank key" do
    expect([ described_class.fetch("acme"), described_class.fetch(nil) ]).to eq([ nil, nil ])
  end

  it "lets a registered provider verify an endpoint's requests" do
    described_class.register("custom", Class.new(VerificationProviders::Base) {
      def verified?(request) = secure_match?(secrets, request.headers["X-Token"].to_s)
    })
    endpoint = create(:endpoint, verification_provider: "custom", signing_secrets: "old\nnew")

    expect(endpoint.signature_verified?(ActionDispatch::Request.new("HTTP_X_TOKEN" => "new"))).to be(true)
    expect(endpoint.signature_verified?(ActionDispatch::Request.new("HTTP_X_TOKEN" => "bad"))).to be(false)
  end
end
