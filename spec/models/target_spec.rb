# frozen_string_literal: true

require "rails_helper"

RSpec.describe Target do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:url) }
    it { is_expected.to validate_numericality_of(:timeout).is_greater_than(0).is_less_than_or_equal_to(300) }

    describe "url format" do
      it "accepts valid HTTP URLs" do
        target = build(:target, url: "http://example.com/webhook")
        expect(target).to be_valid
      end

      it "accepts valid HTTPS URLs" do
        target = build(:target, url: "https://example.com/webhook")
        expect(target).to be_valid
      end

      it "rejects invalid URLs" do
        target = build(:target, url: "not-a-url")
        expect(target).not_to be_valid
        expect(target.errors[:url]).to be_present
      end
    end
  end

  describe "associations" do
    it { is_expected.to have_many(:filters).dependent(:destroy) }
    it { is_expected.to have_many(:deliveries).dependent(:nullify) }
  end

  describe "scopes" do
    describe ".active" do
      let!(:active_target) { create(:target, active: true) }
      let!(:inactive_target) { create(:target, :inactive) }

      it "returns only active targets" do
        expect(described_class.active).to include(active_target)
        expect(described_class.active).not_to include(inactive_target)
      end
    end
  end

  describe "#success_rate_24h" do
    let(:target) { create(:target) }
    let(:webhook) { create(:webhook) }

    context "with no recent deliveries" do
      it "returns 0" do
        expect(target.success_rate_24h).to eq(0)
      end
    end

    context "with recent deliveries" do
      before do
        create(:delivery, :success, target: target, webhook: webhook, created_at: 1.hour.ago)
        create(:delivery, :success, target: target, webhook: webhook, created_at: 2.hours.ago)
        create(:delivery, :failed, target: target, webhook: webhook, created_at: 3.hours.ago)
      end

      it "calculates the success rate" do
        expect(target.success_rate_24h).to eq(66.7)
      end
    end
  end

  describe "#filter_count" do
    let(:target) { create(:target) }

    before do
      create_list(:filter, 3, target: target)
    end

    it "returns the count of filters" do
      expect(target.filter_count).to eq(3)
    end
  end

  describe "#filter_groups" do
    let(:target) { create(:target) }

    it "returns an empty hash when there are no filters" do
      expect(target.filter_groups).to eq({})
    end

    it "groups filters by group key, sorted by key, preserving order within a group" do
      first_ci = create(:filter, target: target, group_key: "ci-fail")
      review = create(:filter, target: target, group_key: "approved")
      second_ci = create(:filter, target: target, group_key: "ci-fail")

      expect(target.reload.filter_groups).to eq("approved" => [ review ], "ci-fail" => [ first_ci, second_ci ])
    end

    it "excludes filters marked for destruction" do
      kept = create(:filter, target: target, group_key: "a")
      removed = create(:filter, target: target, group_key: "b")
      target.reload
      target.filters.find { |filter| filter.id == removed.id }.mark_for_destruction

      expect(target.filter_groups).to eq("a" => [ kept ])
    end
  end

  describe "nested filter attributes" do
    let(:target) { create(:target) }

    it "rejects new rows without a field even when a group key is present" do
      target.update!(filters_attributes: [ { group_key: "default", filter_type: "header", operator: "exists", field: "" } ])

      expect(target.filters.count).to eq(0)
    end

    it "does not silently ignore an existing filter whose field was blanked" do
      filter = create(:filter, target: target)

      result = target.update(filters_attributes: [ { id: filter.id, field: "" } ])

      expect(result).to be false
      expect(filter.reload.field).to eq("X-Api-Key")
    end

    it "destroys an existing filter marked for destruction even with a blank field" do
      filter = create(:filter, target: target)

      target.update!(filters_attributes: [ { id: filter.id, field: "", _destroy: "1" } ])

      expect(described_class.find(target.id).filters).to be_empty
    end
  end
end
