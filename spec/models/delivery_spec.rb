# frozen_string_literal: true

require "rails_helper"

RSpec.describe Delivery do
  describe "associations" do
    it { is_expected.to belong_to(:webhook) }
    it { is_expected.to belong_to(:target) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, success: 1, failed: 2, filtered: 3) }
    it do
      expect(subject).to define_enum_for(:retry_stage)
        .with_values(activejob_phase: 0, recurring_job_phase: 1)
    end
  end

  describe "scopes" do
    describe ".recent_24h" do
      let!(:recent_delivery) { create(:delivery, created_at: 1.hour.ago) }
      let!(:old_delivery) { create(:delivery, created_at: 2.days.ago) }

      it "returns only deliveries from the last 24 hours" do
        expect(described_class.recent_24h).to include(recent_delivery)
        expect(described_class.recent_24h).not_to include(old_delivery)
      end
    end

    describe ".ready_for_retry" do
      let!(:ready_delivery) do
        create(:delivery,
          status: :failed,
          retry_stage: :recurring_job_phase,
          next_retry_at: 1.hour.ago,
          attempts: 6)
      end

      let!(:not_ready_yet) do
        create(:delivery,
          status: :failed,
          retry_stage: :recurring_job_phase,
          next_retry_at: 1.hour.from_now,
          attempts: 6)
      end

      let!(:activejob_phase_delivery) do
        create(:delivery,
          status: :failed,
          retry_stage: :activejob_phase,
          next_retry_at: 1.hour.ago,
          attempts: 3)
      end

      let!(:exhausted_delivery) do
        create(:delivery,
          status: :failed,
          retry_stage: :recurring_job_phase,
          next_retry_at: 1.hour.ago,
          attempts: 10)
      end

      it "returns only failed deliveries in recurring_job_phase ready for retry" do
        results = described_class.ready_for_retry
        expect(results).to include(ready_delivery)
        expect(results).not_to include(not_ready_yet)
        expect(results).not_to include(activejob_phase_delivery)
        expect(results).not_to include(exhausted_delivery)
      end
    end
  end

  describe "#increment_attempts!" do
    let(:delivery) { create(:delivery, attempts: 0) }

    it "increments the attempts counter" do
      expect { delivery.increment_attempts! }.to change { delivery.reload.attempts }.from(0).to(1)
    end

    it "sets last_retry_at to current time" do
      before_time = Time.current
      delivery.increment_attempts!
      expect(delivery.reload.last_retry_at).to be >= before_time
      expect(delivery.reload.last_retry_at).to be_within(1.second).of(Time.current)
    end

    it "calculates and sets next_retry_at based on retry schedule" do
      before_time = Time.current
      delivery.increment_attempts!
      expected_time = before_time + described_class::RETRY_SCHEDULE[1]
      expect(delivery.reload.next_retry_at).to be_within(2.seconds).of(expected_time)
    end
  end

  describe "#retryable?" do
    context "when failed with fewer than 10 attempts" do
      let(:delivery) { build(:delivery, :retryable) }

      it "returns true" do
        expect(delivery.retryable?).to be true
      end
    end

    context "when failed with 10 or more attempts" do
      let(:delivery) { build(:delivery, status: :failed, attempts: 10) }

      it "returns false" do
        expect(delivery.retryable?).to be false
      end
    end

    context "when successful" do
      let(:delivery) { build(:delivery, :success) }

      it "returns false" do
        expect(delivery.retryable?).to be false
      end
    end

    context "when pending" do
      let(:delivery) { build(:delivery, status: :pending, attempts: 0) }

      it "returns false" do
        expect(delivery.retryable?).to be false
      end
    end
  end

  describe "#calculate_next_retry!" do
    let(:delivery) { build(:delivery, attempts: 2) }

    it "sets next_retry_at based on retry schedule" do
      before_time = Time.current
      delivery.calculate_next_retry!
      expected_time = before_time + described_class::RETRY_SCHEDULE[2]
      expect(delivery.next_retry_at).to be_within(2.seconds).of(expected_time)
    end

    context "when attempts exceed max" do
      let(:delivery) { build(:delivery, attempts: 10) }

      it "does not set next_retry_at" do
        delivery.calculate_next_retry!
        expect(delivery.next_retry_at).to be_nil
      end
    end

    context "when attempts exceed schedule length" do
      let(:delivery) { build(:delivery, attempts: 9) }

      it "uses last schedule value" do
        before_time = Time.current
        delivery.calculate_next_retry!
        expected_time = before_time + described_class::RETRY_SCHEDULE.last
        expect(delivery.next_retry_at).to be_within(2.seconds).of(expected_time)
      end
    end
  end

  describe "#ready_for_recurring_phase?" do
    context "when attempts >= 5 and in activejob_phase" do
      let(:delivery) { build(:delivery, attempts: 5, retry_stage: :activejob_phase) }

      it "returns true" do
        expect(delivery.ready_for_recurring_phase?).to be true
      end
    end

    context "when attempts < 5" do
      let(:delivery) { build(:delivery, attempts: 3, retry_stage: :activejob_phase) }

      it "returns false" do
        expect(delivery.ready_for_recurring_phase?).to be false
      end
    end

    context "when already in recurring_job_phase" do
      let(:delivery) { build(:delivery, attempts: 6, retry_stage: :recurring_job_phase) }

      it "returns false" do
        expect(delivery.ready_for_recurring_phase?).to be false
      end
    end
  end

  describe "#transition_to_recurring_phase!" do
    let(:delivery) { create(:delivery, attempts: 5, retry_stage: :activejob_phase, status: :failed) }

    it "changes retry_stage to recurring_job_phase" do
      expect { delivery.transition_to_recurring_phase! }
        .to change { delivery.reload.retry_stage }
        .from("activejob_phase").to("recurring_job_phase")
    end

    it "calculates next_retry_at" do
      before_time = Time.current
      delivery.transition_to_recurring_phase!
      expected_time = before_time + described_class::RETRY_SCHEDULE[5]
      expect(delivery.reload.next_retry_at).to be_within(2.seconds).of(expected_time)
    end

    context "when not ready for transition" do
      let(:delivery) { create(:delivery, attempts: 3, retry_stage: :activejob_phase) }

      it "returns false and does not change retry_stage" do
        expect(delivery.transition_to_recurring_phase!).to be false
        expect(delivery.reload.retry_stage).to eq("activejob_phase")
      end
    end
  end

  describe "#reset_for_retry!" do
    let(:delivery) { create(:delivery, status: :failed) }

    it "resets status to pending" do
      expect { delivery.reset_for_retry! }
        .to change { delivery.reload.status }
        .from("failed").to("pending")
    end
  end

  describe "constants" do
    it "defines RETRY_SCHEDULE with 10 delays" do
      expect(described_class::RETRY_SCHEDULE.length).to eq(10)
    end

    it "defines MAX_TOTAL_ATTEMPTS as 10" do
      expect(described_class::MAX_TOTAL_ATTEMPTS).to eq(10)
    end

    it "defines ACTIVEJOB_MAX_ATTEMPTS as 5" do
      expect(described_class::ACTIVEJOB_MAX_ATTEMPTS).to eq(5)
    end

    it "has retry schedule progressing from 30 seconds to 24 hours" do
      expect(described_class::RETRY_SCHEDULE.first).to eq(30.seconds)
      expect(described_class::RETRY_SCHEDULE.last).to eq(24.hours)
    end
  end
end
