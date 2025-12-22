# frozen_string_literal: true

require "rails_helper"

RSpec.describe FilterEvaluator do
  let(:target) { create(:target) }

  describe "#passes?" do
    context "with no filters" do
      let(:webhook) { create(:webhook) }

      it "returns true" do
        evaluator = described_class.new(webhook, target)
        expect(evaluator.passes?).to be true
      end
    end

    context "with header filters" do
      let(:webhook) { create(:webhook, headers: { "HTTP_X_API_KEY" => "secret123" }) }

      context "exists operator" do
        before { create(:filter, :header_exists, target: target, field: "X-Api-Key") }

        it "passes when header exists" do
          evaluator = described_class.new(webhook, target)
          expect(evaluator.passes?).to be true
        end

        it "fails when header does not exist" do
          webhook.update!(headers: {})
          evaluator = described_class.new(webhook, target)
          expect(evaluator.passes?).to be false
        end
      end

      context "equals operator" do
        before { create(:filter, :header_equals, target: target, field: "X-Api-Key", value: "secret123") }

        it "passes when header value matches" do
          evaluator = described_class.new(webhook, target)
          expect(evaluator.passes?).to be true
        end

        it "fails when header value does not match" do
          webhook.update!(headers: { "HTTP_X_API_KEY" => "wrong" })
          evaluator = described_class.new(webhook, target)
          expect(evaluator.passes?).to be false
        end
      end

      context "matches operator" do
        before { create(:filter, :header_matches, target: target, field: "Authorization", value: "Bearer *") }

        it "passes when header value matches pattern" do
          webhook.update!(headers: { "HTTP_AUTHORIZATION" => "Bearer token123" })
          evaluator = described_class.new(webhook, target)
          expect(evaluator.passes?).to be true
        end

        it "fails when header value does not match pattern" do
          webhook.update!(headers: { "HTTP_AUTHORIZATION" => "Basic auth" })
          evaluator = described_class.new(webhook, target)
          expect(evaluator.passes?).to be false
        end
      end
    end

    context "with payload filters" do
      let(:webhook) { create(:webhook, payload: { event: "order.created", data: { email: "test@example.com" } }.to_json) }

      context "exists operator" do
        before { create(:filter, :payload_exists, target: target, field: "$.event") }

        it "passes when field exists" do
          evaluator = described_class.new(webhook, target)
          expect(evaluator.passes?).to be true
        end

        it "fails when field does not exist" do
          webhook.update!(payload: { other: "data" }.to_json)
          evaluator = described_class.new(webhook, target)
          expect(evaluator.passes?).to be false
        end
      end

      context "equals operator" do
        before { create(:filter, :payload_equals, target: target, field: "$.event", value: "order.created") }

        it "passes when field value matches" do
          evaluator = described_class.new(webhook, target)
          expect(evaluator.passes?).to be true
        end

        it "fails when field value does not match" do
          webhook.update!(payload: { event: "order.cancelled" }.to_json)
          evaluator = described_class.new(webhook, target)
          expect(evaluator.passes?).to be false
        end
      end

      context "matches operator" do
        before { create(:filter, :payload_matches, target: target, field: "$.data.email", value: "*@example.com") }

        it "passes when field value matches pattern" do
          evaluator = described_class.new(webhook, target)
          expect(evaluator.passes?).to be true
        end

        it "fails when field value does not match pattern" do
          webhook.update!(payload: { data: { email: "test@other.com" } }.to_json)
          evaluator = described_class.new(webhook, target)
          expect(evaluator.passes?).to be false
        end
      end
    end

    context "with multiple filters (AND logic)" do
      let(:webhook) do
        create(:webhook,
          headers: { "HTTP_X_API_KEY" => "secret" },
          payload: { event: "order.created" }.to_json)
      end

      before do
        create(:filter, :header_exists, target: target, field: "X-Api-Key")
        create(:filter, :payload_equals, target: target, field: "$.event", value: "order.created")
      end

      it "passes when all filters pass" do
        evaluator = described_class.new(webhook, target)
        expect(evaluator.passes?).to be true
      end

      it "fails when any filter fails" do
        webhook.update!(headers: {})
        evaluator = described_class.new(webhook, target)
        expect(evaluator.passes?).to be false
      end
    end

    context "with invalid JSON payload" do
      let(:webhook) { create(:webhook, payload: "not json") }

      before { create(:filter, :payload_exists, target: target, field: "$.event") }

      it "fails gracefully" do
        evaluator = described_class.new(webhook, target)
        expect(evaluator.passes?).to be false
      end
    end

    context "with empty payload" do
      let(:webhook) { create(:webhook, payload: nil) }

      before { create(:filter, :payload_exists, target: target, field: "$.event") }

      it "fails when payload is empty" do
        evaluator = described_class.new(webhook, target)
        expect(evaluator.passes?).to be false
      end
    end

    context "with invalid regex pattern" do
      let(:webhook) { create(:webhook, headers: { "HTTP_X_API_KEY" => "value" }) }
      let(:filter) { create(:filter, :header_matches, target: target, field: "X-Api-Key", value: "valid") }

      before do
        # Bypass validation to set invalid pattern
        filter.update_column(:value, "[invalid")
      end

      it "fails gracefully with invalid regex" do
        evaluator = described_class.new(webhook, target)
        expect(evaluator.passes?).to be false
      end
    end

    context "with nested array in payload" do
      let(:webhook) { create(:webhook, payload: { items: [ { id: 1 }, { id: 2 } ] }.to_json) }

      before { create(:filter, :payload_exists, target: target, field: "$.items.id") }

      it "fails when path leads to array instead of hash" do
        evaluator = described_class.new(webhook, target)
        expect(evaluator.passes?).to be false
      end
    end
  end
end
