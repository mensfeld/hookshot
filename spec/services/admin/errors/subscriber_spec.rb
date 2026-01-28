# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Errors::Subscriber do
  let(:subscriber) { described_class.new }
  let(:error) { StandardError.new("Test error") }
  let(:context) { {} }

  describe "#report" do
    it "queues error capture job for errors" do
      expect {
        subscriber.report(error, handled: false, severity: :error, context: context.merge(force_capture: true), source: "test")
      }.to have_enqueued_job(Admin::ErrorCaptureJob)
    end

    it "does not queue job for warnings" do
      expect {
        subscriber.report(error, handled: true, severity: :warning, context: context, source: "test")
      }.not_to have_enqueued_job(Admin::ErrorCaptureJob)
    end

    it "does not queue job for info" do
      expect {
        subscriber.report(error, handled: true, severity: :info, context: context, source: "test")
      }.not_to have_enqueued_job(Admin::ErrorCaptureJob)
    end

    context "with DispatchJob errors" do
      let(:dispatch_job) { DispatchJob.new }
      let(:context) { { job: dispatch_job } }

      it "does not queue error capture" do
        expect {
          subscriber.report(error, handled: false, severity: :error, context: context, source: "job")
        }.not_to have_enqueued_job(Admin::ErrorCaptureJob)
      end
    end

    context "with non-DispatchJob errors" do
      it "queues error capture" do
        # Use a context that doesn't have a DispatchJob
        ctx = { some_key: "value", force_capture: true }
        expect {
          subscriber.report(error, handled: false, severity: :error, context: ctx, source: "job")
        }.to have_enqueued_job(Admin::ErrorCaptureJob)
      end
    end

    context "in test environment" do
      before do
        allow(Rails.env).to receive(:test?).and_return(true)
      end

      it "does not capture by default" do
        expect {
          subscriber.report(error, handled: false, severity: :error, context: context, source: "test")
        }.not_to have_enqueued_job(Admin::ErrorCaptureJob)
      end

      it "captures when force_capture is true" do
        context[:force_capture] = true
        expect {
          subscriber.report(error, handled: false, severity: :error, context: context, source: "test")
        }.to have_enqueued_job(Admin::ErrorCaptureJob)
      end
    end

    context "when job queuing fails" do
      before do
        allow(Admin::ErrorCaptureJob).to receive(:perform_later).and_raise(StandardError.new("Queue error"))
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(match(/ErrorSubscriber.*Failed to queue/))
        subscriber.report(error, handled: false, severity: :error, context: context.merge(force_capture: true), source: "test")
      end

      it "returns nil" do
        result = subscriber.report(error, handled: false, severity: :error, context: context.merge(force_capture: true), source: "test")
        expect(result).to be_nil
      end

      it "does not raise exception" do
        expect {
          subscriber.report(error, handled: false, severity: :error, context: context.merge(force_capture: true), source: "test")
        }.not_to raise_error
      end
    end

    describe "context building" do
      it "includes source in context" do
        expect(Admin::ErrorCaptureJob).to receive(:perform_later).with(
          "StandardError",
          "Test error",
          [],
          hash_including(source: "custom_source")
        )

        subscriber.report(error, handled: false, severity: :error, context: { force_capture: true }, source: "custom_source")
      end

      it "passes additional context through" do
        expect(Admin::ErrorCaptureJob).to receive(:perform_later).with(
          "StandardError",
          "Test error",
          [],
          hash_including(additional: hash_including(custom_key: "custom_value"))
        )

        subscriber.report(error, handled: false, severity: :error, context: { custom_key: "custom_value", force_capture: true }, source: "test")
      end
    end
  end
end
