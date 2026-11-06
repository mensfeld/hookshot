# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookDispatcher do
  let(:webhook) { create(:webhook) }
  let(:dispatcher) { described_class.new(webhook) }

  describe "#dispatch" do
    context "with active targets on the webhook's endpoint" do
      let!(:target1) { create(:target, active: true) }
      let!(:target2) { create(:target, active: true) }
      let!(:inactive_target) { create(:target, active: false) }

      it "creates deliveries for the endpoint's active targets" do
        expect { dispatcher.dispatch }
          .to change { Delivery.count }.by(2)
      end

      it "does not create deliveries for inactive targets" do
        dispatcher.dispatch

        expect(Delivery.where(target: inactive_target)).to be_empty
      end

      it "enqueues dispatch jobs for passing filters" do
        expect { dispatcher.dispatch }
          .to have_enqueued_job(DispatchJob).twice
      end
    end

    context "with skip_routed" do
      let!(:routed_target) { create(:target) }
      let!(:new_target) { create(:target) }

      before { create(:delivery, webhook: webhook, target: routed_target) }

      it "creates deliveries only for targets without a delivery of this webhook" do
        expect { dispatcher.dispatch(skip_routed: true) }.to change(Delivery, :count).by(1)

        expect(Delivery.last.target).to eq(new_target)
      end

      it "still skips routed targets when the webhook also has a delivery of a deleted target" do
        create(:delivery, webhook: webhook, target: create(:target)).target.destroy!

        expect { dispatcher.dispatch(skip_routed: true) }.to change(Delivery, :count).by(1)
        expect(Delivery.last.target).to eq(new_target)
      end

      it "delivers to every target again without it (a replay)" do
        expect { dispatcher.dispatch }.to change(Delivery, :count).by(2)
      end
    end

    context "with targets attached to other endpoints" do
      let(:deploys) { create(:endpoint, slug: "deploys") }
      let!(:deploys_target) { create(:target, endpoints: [ deploys ]) }
      let!(:default_target) { create(:target) }
      let!(:unattached_target) { create(:target, :without_endpoints) }

      it "only dispatches to the targets of the endpoint that received the webhook" do
        dispatcher.dispatch

        expect(Delivery.pluck(:target_id)).to eq([ default_target.id ])
      end

      it "routes a webhook received on another endpoint to that endpoint's targets" do
        described_class.new(create(:webhook, endpoint: deploys)).dispatch

        expect(Delivery.pluck(:target_id)).to eq([ deploys_target.id ])
      end

      it "creates no delivery records at all for targets outside the endpoint" do
        dispatcher.dispatch

        expect(Delivery.where(target: [ deploys_target, unattached_target ])).to be_empty
      end
    end

    context "with a target attached to several endpoints" do
      let(:deploys) { create(:endpoint, slug: "deploys") }
      let!(:shared_target) { create(:target, endpoints: [ Endpoint.default, deploys ]) }

      it "receives webhooks from each of them" do
        described_class.new(create(:webhook)).dispatch
        described_class.new(create(:webhook, endpoint: deploys)).dispatch

        expect(Delivery.where(target: shared_target).count).to eq(2)
      end
    end

    context "when the webhook has no endpoint (it was deleted)" do
      let(:webhook) { create(:webhook, endpoint: nil) }

      before { create(:target) }

      it "creates no deliveries" do
        expect { dispatcher.dispatch }.not_to change { Delivery.count }
      end
    end

    context "with no active targets" do
      let!(:inactive_target) { create(:target, active: false) }

      it "creates no deliveries" do
        expect { dispatcher.dispatch }
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
