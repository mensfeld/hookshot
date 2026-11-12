# frozen_string_literal: true

require "rails_helper"

RSpec.describe Endpoint do
  include ActiveSupport::Testing::TimeHelpers

  describe "associations" do
    it { is_expected.to have_many(:endpoint_targets).dependent(:destroy) }
    it { is_expected.to have_many(:targets).through(:endpoint_targets) }
    it { is_expected.to have_many(:webhooks).dependent(:nullify) }
  end

  describe "validations" do
    subject { build(:endpoint) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:slug).ignoring_case_sensitivity }
    it { is_expected.to validate_length_of(:slug).is_at_most(Endpoint::SLUG_MAX_LENGTH) }

    it "accepts lowercase letters, digits and single dashes" do
      expect(build(:endpoint, slug: "github-deploys-2")).to be_valid
    end

    [ "-deploys", "deploys-", "deploy--s", "deploys/prod", "déploys", "deploys.prod" ].each do |slug|
      it "rejects #{slug.inspect}" do
        endpoint = build(:endpoint, slug: slug)

        expect(endpoint).not_to be_valid
        expect(endpoint.errors[:slug]).to include("may only contain lowercase letters, digits and single dashes")
      end
    end
  end

  describe "slug normalization" do
    it "strips, downcases and turns spaces and underscores into dashes" do
      expect(build(:endpoint, slug: "  GitHub_Deploys Prod ").slug).to eq("github-deploys-prod")
    end

    it "derives the slug from the name when left blank" do
      endpoint = create(:endpoint, name: "GitHub Deploys!", slug: "")

      expect(endpoint.slug).to eq("github-deploys")
    end

    it "derives a valid slug from a long name" do
      endpoint = create(:endpoint, name: "a #{'very ' * 20}long name", slug: nil)

      expect(endpoint.slug.length).to be <= Endpoint::SLUG_MAX_LENGTH
      expect(endpoint.slug).to match(Endpoint::SLUG_FORMAT)
    end

    it "keeps an explicit slug" do
      expect(create(:endpoint, name: "GitHub Deploys", slug: "deploys").slug).to eq("deploys")
    end

    it "requires a slug when the name gives none" do
      endpoint = build(:endpoint, name: "!!!", slug: "")

      expect(endpoint).not_to be_valid
      expect(endpoint.errors[:slug]).to include("can't be blank")
    end
  end

  describe ".default" do
    it "creates the default endpoint when missing" do
      expect { described_class.default }.to change(described_class, :count).by(1)
      expect(described_class.default).to have_attributes(slug: "default", name: "Default", active: true)
    end

    it "returns the existing default endpoint" do
      existing = described_class.default

      expect { expect(described_class.default).to eq(existing) }.not_to change(described_class, :count)
    end

    it "returns the default endpoint even when it is inactive" do
      existing = described_class.default
      existing.update!(active: false)

      expect(described_class.default).to eq(existing)
    end

    it "falls back to the existing row when another request created it concurrently" do
      existing = described_class.default
      lookups = 0
      # The first lookup misses as if the row did not exist yet; later ones (the fallback) see it
      allow(described_class).to receive(:find_by).and_wrap_original do |original, *args|
        (lookups += 1) == 1 ? nil : original.call(*args)
      end

      expect(described_class.default).to eq(existing)
    end
  end

  describe "#default?" do
    it "is true for the default endpoint" do
      expect(described_class.default).to be_default
    end

    it "is false for other endpoints" do
      expect(build(:endpoint)).not_to be_default
    end

    it "is true for a new record with the default slug" do
      expect(build(:endpoint, slug: "default")).to be_default
    end
  end

  describe "default endpoint protection" do
    let(:default_endpoint) { described_class.default }

    it "cannot be destroyed" do
      expect(default_endpoint.destroy).to be false
      expect(default_endpoint.errors[:base]).to include("The default endpoint cannot be deleted")
      expect(described_class.exists?(default_endpoint.id)).to be true
    end

    it "cannot have its slug changed" do
      expect(default_endpoint.update(slug: "legacy")).to be false
      expect(default_endpoint.errors[:slug]).to include("of the default endpoint cannot be changed")
    end

    it "can be renamed and deactivated" do
      expect(default_endpoint.update(name: "Legacy URL", active: false)).to be true
    end

    it "allows destroying other endpoints and keeps their webhooks" do
      endpoint = create(:endpoint)
      webhook = create(:webhook, endpoint: endpoint)
      target = create(:target, endpoints: [ endpoint ])

      expect(endpoint.destroy).to be_truthy
      expect(webhook.reload.endpoint).to be_nil
      expect(target.reload.endpoints).to be_empty
    end
  end

  describe ".active" do
    it "returns only active endpoints" do
      active = create(:endpoint)
      create(:endpoint, :inactive)

      expect(described_class.active).to contain_exactly(active)
    end
  end

  describe "#webhooks_count_24h and #last_received_at" do
    let(:endpoint) { create(:endpoint) }

    it "count recent webhooks and report the latest one" do
      create(:webhook, endpoint: endpoint, received_at: 2.days.ago)
      latest = create(:webhook, endpoint: endpoint, received_at: 1.hour.ago)
      create(:webhook, received_at: 1.minute.ago)

      expect(endpoint.webhooks_count_24h).to eq(1)
      expect(endpoint.last_received_at).to be_within(1.second).of(latest.received_at)
    end

    it "report nothing for an endpoint that never received a webhook" do
      expect(endpoint.webhooks_count_24h).to eq(0)
      expect(endpoint.last_received_at).to be_nil
    end
  end

  describe "signature verification settings" do
    it "verifies nothing without a preset" do
      endpoint = create(:endpoint, signature_preset: "")

      expect(endpoint).to have_attributes(verifier: nil, signature_preset: nil, verifies_signatures?: false)
    end

    it "stores no signature settings without a preset, so loading the endpoint allocates no extra strings" do
      endpoint = create(:endpoint, signature_preset: "", signing_secrets: "x", signature_algorithm: "sha512",
        signature_encoding: "hex", signature_format: "plain", signed_payload_template: "{body}", timestamp_tolerance: 60)

      values = endpoint.reload.attributes.values_at(*Endpoint::SIGNATURE_SETTINGS.map(&:to_s))
      expect(values).to all(be_nil)
    end

    it "clears the settings when verification is turned off" do
      endpoint = create(:endpoint, signature_preset: "stripe", signing_secrets: "x")

      endpoint.update!(signature_preset: "")

      expect(endpoint.reload).to have_attributes(signing_secrets: nil, signature_header: nil, signed_payload_template: nil)
    end

    it "fills blank Generic HMAC settings with SHA-256, hex, a plain header and {body}" do
      endpoint = create(:endpoint, signature_preset: "generic", signing_secrets: "x", signature_header: "X-Sig",
        signature_algorithm: "", signed_payload_template: "")

      expect(endpoint).to have_attributes(signature_algorithm: "sha256", signature_encoding: "hex",
        signature_format: "plain", signed_payload_template: "{body}")
    end

    it "fills in a named preset's settings and clears the ones it does not use" do
      endpoint = create(:endpoint, signature_preset: "github", signing_secrets: "x", signature_header: "X-Other",
        signature_encoding: "base64", timestamp_header: "X-Timestamp", timestamp_tolerance: 5)

      expect(endpoint).to have_attributes(
        verifier: "hmac", signature_header: "X-Hub-Signature-256", signature_encoding: "hex", signature_prefix: "sha256=",
        timestamp_header: nil, timestamp_tolerance: nil
      )
    end

    it "keeps the entered settings for Generic HMAC" do
      endpoint = create(:endpoint, signature_preset: "generic", signing_secrets: "x", signature_header: "X-Sig",
        signature_algorithm: "sha512", signature_encoding: "base64", signature_prefix: "")

      expect(endpoint).to have_attributes(verifier: "hmac", signature_header: "X-Sig", signature_algorithm: "sha512",
        signature_encoding: "base64", signature_prefix: nil)
    end

    it "requires a secret" do
      endpoint = build(:endpoint, signature_preset: "github", signing_secrets: " \n ")

      expect(endpoint).not_to be_valid
      expect(endpoint.errors[:signing_secrets]).to include("must contain at least one secret")
    end

    it "lists one secret per non-blank line" do
      expect(build(:endpoint, signing_secrets: "a\r\n\n b \n").signing_secrets_list).to eq(%w[a b])
    end

    it "rejects an unknown preset, algorithm, encoding or format" do
      endpoint = build(:endpoint, signature_preset: "generic", signing_secrets: "x", signature_header: "X-Sig",
        signature_algorithm: "md5", signature_encoding: "base32", signature_format: "json")
      endpoint.validate

      expect(endpoint.errors.attribute_names).to include(:signature_algorithm, :signature_encoding, :signature_format)
      expect(build(:endpoint, signature_preset: "acme", signing_secrets: "x")).not_to be_valid
    end

    it "requires the signature header and, for a key=value list, the signature key" do
      endpoint = build(:endpoint, signature_preset: "generic", signing_secrets: "x", signature_format: "key_value")
      endpoint.validate

      expect(endpoint.errors[:signature_header]).to include("can't be blank")
      expect(endpoint.errors[:signature_key]).to include("is required for a key=value signature header")
    end

    it "rejects unknown placeholders in the signed-content template" do
      endpoint = build(:endpoint, signature_preset: "generic", signing_secrets: "x", signature_header: "X-Sig",
        signed_payload_template: "{body}.{nonce}")

      expect(endpoint).not_to be_valid
      expect(endpoint.errors[:signed_payload_template]).to include("may only use {body}, {timestamp} and {header:Name} (letters, digits and dashes)")
    end

    it "rejects a template header name Rails cannot look up" do
      endpoint = build(:endpoint, signature_preset: "generic", signing_secrets: "x", signature_header: "X-Sig",
        signed_payload_template: "{header:X_Delivery}.{body}")

      expect(endpoint).not_to be_valid
    end

    it "strips spaces around the signature and timestamp header names" do
      endpoint = create(:endpoint, signature_preset: "generic", signing_secrets: "x", signature_header: " X-Signature ",
        timestamp_header: "X-T \n", timestamp_tolerance: 60)

      expect(endpoint).to have_attributes(signature_header: "X-Signature", timestamp_header: "X-T")
    end

    [ "X_Signature", "X:Signature", "X Signature" ].each do |name|
      it "rejects the signature header name #{name.inspect}" do
        endpoint = build(:endpoint, signature_preset: "generic", signing_secrets: "x", signature_header: name)

        expect(endpoint).not_to be_valid
        expect(endpoint.errors[:signature_header]).to include("may only contain letters, digits and dashes")
      end

      it "rejects the timestamp header name #{name.inspect}" do
        endpoint = build(:endpoint, signature_preset: "generic", signing_secrets: "x", signature_header: "X-Sig",
          timestamp_header: name, timestamp_tolerance: 60)

        expect(endpoint).not_to be_valid
        expect(endpoint.errors[:timestamp_header]).to include("may only contain letters, digits and dashes")
      end
    end

    it "rejects an unmatched brace in the signed-content template" do
      endpoint = build(:endpoint, signature_preset: "generic", signing_secrets: "x", signature_header: "X-Sig",
        signed_payload_template: "{")

      expect(endpoint).not_to be_valid
    end

    it "requires a timestamp source when the template signs a timestamp or a tolerance is set" do
      endpoint = build(:endpoint, signature_preset: "generic", signing_secrets: "x", signature_header: "X-Sig",
        timestamp_tolerance: 60)

      expect(endpoint).not_to be_valid
      expect(endpoint.errors[:timestamp_header]).to be_present

      endpoint.timestamp_header = "X-Timestamp"
      expect(endpoint).to be_valid
    end

    it "rejects a tolerance that is not a positive whole number" do
      endpoint = build(:endpoint, signature_preset: "generic", signing_secrets: "x", signature_header: "X-Sig",
        timestamp_header: "X-Timestamp", timestamp_tolerance: 0)
      expect(endpoint).not_to be_valid
    end

    it "counts verification failures" do
      endpoint = create(:endpoint)

      freeze_time do
        2.times { endpoint.record_verification_failure! }

        expect(endpoint.reload).to have_attributes(verification_failures_count: 2, last_verification_failed_at: Time.current)
      end
    end
  end
end
