# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Errors::Capture do
  include ActiveSupport::Testing::TimeHelpers
  describe ".call" do
    let(:exception) { StandardError.new("Test error") }
    let(:context) { { source: "test" } }

    it "creates a new error record" do
      expect {
        described_class.call(exception, context: context)
      }.to change { ErrorRecord.count }.by(1)
    end

    it "sets error_class from exception class" do
      described_class.call(exception, context: context)
      record = ErrorRecord.last
      expect(record.error_class).to eq("StandardError")
    end

    it "sets message from exception message" do
      described_class.call(exception, context: context)
      record = ErrorRecord.last
      expect(record.message).to eq("Test error")
    end

    it "generates a fingerprint" do
      described_class.call(exception, context: context)
      record = ErrorRecord.last
      expect(record.fingerprint).to be_present
      expect(record.fingerprint.length).to eq(64) # SHA256 length
    end

    it "sets occurrences_count to 1 for new error" do
      described_class.call(exception, context: context)
      record = ErrorRecord.last
      expect(record.occurrences_count).to eq(1)
    end

    it "sanitizes context" do
      ctx = { source: "test", password: "secret123" }
      described_class.call(exception, context: ctx)
      record = ErrorRecord.last
      expect(record.context["password"]).to eq("[REDACTED]")
    end

    context "with duplicate error" do
      before do
        described_class.call(exception, context: context)
      end

      it "does not create a new record" do
        expect {
          described_class.call(exception, context: context)
        }.not_to change { ErrorRecord.count }
      end

      it "increments occurrences_count" do
        record = ErrorRecord.last
        expect {
          described_class.call(exception, context: context)
        }.to change { record.reload.occurrences_count }.from(1).to(2)
      end

      it "updates last_occurred_at" do
        record = ErrorRecord.last
        original_time = record.last_occurred_at
        travel 1.hour
        described_class.call(exception, context: context)
        expect(record.reload.last_occurred_at).to be > original_time
      end

      it "does not update first_occurred_at" do
        record = ErrorRecord.last
        original_time = record.first_occurred_at
        travel 1.hour
        described_class.call(exception, context: context)
        expect(record.reload.first_occurred_at).to eq(original_time)
      end
    end

    context "with backtrace" do
      let(:backtrace) do
        [
          "app/controllers/test_controller.rb:10:in `create'",
          "/gems/actionpack/lib/action_controller.rb:100:in `dispatch'",
          "app/services/test_service.rb:20:in `call'"
        ]
      end

      before do
        exception.set_backtrace(backtrace)
      end

      it "removes gem paths from backtrace" do
        described_class.call(exception, context: context)
        record = ErrorRecord.last
        expect(record.backtrace).not_to include("actionpack")
        expect(record.backtrace).to include("test_controller")
        expect(record.backtrace).to include("test_service")
      end
    end

    context "when capture fails" do
      before do
        allow(ErrorRecord).to receive(:transaction).and_raise(StandardError.new("DB error"))
        allow(Rails.logger).to receive(:error)
      end

      it "logs the error" do
        described_class.call(exception, context: context)
        expect(Rails.logger).to have_received(:error).with(match(/ErrorCapture.*Transaction failed/))
      end

      it "returns nil" do
        result = described_class.call(exception, context: context)
        expect(result).to be_nil
      end

      it "does not raise exception" do
        expect {
          described_class.call(exception, context: context)
        }.not_to raise_error
      end
    end
  end

  describe "fingerprint normalization" do
    it "normalizes numbers" do
      error1 = StandardError.new("Error with id 123")
      error2 = StandardError.new("Error with id 456")

      described_class.call(error1)
      fingerprint1 = ErrorRecord.last.fingerprint

      described_class.call(error2)
      expect(ErrorRecord.count).to eq(1) # Same fingerprint
      expect(ErrorRecord.last.fingerprint).to eq(fingerprint1)
    end

    it "normalizes UUIDs" do
      error1 = StandardError.new("Error with uuid 550e8400-e29b-41d4-a716-446655440000")
      error2 = StandardError.new("Error with uuid 6ba7b810-9dad-11d1-80b4-00c04fd430c8")

      # First error creates the record
      described_class.call(error1)
      expect(ErrorRecord.count).to eq(1)
      initial_count = ErrorRecord.last.occurrences_count

      # Second error with different UUID should deduplicate
      described_class.call(error2)
      expect(ErrorRecord.count).to eq(1) # Same record
      expect(ErrorRecord.last.occurrences_count).to eq(initial_count + 1) # Incremented
    end

    it "normalizes hex addresses" do
      error1 = StandardError.new("Object at 0x00007f8b3c8d9f60")
      error2 = StandardError.new("Object at 0x00007f8b3c8d9f70")

      described_class.call(error1)
      fingerprint1 = ErrorRecord.last.fingerprint

      described_class.call(error2)
      expect(ErrorRecord.count).to eq(1) # Same fingerprint
    end

    it "normalizes temp paths" do
      error1 = StandardError.new("File not found: /tmp/foo123")
      error2 = StandardError.new("File not found: /tmp/bar456")

      described_class.call(error1)
      fingerprint1 = ErrorRecord.last.fingerprint

      described_class.call(error2)
      expect(ErrorRecord.count).to eq(1) # Same fingerprint
    end
  end

  describe "context sanitization" do
    it "redacts password fields" do
      context = { password: "secret123" }
      described_class.call(StandardError.new("test"), context: context)
      record = ErrorRecord.last
      expect(record.context["password"]).to eq("[REDACTED]")
    end

    it "redacts token fields" do
      context = { api_token: "abc123" }
      described_class.call(StandardError.new("test"), context: context)
      record = ErrorRecord.last
      expect(record.context["api_token"]).to eq("[REDACTED]")
    end

    it "redacts authorization headers" do
      context = { authorization: "Bearer token123" }
      described_class.call(StandardError.new("test"), context: context)
      record = ErrorRecord.last
      expect(record.context["authorization"]).to eq("[REDACTED]")
    end

    it "truncates long strings" do
      long_string = "x" * 2000
      context = { data: long_string }
      described_class.call(StandardError.new("test"), context: context)
      record = ErrorRecord.last
      expect(record.context["data"].length).to be < long_string.length
      expect(record.context["data"]).to include("[truncated]")
    end

    it "handles nested hashes" do
      context = { user: { password: "secret", name: "John" } }
      described_class.call(StandardError.new("test"), context: context)
      record = ErrorRecord.last
      expect(record.context["user"]["password"]).to eq("[REDACTED]")
      expect(record.context["user"]["name"]).to eq("John")
    end
  end
end
