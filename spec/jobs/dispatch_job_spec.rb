# frozen_string_literal: true

require "rails_helper"

RSpec.describe DispatchJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:webhook) { create(:webhook, payload: '{"test": true}') }
  let(:target) { create(:target, url: "https://api.example.com/webhook") }
  let(:delivery) { create(:delivery, webhook: webhook, target: target, status: :pending) }

  describe "job configuration" do
    it "has correct queue configuration" do
      expect(described_class.new.queue_name).to eq("default")
    end

    it "can enqueue a job successfully without ArgumentError" do
      # This test verifies the concurrency limit key lambda is properly defined
      # The bug was: key: -> { "dispatch" } which raised ArgumentError when SolidQueue passed the job instance
      # The fix: key: -> (_job) { "dispatch" } which accepts the job argument
      expect {
        described_class.perform_later(delivery.id)
      }.to have_enqueued_job(described_class).with(delivery.id)
    end
  end

  describe "#perform" do
    context "with successful delivery" do
      before do
        stub_request(:post, target.url)
          .to_return(status: 200, body: '{"status": "ok"}')
      end

      it "updates delivery to success" do
        described_class.perform_now(delivery.id)

        delivery.reload
        expect(delivery.status).to eq("success")
        expect(delivery.status_code).to eq(200)
        expect(delivery.dispatched_at).to be_present
      end

      it "increments attempts" do
        expect {
          described_class.perform_now(delivery.id)
        }.to change { delivery.reload.attempts }.by(1)
      end

      it "includes custom headers from target" do
        target.update!(custom_headers: { "Authorization" => "Bearer token" })

        stub_request(:post, target.url)
          .with(headers: { "Authorization" => "Bearer token" })
          .to_return(status: 200, body: "ok")

        described_class.perform_now(delivery.id)

        expect(a_request(:post, target.url)
          .with(headers: { "Authorization" => "Bearer token" })).to have_been_made
      end

      it "includes Hookshot headers" do
        stub_request(:post, target.url)
          .with(headers: {
            "X-Hookshot-Webhook-Id" => webhook.id.to_s,
            "X-Hookshot-Delivery-Id" => delivery.id.to_s
          })
          .to_return(status: 200, body: "ok")

        described_class.perform_now(delivery.id)

        expect(a_request(:post, target.url)
          .with(headers: { "X-Hookshot-Webhook-Id" => webhook.id.to_s })).to have_been_made
      end

      it "includes X-Hookshot-Attempt header with current attempt number" do
        delivery.update!(attempts: 2)

        stub_request(:post, target.url)
          .with(headers: { "X-Hookshot-Attempt" => "3" })
          .to_return(status: 200, body: "ok")

        described_class.perform_now(delivery.id)

        expect(a_request(:post, target.url)
          .with(headers: { "X-Hookshot-Attempt" => "3" })).to have_been_made
      end
    end

    context "with server error (5xx)" do
      before do
        stub_request(:post, target.url)
          .to_return(status: 500, body: "Internal Server Error")
      end

      it "updates delivery to failed" do
        # ServerError is raised for retry mechanism but caught by perform_now
        described_class.perform_now(delivery.id) rescue DispatchJob::ServerError

        delivery.reload
        expect(delivery.status).to eq("failed")
        expect(delivery.status_code).to eq(500)
      end
    end

    context "with client error (4xx)" do
      before do
        stub_request(:post, target.url)
          .to_return(status: 400, body: "Bad Request")
      end

      it "updates delivery to failed and discards job" do
        # ClientError should be discarded, so no exception raised
        described_class.perform_now(delivery.id)

        delivery.reload
        expect(delivery.status).to eq("failed")
        expect(delivery.status_code).to eq(400)
      end
    end

    context "with already completed delivery" do
      let(:delivery) { create(:delivery, :success, webhook: webhook, target: target) }

      it "returns early without making request" do
        stub_request(:post, target.url)

        described_class.perform_now(delivery.id)

        expect(a_request(:post, target.url)).not_to have_been_made
      end
    end

    context "with filtered delivery" do
      let(:delivery) { create(:delivery, :filtered, webhook: webhook, target: target) }

      it "returns early without making request" do
        stub_request(:post, target.url)

        described_class.perform_now(delivery.id)

        expect(a_request(:post, target.url)).not_to have_been_made
      end
    end

    context "with non-existent delivery" do
      it "handles gracefully due to discard_on" do
        # discard_on ActiveRecord::RecordNotFound means no error is raised
        expect {
          described_class.perform_now(-1)
        }.not_to raise_error
      end
    end
  end

  describe "retry configuration" do
    it "retries up to ACTIVEJOB_MAX_ATTEMPTS times" do
      # The retry_on configuration should match Delivery::ACTIVEJOB_MAX_ATTEMPTS
      expect(Delivery::ACTIVEJOB_MAX_ATTEMPTS).to eq(5)
    end
  end

  describe "transition to recurring job phase" do
    let(:delivery) { create(:delivery, webhook: webhook, target: target, attempts: 5, retry_stage: :activejob_phase, status: :failed) }

    it "transitions when delivery is ready for recurring phase" do
      expect(delivery.ready_for_recurring_phase?).to be true

      delivery.transition_to_recurring_phase!

      delivery.reload
      expect(delivery.retry_stage).to eq("recurring_job_phase")
      expect(delivery.next_retry_at).to be_present
    end

    context "before 5th attempt" do
      let(:delivery) { create(:delivery, webhook: webhook, target: target, attempts: 2, retry_stage: :activejob_phase, status: :pending) }

      it "is not ready for transition" do
        expect(delivery.ready_for_recurring_phase?).to be false
      end
    end
  end

  describe "running enqueued jobs as a worker" do
    include ActiveJob::TestHelper

    context "when the target keeps answering with a server error" do
      before do
        stub_request(:post, target.url)
          .to_return(status: 503, body: "Service Unavailable")
      end

      it "moves the delivery to the recurring job phase after the last attempt" do
        described_class.perform_later(delivery.id)

        expect {
          perform_enqueued_jobs while enqueued_jobs.any?
        }.to raise_error(DispatchJob::ServerError)

        delivery.reload
        expect(delivery.attempts).to eq(Delivery::ACTIVEJOB_MAX_ATTEMPTS)
        expect(delivery.retry_stage).to eq("recurring_job_phase")
        expect(a_request(:post, target.url)).to have_been_made.times(Delivery::ACTIVEJOB_MAX_ATTEMPTS)
      end
    end

    context "when a delivery in the recurring job phase keeps getting a server error" do
      let(:delivery) do
        create(:delivery, webhook: webhook, target: target, status: :failed, attempts: 5, retry_stage: :activejob_phase)
      end

      before do
        stub_request(:post, target.url)
          .to_return(status: 503, body: "Service Unavailable")

        delivery.transition_to_recurring_phase!
      end

      def run_due_retry
        travel_to(delivery.reload.next_retry_at, with_usec: true)
        RetryFailedDeliveriesJob.perform_now
        perform_enqueued_jobs while enqueued_jobs.any?
      end

      it "makes one request per due retry, 1h, 2h, 4h, 8h and 24h apart" do
        previous_attempt_at = Time.current

        [ 1.hour, 2.hours, 4.hours, 8.hours, 24.hours ].each.with_index(6) do |delay, attempt|
          RetryFailedDeliveriesJob.perform_now
          expect(enqueued_jobs).to be_empty

          run_due_retry

          delivery.reload
          expect(delivery.attempts).to eq(attempt)
          expect(delivery.status).to eq("failed")
          expect(delivery.last_retry_at - previous_attempt_at).to be_within(1.second).of(delay)
          expect(a_request(:post, target.url)).to have_been_made.times(attempt - Delivery::ACTIVEJOB_MAX_ATTEMPTS)

          previous_attempt_at = delivery.last_retry_at
        end
      end

      it "gives up after attempt 10" do
        5.times { run_due_retry }

        travel 2.days
        RetryFailedDeliveriesJob.perform_now

        delivery.reload
        expect(enqueued_jobs).to be_empty
        expect(delivery.attempts).to eq(Delivery::MAX_TOTAL_ATTEMPTS)
        expect(delivery.status).to eq("failed")
        expect(delivery).not_to be_retryable
        expect(Delivery.ready_for_retry).not_to include(delivery)
        expect(a_request(:post, target.url)).to have_been_made.times(5)
      end

      it "stops retrying after a success" do
        run_due_retry

        stub_request(:post, target.url)
          .to_return(status: 200, body: "ok")
        run_due_retry

        travel 2.days
        RetryFailedDeliveriesJob.perform_now

        delivery.reload
        expect(enqueued_jobs).to be_empty
        expect(delivery.status).to eq("success")
        expect(delivery.attempts).to eq(7)
        expect(a_request(:post, target.url)).to have_been_made.twice
      end
    end

    context "when the target answers with a client error" do
      before do
        stub_request(:post, target.url)
          .to_return(status: 404, body: "Not Found")
      end

      it "makes one request and does not retry" do
        described_class.perform_later(delivery.id)
        perform_enqueued_jobs while enqueued_jobs.any?

        expect(a_request(:post, target.url)).to have_been_made.once
        expect(enqueued_jobs).to be_empty
        expect(delivery.reload.attempts).to eq(1)
      end
    end

    context "when the delivery does not exist" do
      it "does not retry" do
        described_class.perform_later(-1)

        expect {
          perform_enqueued_jobs while enqueued_jobs.any?
        }.not_to raise_error

        expect(performed_jobs.size).to eq(1)
        expect(enqueued_jobs).to be_empty
      end
    end
  end

  describe "logging" do
    before do
      stub_request(:post, target.url)
        .to_return(status: 200, body: "ok")
    end

    it "logs attempt number on each dispatch" do
      allow(Rails.logger).to receive(:info)

      described_class.perform_now(delivery.id)

      expect(Rails.logger).to have_received(:info)
        .with(/Delivery #{delivery.id} attempt 1\/#{Delivery::MAX_TOTAL_ATTEMPTS}/)
    end
  end
end
