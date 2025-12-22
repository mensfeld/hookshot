# frozen_string_literal: true

require "rails_helper"

RSpec.describe Filter do
  describe "validations" do
    it { is_expected.to validate_presence_of(:filter_type) }
    it { is_expected.to validate_presence_of(:field) }
    it { is_expected.to validate_presence_of(:operator) }

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
end
