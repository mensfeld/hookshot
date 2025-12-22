# frozen_string_literal: true

require "rails_helper"

RSpec.describe Delivery do
  describe "associations" do
    it { is_expected.to belong_to(:webhook) }
    it { is_expected.to belong_to(:target) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, success: 1, failed: 2, filtered: 3) }
  end

  describe "scopes" do
    describe ".recent_24h" do
      let!(:recent_delivery) { create(:delivery, created_at: 1.hour.ago) }
      let!(:old_delivery) { create(:delivery, created_at: 2.days.ago) }

      it "returns only deliveries from the last 24 hours" do
        expect(described_class.recent_24h).to include(recent_delivery)
        expect(described_class.recent_24h).not_to include(old_delivery)
      end
    end
  end

  describe "#increment_attempts!" do
    let(:delivery) { create(:delivery, attempts: 0) }

    it "increments the attempts counter" do
      expect { delivery.increment_attempts! }.to change { delivery.reload.attempts }.from(0).to(1)
    end
  end

  describe "#retryable?" do
    context "when failed with fewer than 5 attempts" do
      let(:delivery) { build(:delivery, :retryable) }

      it "returns true" do
        expect(delivery.retryable?).to be true
      end
    end

    context "when failed with 5 or more attempts" do
      let(:delivery) { build(:delivery, :failed) }

      it "returns false" do
        expect(delivery.retryable?).to be false
      end
    end

    context "when successful" do
      let(:delivery) { build(:delivery, :success) }

      it "returns false" do
        expect(delivery.retryable?).to be false
      end
    end

    context "when pending" do
      let(:delivery) { build(:delivery, status: :pending, attempts: 0) }

      it "returns false" do
        expect(delivery.retryable?).to be false
      end
    end
  end
end
