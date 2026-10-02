# frozen_string_literal: true

require "rails_helper"

# Server-rendered structure of the grouped filter editor on the target form. The client-side behavior (renaming,
# adding, removing, collapsing) is covered by spec/javascript/filters_controller.test.mjs.
RSpec.describe "Admin target filter editor" do
  let(:auth_headers) do
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "changeme") }
  end
  let(:target) { create(:target) }

  def editor
    Nokogiri::HTML(response.body).at_css("#filters")
  end

  # Group cards rendered for the target (excluding the ones inside <template> elements)
  def cards
    editor.css("[data-filters-target='groups'] > [data-filters-target='group']")
  end

  def card_named(name)
    cards.find { |card| card.at_css("[data-group-name]")["value"] == name }
  end

  def rows_in(card)
    card.css("[data-filters-target='row']")
  end

  def field_value(row, attribute)
    row.at_css("[name$='[#{attribute}]']")["value"]
  end

  context "with filters in several groups" do
    let!(:ci_event) do
      create(:filter, target: target, group_key: "ci-fail", filter_type: :header, field: "X-GitHub-Event",
        operator: :equals, value: "check_suite")
    end
    let!(:approved) do
      create(:filter, target: target, group_key: "approved", filter_type: :payload, field: "$.review.state",
        operator: :equals, value: "approved")
    end
    let!(:ci_conclusion) do
      create(:filter, target: target, group_key: "ci-fail", filter_type: :payload, field: "$.check_suite.conclusion",
        operator: :equals, value: "failure")
    end

    before { get "/admin/targets/#{target.id}/edit", headers: auth_headers }

    it "renders one card per group, ordered by group name" do
      expect(cards.map { |card| card.at_css("[data-group-name]")["value"] }).to eq(%w[approved ci-fail])
    end

    it "nests each filter inside the card of its group" do
      expect(rows_in(card_named("ci-fail")).map { |row| field_value(row, "id") })
        .to eq([ ci_event.id.to_s, ci_conclusion.id.to_s ])
      expect(rows_in(card_named("approved")).map { |row| field_value(row, "id") }).to eq([ approved.id.to_s ])
    end

    it "keeps the group key as a hidden field on every row matching its card" do
      cards.each do |card|
        name = card.at_css("[data-group-name]")["value"]
        rows_in(card).each do |row|
          group_field = row.at_css("input.group-field")
          expect(group_field["type"]).to eq("hidden")
          expect(group_field["value"]).to eq(name)
        end
      end
    end

    it "does not submit the group name input itself" do
      expect(cards.map { |card| card.at_css("[data-group-name]")["name"] }).to all(be_nil)
    end

    it "gives every rendered filter a unique nested attributes index" do
      indexes = cards.flat_map { |card| rows_in(card) }.map do |row|
        row.at_css("[name$='[field]']")["name"][/filters_attributes\]\[(\d+)\]/, 1]
      end

      expect(indexes).to eq(%w[0 1 2])
    end

    it "shows OR between groups and AND between filters of a group, but not before the first" do
      expect(cards.map { |card| card.at_css("[data-or-divider]").key?("hidden") }).to eq([ true, false ])
      expect(rows_in(card_named("ci-fail")).map { |row| row.at_css("[data-and-label]").key?("hidden") })
        .to eq([ true, false ])
    end

    it "renders every card expanded with collapse controls" do
      cards.each do |card|
        expect(card.at_css("[data-group-body]").key?("hidden")).to be false
        expect(card.at_css("[data-group-summary]").key?("hidden")).to be true
        expect(card.at_css("[data-collapse-toggle]")["aria-expanded"]).to eq("true")
      end
      expect(editor.text).to include("Collapse all", "Expand all")
    end

    it "scopes the remembered collapse state to the target" do
      expect(editor["data-filters-storage-key-value"]).to eq("hookshot:target:#{target.id}:collapsed-filter-groups")
    end

    it "provides templates for a new group and a new filter row" do
      group_template = editor.at_css("template[data-filters-target='groupTemplate']").inner_html
      row_template = editor.at_css("template[data-filters-target='rowTemplate']").inner_html

      expect(group_template).to include('name="target[filters_attributes][NEW_INDEX][field]"', "data-group-name")
      expect(row_template).to include('name="target[filters_attributes][NEW_INDEX][group_key]"')
      expect(row_template).not_to include("[id]")
    end
  end

  context "with a new target" do
    before { get "/admin/targets/new", headers: auth_headers }

    it "starts with a single default group holding one empty filter" do
      expect(cards.size).to eq(1)
      expect(cards.first.at_css("[data-group-name]")["value"]).to eq("default")
      expect(rows_in(cards.first).size).to eq(1)
    end

    it "does not remember collapse state before the target exists" do
      expect(editor["data-filters-storage-key-value"]).to be_blank
    end
  end

  context "when an update fails validation after filters were removed" do
    let!(:kept) { create(:filter, target: target, group_key: "a") }
    let!(:removed) { create(:filter, target: target, group_key: "a", field: "X-Removed") }
    let!(:removed_group_filter) { create(:filter, target: target, group_key: "b", field: "X-Gone") }

    before do
      patch "/admin/targets/#{target.id}", headers: auth_headers, params: {
        target: {
          url: "not-a-url",
          filters_attributes: {
            "0" => { id: kept.id },
            "1" => { id: removed.id, _destroy: "true" },
            "2" => { id: removed_group_filter.id, _destroy: "true" }
          }
        }
      }
    end

    it "re-renders the form" do
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "keeps removed filters hidden and still flagged for destruction" do
      row = cards.flat_map { |card| rows_in(card).to_a }.find { |r| field_value(r, "id") == removed.id.to_s }

      expect(row.key?("hidden")).to be true
      expect(field_value(row, "_destroy")).to eq("true")
    end

    it "hides a group whose filters were all removed" do
      expect(card_named("b").key?("hidden")).to be true
      expect(card_named("a").key?("hidden")).to be false
    end

    it "keeps remaining filters visible and not flagged" do
      row = rows_in(card_named("a")).find { |r| field_value(r, "id") == kept.id.to_s }

      expect(row.key?("hidden")).to be false
      expect(field_value(row, "_destroy")).to eq("false")
    end
  end

  it "round-trips a resubmitted form after a failed update without losing removals" do
    kept = create(:filter, target: target, group_key: "a")
    removed = create(:filter, target: target, group_key: "a", field: "X-Removed")
    params = { "0" => { id: kept.id }, "1" => { id: removed.id, _destroy: "true" } }

    patch "/admin/targets/#{target.id}", headers: auth_headers, params: { target: { url: "bad", filters_attributes: params } }
    patch "/admin/targets/#{target.id}", headers: auth_headers,
      params: { target: { url: "https://ok.example.com", filters_attributes: params } }

    expect(response).to redirect_to(admin_targets_path)
    expect(target.reload.filters).to eq([ kept ])
  end
end
