# frozen_string_literal: true

require "rails_helper"

RSpec.describe TargetsHelper do
  describe "#filter_logic_summary" do
    let(:target) { create(:target) }

    it "describes a target without filters" do
      expect(helper.filter_logic_summary(target)).to eq("Delivers every webhook (no filters)")
    end

    it "joins a single group with AND and no group labels" do
      create(:filter, :header_exists, target: target)
      create(:filter, :payload_equals, target: target)

      expect(helper.filter_logic_summary(target.reload)).to eq(
        "Delivers if Header 'X-Api-Key' must exist AND Payload '$.event' equals 'order.created'"
      )
    end

    it "joins multiple groups with OR and labels each group" do
      create(:filter, :header_exists, target: target, group_key: "b")
      create(:filter, :payload_equals, target: target, group_key: "a")

      expect(helper.filter_logic_summary(target.reload)).to eq(
        "Delivers if [a] (Payload '$.event' equals 'order.created') OR [b] (Header 'X-Api-Key' must exist)"
      )
    end
  end
end
