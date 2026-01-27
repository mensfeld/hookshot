# frozen_string_literal: true

require "rails_helper"

RSpec.describe DispatchJob do
  let(:webhook) { create(:webhook, payload: '{"test": true}') }
  let(:target) { create(:target, url: "https://api.example.com/webhook") }
  let(:delivery) { create(:delivery, webhook: webhook, target: target, status: :pending) }

  describe "job configuration" do
    it "has correct queue configuration" do
      expect(described_class.new.queue_name).to eq("default")
    end

    it "can enqueue a job successfully" do
      expect {
        described_class.perform_later(delivery.id)
      }.to have_enqueued_job(described_class).with(delivery.id)
    end

    it "has concurrency limit with working key lambda" do
      # The key lambda receives the job instance as an argument
      # This test ensures the lambda accepts the argument without raising ArgumentError
      job = described_class.new
      concurrency_key = described_class.concurrency_key(job)
      expect(concurrency_key).to eq("dispatch")
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
end
