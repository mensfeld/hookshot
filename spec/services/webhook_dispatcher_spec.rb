# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookDispatcher do
  let(:webhook) { create(:webhook) }
  let(:dispatcher) { described_class.new(webhook) }

  describe "#dispatch_to_all_targets" do
    context "with active targets" do
      let!(:target1) { create(:target, active: true) }
      let!(:target2) { create(:target, active: true) }
      let!(:inactive_target) { create(:target, active: false) }

      it "creates deliveries for all active targets" do
        expect { dispatcher.dispatch_to_all_targets }
          .to change { Delivery.count }.by(2)
      end

      it "does not create deliveries for inactive targets" do
        dispatcher.dispatch_to_all_targets

        expect(Delivery.where(target: inactive_target)).to be_empty
      end

      it "enqueues dispatch jobs for passing filters" do
        expect { dispatcher.dispatch_to_all_targets }
          .to have_enqueued_job(DispatchJob).twice
      end
    end

    context "with no active targets" do
      let!(:inactive_target) { create(:target, active: false) }

      it "creates no deliveries" do
        expect { dispatcher.dispatch_to_all_targets }
          .not_to change { Delivery.count }
      end
    end
  end

  describe "#dispatch_to_target" do
    let(:target) { create(:target) }

    context "when filters pass" do
      it "creates a pending delivery" do
        delivery = dispatcher.dispatch_to_target(target)

        expect(delivery.status).to eq("pending")
      end

      it "enqueues a dispatch job" do
        expect { dispatcher.dispatch_to_target(target) }
          .to have_enqueued_job(DispatchJob)
      end
    end

    context "when filters fail" do
      let(:target) { create(:target, :with_filter) }
      let(:webhook) { create(:webhook, payload: '{}') }

      before do
        target.filters.first.update!(
          filter_type: :payload,
          field: "$.nonexistent",
          operator: :exists
        )
      end

      it "creates a filtered delivery" do
        delivery = dispatcher.dispatch_to_target(target)

        expect(delivery.status).to eq("filtered")
      end

      it "does not enqueue a dispatch job" do
        expect { dispatcher.dispatch_to_target(target) }
          .not_to have_enqueued_job(DispatchJob)
      end
    end

    it "returns the created delivery" do
      delivery = dispatcher.dispatch_to_target(target)

      expect(delivery).to be_a(Delivery)
      expect(delivery.webhook).to eq(webhook)
      expect(delivery.target).to eq(target)
    end
  end
end
