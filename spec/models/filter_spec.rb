# frozen_string_literal: true

require "rails_helper"

RSpec.describe Filter do
  describe "validations" do
    it { is_expected.to validate_presence_of(:filter_type) }
    it { is_expected.to validate_presence_of(:field) }
    it { is_expected.to validate_presence_of(:operator) }
    it { is_expected.to validate_length_of(:group_key).is_at_most(Filter::GROUP_KEY_MAX_LENGTH) }

    describe "value presence" do
      context "with exists operator" do
        let(:filter) { build(:filter, operator: :exists, value: nil) }

        it "does not require value" do
          expect(filter).to be_valid
        end
      end

      context "with equals operator" do
        let(:filter) { build(:filter, operator: :equals, value: nil) }

        it "requires value" do
          expect(filter).not_to be_valid
          expect(filter.errors[:value]).to be_present
        end
      end

      context "with matches operator" do
        let(:filter) { build(:filter, operator: :matches, value: nil) }

        it "requires value" do
          expect(filter).not_to be_valid
          expect(filter.errors[:value]).to be_present
        end
      end
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:target) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:filter_type).with_values(header: 0, payload: 1) }
    it { is_expected.to define_enum_for(:operator).with_values(exists: 0, equals: 1, matches: 2) }
  end

  describe "#description" do
    context "with exists operator" do
      let(:filter) { build(:filter, :header_exists, field: "X-Api-Key") }

      it "returns a readable description" do
        expect(filter.description).to eq("Header 'X-Api-Key' must exist")
      end
    end

    context "with equals operator" do
      let(:filter) { build(:filter, :header_equals, field: "X-Api-Key", value: "secret") }

      it "returns a readable description" do
        expect(filter.description).to eq("Header 'X-Api-Key' equals 'secret'")
      end
    end

    context "with matches operator" do
      let(:filter) { build(:filter, :payload_matches, field: "$.email", value: "*@example.com") }

      it "returns a readable description" do
        expect(filter.description).to eq("Payload '$.email' matches '*@example.com'")
      end
    end
  end

  describe "#group_key" do
    it "defaults to the default group" do
      expect(described_class.new.group_key).to eq("default")
    end

    it "defaults to the default group when persisted without one" do
      target = create(:target)
      filter = described_class.create!(target: target, filter_type: :header, field: "X-Api-Key", operator: :exists)

      expect(filter.reload.group_key).to eq("default")
    end

    it "normalizes a blank value to the default group" do
      expect(build(:filter, group_key: "   ").group_key).to eq("default")
    end

    it "normalizes nil to the default group" do
      expect(build(:filter, group_key: nil).group_key).to eq("default")
    end

    it "strips surrounding whitespace" do
      expect(build(:filter, group_key: "  ci-fail \t").group_key).to eq("ci-fail")
    end

    it "preserves case" do
      expect(build(:filter, group_key: "CI-Fail").group_key).to eq("CI-Fail")
    end

    it "persists the normalized value" do
      filter = create(:filter, group_key: " ci-fail ")

      expect(filter.reload.group_key).to eq("ci-fail")
    end
  end

  describe "#default_group?" do
    it "is true for the default group" do
      expect(build(:filter)).to be_default_group
    end

    it "is false for a named group" do
      expect(build(:filter, group_key: "ci-fail")).not_to be_default_group
    end
  end
end
