# frozen_string_literal: true

require "rails_helper"

RSpec.describe CleanupJob do
  describe "#perform" do
    let!(:old_webhook) { create(:webhook, received_at: 31.days.ago) }
    let!(:recent_webhook) { create(:webhook, received_at: 1.day.ago) }

    it "deletes webhooks older than retention period" do
      expect { described_class.new.perform }
        .to change { Webhook.count }.by(-1)

      expect(Webhook.exists?(old_webhook.id)).to be false
    end

    it "keeps webhooks within retention period" do
      described_class.new.perform

      expect(Webhook.exists?(recent_webhook.id)).to be true
    end

    it "respects custom RETENTION_DAYS" do
      allow(Hookshot::Settings).to receive(:retention_days).and_return(7)

      old_within_custom = create(:webhook, received_at: 6.days.ago)
      old_beyond_custom = create(:webhook, received_at: 8.days.ago)

      described_class.new.perform

      expect(Webhook.exists?(old_within_custom.id)).to be true
      expect(Webhook.exists?(old_beyond_custom.id)).to be false
    end

    it "deletes the deliveries of old webhooks and keeps the others" do
      old_delivery = create(:delivery, webhook: old_webhook)
      recent_delivery = create(:delivery, webhook: recent_webhook)

      described_class.new.perform

      expect(Delivery.exists?(old_delivery.id)).to be false
      expect(Delivery.exists?(recent_delivery.id)).to be true
    end

    it "deletes across several batches" do
      stub_const("#{described_class}::BATCH_SIZE", 2)
      stub_const("#{described_class}::PAUSE", 0)
      create_list(:webhook, 4, received_at: 40.days.ago)

      expect { described_class.new.perform }.to change { Webhook.count }.by(-5)
      expect(Webhook.exists?(recent_webhook.id)).to be true
    end

    it "logs the number of deleted webhooks" do
      expect(Rails.logger).to receive(:info).with(/Deleted 1 webhooks older than 30 days/)

      described_class.new.perform
    end
  end
end
