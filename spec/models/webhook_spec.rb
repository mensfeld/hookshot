# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhook do
  describe "validations" do
    it { is_expected.to validate_presence_of(:content_type) }
    it { is_expected.to validate_presence_of(:source_ip) }
    it { is_expected.to validate_presence_of(:received_at) }
  end

  describe "associations" do
    it { is_expected.to have_many(:deliveries).dependent(:destroy) }
  end

  describe "scopes" do
    describe ".today" do
      let!(:today_webhook) { create(:webhook, received_at: Time.current) }
      let!(:yesterday_webhook) { create(:webhook, received_at: 1.day.ago) }

      it "returns only today's webhooks" do
        expect(described_class.today).to include(today_webhook)
        expect(described_class.today).not_to include(yesterday_webhook)
      end
    end

    describe ".older_than" do
      let!(:recent_webhook) { create(:webhook, received_at: 10.days.ago) }
      let!(:old_webhook) { create(:webhook, received_at: 40.days.ago) }

      it "returns webhooks older than specified days" do
        expect(described_class.older_than(30)).to include(old_webhook)
        expect(described_class.older_than(30)).not_to include(recent_webhook)
      end
    end
  end

  describe "#payload_size" do
    context "with payload" do
      let(:webhook) { build(:webhook, payload: "test payload") }

      it "returns the bytesize of the payload" do
        expect(webhook.payload_size).to eq("test payload".bytesize)
      end
    end

    context "without payload" do
      let(:webhook) { build(:webhook, :without_payload) }

      it "returns 0" do
        expect(webhook.payload_size).to eq(0)
      end
    end
  end

  describe "#dispatch_stats" do
    let(:webhook) { create(:webhook) }
    let(:target) { create(:target) }

    before do
      create(:delivery, :success, webhook: webhook, target: target)
      create(:delivery, :failed, webhook: webhook, target: target)
    end

    it "returns success and total counts" do
      stats = webhook.dispatch_stats
      expect(stats[:success]).to eq(1)
      expect(stats[:total]).to eq(2)
    end
  end
end
