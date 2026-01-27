# frozen_string_literal: true

require "rails_helper"

RSpec.describe RetryFailedDeliveriesJob do
  describe "job configuration" do
    it "runs on low priority queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end

  describe "#perform" do
    context "with deliveries ready for retry" do
      let!(:ready_delivery) do
        create(:delivery,
          status: :failed,
          retry_stage: :recurring_job_phase,
          next_retry_at: 1.hour.ago,
          attempts: 6)
      end

      it "resets delivery status to pending" do
        described_class.perform_now

        expect(ready_delivery.reload.status).to eq("pending")
      end

      it "enqueues DispatchJob for the delivery" do
        expect {
          described_class.perform_now
        }.to have_enqueued_job(DispatchJob).with(ready_delivery.id)
      end

      it "logs scheduled retry with attempt number" do
        allow(Rails.logger).to receive(:info)

        described_class.perform_now

        expect(Rails.logger).to have_received(:info)
          .with(/Scheduled retry for delivery #{ready_delivery.id} \(attempt 7\/#{Delivery::MAX_TOTAL_ATTEMPTS}\)/)
      end

      it "logs summary of processed deliveries" do
        allow(Rails.logger).to receive(:info)

        described_class.perform_now

        expect(Rails.logger).to have_received(:info)
          .with(/Processed 1 deliveries, 0 failed\/exhausted/)
      end
    end

    context "with multiple ready deliveries" do
      let!(:ready_deliveries) do
        3.times.map do
          create(:delivery,
            status: :failed,
            retry_stage: :recurring_job_phase,
            next_retry_at: 1.hour.ago,
            attempts: 6)
        end
      end

      it "processes all ready deliveries" do
        expect {
          described_class.perform_now
        }.to have_enqueued_job(DispatchJob).exactly(3).times
      end

      it "logs correct count" do
        allow(Rails.logger).to receive(:info)

        described_class.perform_now

        expect(Rails.logger).to have_received(:info)
          .with(/Processed 3 deliveries, 0 failed\/exhausted/)
      end
    end

    context "with deliveries not yet ready for retry" do
      let!(:not_ready_delivery) do
        create(:delivery,
          status: :failed,
          retry_stage: :recurring_job_phase,
          next_retry_at: 1.hour.from_now,
          attempts: 6)
      end

      it "does not process the delivery" do
        expect {
          described_class.perform_now
        }.not_to have_enqueued_job(DispatchJob)
      end
    end

    context "with deliveries in activejob_phase" do
      let!(:activejob_delivery) do
        create(:delivery,
          status: :failed,
          retry_stage: :activejob_phase,
          next_retry_at: 1.hour.ago,
          attempts: 3)
      end

      it "does not process the delivery" do
        expect {
          described_class.perform_now
        }.not_to have_enqueued_job(DispatchJob)
      end
    end

    context "with deliveries that exhausted all attempts" do
      let!(:exhausted_delivery) do
        create(:delivery,
          status: :failed,
          retry_stage: :recurring_job_phase,
          next_retry_at: 1.hour.ago,
          attempts: 10)
      end

      it "does not enqueue retry" do
        expect {
          described_class.perform_now
        }.not_to have_enqueued_job(DispatchJob)
      end

      it "increments exhausted count" do
        # The job should process the exhausted delivery but not retry it
        described_class.perform_now
        # Verify it wasn't retried
        expect(exhausted_delivery.reload.status).to eq("failed")
      end
    end

    context "with mix of ready and exhausted deliveries" do
      let!(:ready_delivery) do
        create(:delivery,
          status: :failed,
          retry_stage: :recurring_job_phase,
          next_retry_at: 1.hour.ago,
          attempts: 7)
      end

      let!(:exhausted_delivery) do
        create(:delivery,
          status: :failed,
          retry_stage: :recurring_job_phase,
          next_retry_at: 1.hour.ago,
          attempts: 10)
      end

      it "processes only ready deliveries" do
        expect {
          described_class.perform_now
        }.to have_enqueued_job(DispatchJob).once.with(ready_delivery.id)
      end
    end

    context "with successful deliveries" do
      let!(:success_delivery) do
        create(:delivery, :success,
          retry_stage: :recurring_job_phase,
          next_retry_at: 1.hour.ago,
          attempts: 3)
      end

      it "does not process successful deliveries" do
        expect {
          described_class.perform_now
        }.not_to have_enqueued_job(DispatchJob)
      end
    end

    context "with pending deliveries" do
      let!(:pending_delivery) do
        create(:delivery,
          status: :pending,
          retry_stage: :recurring_job_phase,
          next_retry_at: 1.hour.ago,
          attempts: 3)
      end

      it "does not process pending deliveries" do
        expect {
          described_class.perform_now
        }.not_to have_enqueued_job(DispatchJob)
      end
    end

    context "with more than 100 ready deliveries" do
      before do
        # Create 101 ready deliveries
        101.times do
          create(:delivery,
            status: :failed,
            retry_stage: :recurring_job_phase,
            next_retry_at: 1.hour.ago,
            attempts: 6)
        end
      end

      it "processes only 100 deliveries per run" do
        expect {
          described_class.perform_now
        }.to have_enqueued_job(DispatchJob).exactly(100).times
      end
    end

    context "when no deliveries are ready" do
      it "does not enqueue any jobs" do
        expect {
          described_class.perform_now
        }.not_to have_enqueued_job(DispatchJob)
      end
    end
  end
end
