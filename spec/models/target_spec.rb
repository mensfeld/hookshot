# frozen_string_literal: true

require "rails_helper"

RSpec.describe Target do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:url) }
    it { is_expected.to validate_numericality_of(:timeout).is_greater_than(0).is_less_than_or_equal_to(300) }

    describe "url format" do
      it "accepts valid HTTP URLs" do
        target = build(:target, url: "http://example.com/webhook")
        expect(target).to be_valid
      end

      it "accepts valid HTTPS URLs" do
        target = build(:target, url: "https://example.com/webhook")
        expect(target).to be_valid
      end

      it "rejects invalid URLs" do
        target = build(:target, url: "not-a-url")
        expect(target).not_to be_valid
        expect(target.errors[:url]).to be_present
      end
    end
  end

  describe "associations" do
    it { is_expected.to have_many(:filters).dependent(:destroy) }
    it { is_expected.to have_many(:deliveries).dependent(:nullify) }
  end

  describe "scopes" do
    describe ".active" do
      let!(:active_target) { create(:target, active: true) }
      let!(:inactive_target) { create(:target, :inactive) }

      it "returns only active targets" do
        expect(described_class.active).to include(active_target)
        expect(described_class.active).not_to include(inactive_target)
      end
    end
  end

  describe "#success_rate_24h" do
    let(:target) { create(:target) }
    let(:webhook) { create(:webhook) }

    context "with no recent deliveries" do
      it "returns 0" do
        expect(target.success_rate_24h).to eq(0)
      end
    end

    context "with recent deliveries" do
      before do
        create(:delivery, :success, target: target, webhook: webhook, created_at: 1.hour.ago)
        create(:delivery, :success, target: target, webhook: webhook, created_at: 2.hours.ago)
        create(:delivery, :failed, target: target, webhook: webhook, created_at: 3.hours.ago)
      end

      it "calculates the success rate" do
        expect(target.success_rate_24h).to eq(66.7)
      end
    end
  end

  describe "#filter_count" do
    let(:target) { create(:target) }

    before do
      create_list(:filter, 3, target: target)
    end

    it "returns the count of filters" do
      expect(target.filter_count).to eq(3)
    end
  end
end
