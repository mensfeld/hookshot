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

    context "with regex operator" do
      let(:evaluator) { described_class.new(webhook, target) }
      let(:webhook) do
        create(:webhook,
          headers: { "HTTP_X_GITHUB_EVENT" => "pull_request_review_comment" },
          payload: { comment: { user: { login: "Copilot", id: 42 } }, labels: [ "bug" ], draft: false }.to_json)
      end

      def regex_filter(filter_type, field, pattern)
        create(:filter, target: target, filter_type: filter_type, field: field, operator: :regex, value: pattern)
      end

      it "matches a header value" do
        regex_filter(:header, "X-GitHub-Event", '\Apull_request(_review)?(_comment)?\z')

        expect(evaluator.passes?).to be true
      end

      it "matches a payload value" do
        regex_filter(:payload, "$.comment.user.login", '\A(mensfeld|Copilot)\z')

        expect(evaluator.passes?).to be true
      end

      it "matches anywhere in the value unless anchored" do
        regex_filter(:header, "X-GitHub-Event", 'review')

        expect(evaluator.passes?).to be true
      end

      it "fails when an anchored pattern only matches part of the value" do
        regex_filter(:header, "X-GitHub-Event", '\Areview\z')

        expect(evaluator.passes?).to be false
      end

      it "is case-sensitive by default" do
        regex_filter(:payload, "$.comment.user.login", 'copilot')

        expect(evaluator.passes?).to be false
      end

      it "supports inline flags for case-insensitive matching" do
        regex_filter(:payload, "$.comment.user.login", '(?i)copilot')

        expect(evaluator.passes?).to be true
      end

      it "matches non-string payload values by their string form" do
        regex_filter(:payload, "$.comment.user.id", '\A\d+\z')

        expect(evaluator.passes?).to be true
      end

      it "matches false booleans by their string form" do
        regex_filter(:payload, "$.draft", '\Afalse\z')

        expect(evaluator.passes?).to be true
      end

      it "never matches a missing payload field, even with a pattern accepting empty strings" do
        regex_filter(:payload, "$.comment.user.type", '.*')

        expect(evaluator.passes?).to be false
      end

      it "never matches a missing header, even with a negative lookahead" do
        regex_filter(:header, "X-Missing", '\A(?!bot)')

        expect(evaluator.passes?).to be false
      end

      it "fails when the payload is not JSON" do
        webhook.update!(payload: "not json")
        regex_filter(:payload, "$.comment.user.login", '.')

        expect(evaluator.passes?).to be false
      end

      it "fails gracefully when a stored pattern is invalid" do
        regex_filter(:header, "X-GitHub-Event", 'valid').update_column(:value, "invalid[")

        expect(evaluator.passes?).to be false
      end

      it "fails and logs a warning when matching times out" do
        filter = regex_filter(:header, "X-GitHub-Event", 'review')
        regex = instance_double(Regexp)
        allow(regex).to receive(:match?).and_raise(Regexp::TimeoutError)
        allow_any_instance_of(Filter).to receive(:compiled_regex).and_return(regex)
        allow(Rails.logger).to receive(:warn)

        expect(evaluator.passes?).to be false
        expect(Rails.logger).to have_received(:warn).with(/Regex filter #{filter.id} timed out on webhook #{webhook.id}/)
      end

      it "stops a catastrophic backtracking pattern at the timeout" do
        webhook.update!(headers: { "HTTP_X_SLOW" => "#{'a' * 50_000}!" })
        regex_filter(:header, "X-Slow", '\A(a|a?)+\z')

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        expect(evaluator.passes?).to be false
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2
      end

      it "combines with other filters in a group" do
        create(:filter, target: target, group_key: "copilot", filter_type: :header, field: "X-GitHub-Event",
          operator: :equals, value: "issue_comment")
        create(:filter, target: target, group_key: "copilot", filter_type: :payload, field: "$.comment.user.login",
          operator: :regex, value: "(?i)copilot")

        expect(evaluator.passes?).to be false
        webhook.update!(headers: { "HTTP_X_GITHUB_EVENT" => "issue_comment" })
        expect(described_class.new(webhook, target).passes?).to be true
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

    context "with filter groups" do
      let(:evaluator) { described_class.new(webhook, target) }

      def github_webhook(event, payload)
        create(:webhook, headers: { "HTTP_X_GITHUB_EVENT" => event }, payload: payload.to_json)
      end

      def add_filter(group_key, filter_type, field, operator, value = nil)
        create(:filter, target: target, group_key: group_key, filter_type: filter_type,
          field: field, operator: operator, value: value)
      end

      before do
        add_filter("ci-fail", :header, "X-GitHub-Event", :equals, "check_suite")
        add_filter("ci-fail", :payload, "$.check_suite.conclusion", :equals, "failure")
        add_filter("changes-requested", :header, "X-GitHub-Event", :equals, "pull_request_review")
        add_filter("changes-requested", :payload, "$.review.state", :equals, "changes_requested")
      end

      context "when one group fully matches and another does not" do
        let(:webhook) { github_webhook("pull_request_review", { review: { state: "changes_requested" } }) }

        it "passes (OR across groups)" do
          expect(evaluator.passes?).to be true
        end
      end

      context "when the first group fully matches" do
        let(:webhook) { github_webhook("check_suite", { check_suite: { conclusion: "failure" } }) }

        it "passes" do
          expect(evaluator.passes?).to be true
        end
      end

      context "when a group only partially matches and no other group matches" do
        let(:webhook) { github_webhook("check_suite", { check_suite: { conclusion: "success" } }) }

        it "does not pass (AND within a group)" do
          expect(evaluator.passes?).to be false
        end
      end

      context "when each group partially matches but none fully" do
        let(:webhook) { github_webhook("check_suite", { review: { state: "changes_requested" } }) }

        it "does not pass (matches are not combined across groups)" do
          expect(evaluator.passes?).to be false
        end
      end

      context "when no group matches at all" do
        let(:webhook) { github_webhook("push", { ref: "refs/heads/master" }) }

        it "does not pass" do
          expect(evaluator.passes?).to be false
        end
      end

      context "with a single-filter group alongside multi-filter groups" do
        let(:webhook) { github_webhook("pull_request", { action: "opened" }) }

        before { add_filter("any-pr", :header, "X-GitHub-Event", :equals, "pull_request") }

        it "passes when the single-filter group matches" do
          expect(evaluator.passes?).to be true
        end
      end

      context "with a default group alongside named groups" do
        let(:webhook) { github_webhook("check_suite", { check_suite: { conclusion: "failure" } }) }

        before { add_filter("default", :header, "X-Hub-Signature-256", :exists) }

        it "treats default as another alternative rather than a condition shared by all groups" do
          expect(evaluator.passes?).to be true
        end

        it "passes on the default group alone when no named group matches" do
          webhook.update!(headers: { "HTTP_X_GITHUB_EVENT" => "push", "HTTP_X_HUB_SIGNATURE_256" => "sha256=abc" })

          expect(evaluator.passes?).to be true
        end
      end

      context "with group keys that differ only by surrounding whitespace" do
        let(:webhook) { github_webhook("check_suite", { check_suite: { conclusion: "success" } }) }

        before do
          target.filters.where(group_key: "ci-fail").destroy_all
          add_filter(" ci-fail ", :header, "X-GitHub-Event", :equals, "check_suite")
          add_filter("ci-fail", :payload, "$.check_suite.conclusion", :equals, "failure")
        end

        it "treats them as one group" do
          expect(evaluator.passes?).to be false
        end
      end
    end

    context "with all filters in the default group (backward compatibility)" do
      let(:webhook) do
        create(:webhook, headers: { "HTTP_X_API_KEY" => "secret123" }, payload: { event: "order.created" }.to_json)
      end
      let(:evaluator) { described_class.new(webhook, target) }

      before do
        create(:filter, :header_equals, target: target, value: "secret123")
        create(:filter, :payload_equals, target: target, value: "order.created")
      end

      it "passes when all filters match" do
        expect(evaluator.passes?).to be true
      end

      it "fails when any single filter fails" do
        webhook.update!(headers: { "HTTP_X_API_KEY" => "wrong" })
        expect(evaluator.passes?).to be false
      end
    end
  end
end
