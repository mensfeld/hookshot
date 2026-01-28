# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::ErrorCaptureJob do
  describe "#perform" do
    let(:error_class) { "StandardError" }
    let(:error_message) { "Test error" }
    let(:error_backtrace) { [ "line 1", "line 2" ] }
    let(:context) { { source: "test" } }

    it "calls Admin::Errors::Capture" do
      expect(Admin::Errors::Capture).to receive(:call).with(
        an_instance_of(StandardError),
        context: context
      )

      described_class.perform_now(error_class, error_message, error_backtrace, context)
    end

    it "builds exception with correct class" do
      result = nil
      allow(Admin::Errors::Capture).to receive(:call) do |exception, **_|
        result = exception
      end

      described_class.perform_now(error_class, error_message, error_backtrace, context)

      expect(result).to be_a(StandardError)
      expect(result.message).to eq(error_message)
      expect(result.backtrace).to eq(error_backtrace)
    end

    context "with unknown error class" do
      let(:error_class) { "NonExistentError" }

      it "falls back to StandardError" do
        result = nil
        allow(Admin::Errors::Capture).to receive(:call) do |exception, **_|
          result = exception
        end

        described_class.perform_now(error_class, error_message, error_backtrace, context)

        expect(result).to be_a(StandardError)
      end
    end

    context "when capture fails" do
      before do
        allow(Admin::Errors::Capture).to receive(:call).and_raise(StandardError.new("Capture failed"))
      end

      it "does not retry the job" do
        # The job has discard_on StandardError, so it swallows the exception
        # and doesn't retry. We just verify it doesn't raise to the caller.
        expect {
          described_class.perform_now(error_class, error_message, error_backtrace, context)
        }.not_to raise_error
      end
    end
  end
end
