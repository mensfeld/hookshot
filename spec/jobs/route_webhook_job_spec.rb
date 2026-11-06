# frozen_string_literal: true

require "rails_helper"

RSpec.describe RouteWebhookJob do
  include ActiveJob::TestHelper

  let(:webhook) { create(:webhook) }

  describe "#perform" do
    let!(:target) { create(:target, active: true) }
    let!(:other_target) { create(:target, active: true) }

    it "creates a pending delivery for each active target of the endpoint" do
      expect { described_class.perform_now(webhook.id) }.to change(Delivery, :count).by(2)

      expect(Delivery.where(webhook: webhook).pluck(:target_id)).to contain_exactly(target.id, other_target.id)
      expect(Delivery.where(webhook: webhook)).to all(be_pending)
    end

    it "enqueues a dispatch job for each delivery" do
      expect { described_class.perform_now(webhook.id) }.to have_enqueued_job(DispatchJob).twice
    end

    it "does not deliver twice when run again" do
      described_class.perform_now(webhook.id)

      expect { described_class.perform_now(webhook.id) }.not_to change(Delivery, :count)
    end

    it "routes only the remaining targets after a partial run" do
      create(:delivery, webhook: webhook, target: target)

      expect { described_class.perform_now(webhook.id) }.to change(Delivery, :count).by(1)
      expect(Delivery.last.target).to eq(other_target)
    end

    it "discards the job when the webhook no longer exists" do
      expect { described_class.perform_now(0) }.not_to raise_error
      expect(Delivery.count).to eq(0)
    end

    it "schedules a retry when routing fails" do
      allow(WebhookDispatcher).to receive(:new).and_raise(ActiveRecord::StatementInvalid, "database is locked")

      expect { described_class.perform_now(webhook.id) }.to have_enqueued_job(described_class).with(webhook.id)
    end
  end

  it "runs ahead of dispatch jobs in the default queue" do
    expect(described_class.new.queue_name).to eq("default")
    expect(described_class.new.priority).to be < DispatchJob.new.priority.to_i
  end
end
