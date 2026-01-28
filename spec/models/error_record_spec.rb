# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorRecord do
  describe "validations" do
    subject { build(:error_record) }

    it { is_expected.to validate_presence_of(:error_class) }
    it { is_expected.to validate_presence_of(:fingerprint) }
    it { is_expected.to validate_uniqueness_of(:fingerprint) }
  end

  describe "scopes" do
    describe ".unresolved" do
      let!(:unresolved_error) { create(:error_record) }
      let!(:resolved_error) { create(:error_record, :resolved) }

      it "returns only unresolved errors" do
        expect(described_class.unresolved).to include(unresolved_error)
        expect(described_class.unresolved).not_to include(resolved_error)
      end
    end

    describe ".resolved" do
      let!(:unresolved_error) { create(:error_record) }
      let!(:resolved_error) { create(:error_record, :resolved) }

      it "returns only resolved errors" do
        expect(described_class.resolved).to include(resolved_error)
        expect(described_class.resolved).not_to include(unresolved_error)
      end
    end

    describe ".recent_first" do
      let!(:old_error) { create(:error_record, last_occurred_at: 2.days.ago) }
      let!(:new_error) { create(:error_record, last_occurred_at: 1.hour.ago) }

      it "orders by last_occurred_at descending" do
        expect(described_class.recent_first.first).to eq(new_error)
        expect(described_class.recent_first.last).to eq(old_error)
      end
    end
  end

  describe "#resolve!" do
    let(:error_record) { create(:error_record) }

    it "sets resolved_at to current time" do
      before_time = Time.current
      error_record.resolve!
      expect(error_record.reload.resolved_at).to be >= before_time
      expect(error_record.reload.resolved_at).to be_within(1.second).of(Time.current)
    end

    it "returns true on success" do
      expect(error_record.resolve!).to be true
    end
  end

  describe "#unresolve!" do
    let(:error_record) { create(:error_record, :resolved) }

    it "sets resolved_at to nil" do
      error_record.unresolve!
      expect(error_record.reload.resolved_at).to be_nil
    end

    it "returns true on success" do
      expect(error_record.unresolve!).to be true
    end
  end

  describe "#backtrace_lines" do
    context "with multi-line backtrace" do
      let(:error_record) do
        create(:error_record, backtrace: (1..30).map { |i| "line #{i}" }.join("\n"))
      end

      it "returns first 20 lines" do
        expect(error_record.backtrace_lines.size).to eq(20)
        expect(error_record.backtrace_lines.first).to eq("line 1")
        expect(error_record.backtrace_lines.last).to eq("line 20")
      end
    end

    context "with nil backtrace" do
      let(:error_record) { create(:error_record, backtrace: nil) }

      it "returns empty array" do
        expect(error_record.backtrace_lines).to eq([])
      end
    end
  end

  describe "#resolved?" do
    context "when resolved_at is present" do
      let(:error_record) { create(:error_record, :resolved) }

      it "returns true" do
        expect(error_record.resolved?).to be true
      end
    end

    context "when resolved_at is nil" do
      let(:error_record) { create(:error_record) }

      it "returns false" do
        expect(error_record.resolved?).to be false
      end
    end
  end
end
