# frozen_string_literal: true

require "rails_helper"

# End-to-end coverage of filter groups: a target is configured through the admin form with several OR-ed groups
# (the "actionable GitHub events" use case) and real GitHub-style webhooks are then received and dispatched.
RSpec.describe "Filter groups end-to-end" do
  include ActiveJob::TestHelper

  let(:auth_headers) do
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "changeme") }
  end
  let(:target_url) { "https://reconciler.example.com/github" }

  let(:filter_rows) do
    [
      [ "changes-requested", "header", "X-GitHub-Event", "equals", "pull_request_review" ],
      [ "changes-requested", "payload", "$.action", "equals", "submitted" ],
      [ "changes-requested", "payload", "$.review.state", "equals", "changes_requested" ],
      [ "approved", "header", "X-GitHub-Event", "equals", "pull_request_review" ],
      [ "approved", "payload", "$.review.state", "equals", "approved" ],
      [ "ci-fail", "header", "X-GitHub-Event", "equals", "check_suite" ],
      [ "ci-fail", "payload", "$.action", "equals", "completed" ],
      [ "ci-fail", "payload", "$.check_suite.conclusion", "equals", "failure" ],
      [ "owner-comment", "header", "X-GitHub-Event", "equals", "issue_comment" ],
      [ "owner-comment", "payload", "$.issue.pull_request", "exists", "" ],
      [ "owner-comment", "payload", "$.comment.user.login", "equals", "mensfeld" ],
      [ "copilot-comment", "header", "X-GitHub-Event", "equals", "issue_comment" ],
      [ "copilot-comment", "payload", "$.issue.pull_request", "exists", "" ],
      [ "copilot-comment", "payload", "$.comment.user.login", "matches", "*copilot*" ],
      [ "bot-review", "header", "X-GitHub-Event", "regex", '\Apull_request_review(_comment)?\z' ],
      [ "bot-review", "payload", "$.sender.login", "regex", '(?i)\A(renovate|dependabot)\[bot\]\z' ],
      [ "pr-closed", "header", "X-GitHub-Event", "equals", "pull_request" ],
      [ "pr-closed", "payload", "$.action", "equals", "closed" ]
    ]
  end

  let(:target) { Target.find_by!(name: "Redmine reconciler") }

  before do
    filters_attributes = filter_rows.each_with_index.to_h do |(group_key, filter_type, field, operator, value), index|
      [ index.to_s, { group_key: group_key, filter_type: filter_type, field: field, operator: operator, value: value } ]
    end
    # A trailing empty row, as left behind by the admin form, must not break the save
    filters_attributes["1000"] = { group_key: "pr-closed", filter_type: "header", field: "", operator: "exists", value: "" }

    post "/admin/targets", headers: auth_headers, params: {
      target: { name: "Redmine reconciler", url: target_url, active: true, timeout: 30, filters_attributes: filters_attributes }
    }
    expect(response).to redirect_to(admin_targets_path)
  end

  def receive_github(event, payload)
    post "/webhooks/receive", params: payload.to_json, headers: {
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_GITHUB_EVENT" => event
    }
    expect(response).to have_http_status(:ok)

    Delivery.find_by!(webhook: Webhook.last, target: target)
  end

  it "stores all seven groups from the admin form" do
    expect(target.filters.count).to eq(filter_rows.size)
    expect(target.filter_groups.keys).to contain_exactly(
      "approved", "bot-review", "changes-requested", "ci-fail", "copilot-comment", "owner-comment", "pr-closed"
    )
  end

  {
    "a review requesting changes" => [
      "pull_request_review", { action: "submitted", review: { state: "changes_requested" } }
    ],
    "an approving review" => [
      "pull_request_review", { action: "submitted", review: { state: "approved" } }
    ],
    "a failed check suite" => [
      "check_suite", { action: "completed", check_suite: { conclusion: "failure" } }
    ],
    "a PR comment from the owner" => [
      "issue_comment", { action: "created", issue: { pull_request: { url: "x" } }, comment: { user: { login: "mensfeld" } } }
    ],
    "a PR comment from Copilot" => [
      "issue_comment",
      { action: "created", issue: { pull_request: { url: "x" } }, comment: { user: { login: "Copilot-Pull-Request-Reviewer" } } }
    ],
    "a closed PR" => [
      "pull_request", { action: "closed", pull_request: { merged: true } }
    ],
    "a review comment from Renovate (regex group)" => [
      "pull_request_review_comment", { action: "created", sender: { login: "renovate[bot]" } }
    ],
    "a review from Dependabot in any case (regex group)" => [
      "pull_request_review", { action: "submitted", review: { state: "commented" }, sender: { login: "Dependabot[bot]" } }
    ]
  }.each do |description, (event, payload)|
    it "delivers #{description}" do
      expect(receive_github(event, payload)).to be_pending
    end
  end

  {
    "a successful check suite (partial match of ci-fail)" => [
      "check_suite", { action: "completed", check_suite: { conclusion: "success" } }
    ],
    "a commented review" => [
      "pull_request_review", { action: "submitted", review: { state: "commented" } }
    ],
    "a PR comment from someone else" => [
      "issue_comment", { action: "created", issue: { pull_request: { url: "x" } }, comment: { user: { login: "octocat" } } }
    ],
    "an owner comment on a plain issue (not a PR)" => [
      "issue_comment", { action: "created", issue: { number: 1 }, comment: { user: { login: "mensfeld" } } }
    ],
    "an opened PR" => [
      "pull_request", { action: "opened" }
    ],
    "a push" => [
      "push", { ref: "refs/heads/master" }
    ],
    "a review comment from a look-alike account (anchored regex)" => [
      "pull_request_review_comment", { action: "created", sender: { login: "renovate[bot]-fan" } }
    ],
    "a bot comment on another event (regex header mismatch)" => [
      "pull_request_review_thread", { action: "resolved", sender: { login: "renovate[bot]" } }
    ],
    "a review comment without a sender" => [
      "pull_request_review_comment", { action: "created" }
    ],
    "a closed action on a non-PR event (header mismatch)" => [
      "issues", { action: "closed" }
    ]
  }.each do |description, (event, payload)|
    it "filters out #{description}" do
      expect(receive_github(event, payload)).to be_filtered
    end
  end

  it "forwards a matching webhook downstream and skips a partially matching one" do
    stub = stub_request(:post, target_url).to_return(status: 200)

    perform_enqueued_jobs do
      receive_github("check_suite", { action: "completed", check_suite: { conclusion: "success" } })
      receive_github("check_suite", { action: "completed", check_suite: { conclusion: "failure" } })
    end

    expect(stub).to have_been_requested.once
    expect(WebMock).to have_requested(:post, target_url).with { |req| req.body.include?("failure") }
    expect(Delivery.where(target: target).pluck(:status)).to contain_exactly("filtered", "success")
  end

  context "with a legacy target whose filters all sit in the default group" do
    let(:legacy_url) { "https://legacy.example.com/hook" }

    before do
      legacy = create(:target, url: legacy_url)
      create(:filter, target: legacy, filter_type: :header, field: "X-GitHub-Event", operator: :equals, value: "check_suite")
      create(:filter, target: legacy, filter_type: :payload, field: "$.check_suite.conclusion", operator: :equals, value: "failure")
    end

    it "keeps requiring every filter to match" do
      receive_github("check_suite", { action: "completed", check_suite: { conclusion: "success" } })
      expect(Delivery.joins(:target).where(targets: { url: legacy_url }).last).to be_filtered

      receive_github("check_suite", { action: "completed", check_suite: { conclusion: "failure" } })
      expect(Delivery.joins(:target).where(targets: { url: legacy_url }).last).to be_pending
    end
  end
end
