// Tests for the grouped filter editor (app/javascript/controllers/filters_controller.js).
// Run with `npm test`. The markup below mirrors the data attributes rendered by
// app/views/admin/targets/_filter_group.html.erb and _filter_row.html.erb; their server-side structure is covered by
// spec/requests/admin/target_filter_editor_spec.rb.
import { test, beforeEach, before, after } from "node:test"
import assert from "node:assert/strict"
import { JSDOM } from "jsdom"

const dom = new JSDOM("<!doctype html><html><body></body></html>", { url: "http://localhost/" })
for (const key of ["window", "document", "MutationObserver", "Element", "HTMLElement", "Node", "Event",
  "KeyboardEvent", "MouseEvent", "CustomEvent", "localStorage"]) {
  globalThis[key] = key === "window" ? dom.window : dom.window[key]
}
dom.window.HTMLElement.prototype.scrollIntoView = function () {}

const { Application } = await import("@hotwired/stimulus")
const { default: FiltersController } = await import("../../app/javascript/controllers/filters_controller.js")

const STORAGE_KEY = "hookshot:target:1:collapsed-filter-groups"
let application

before(() => {
  application = Application.start(document.documentElement)
  application.register("filters", FiltersController)
})

after(() => application.stop())

beforeEach(() => {
  document.body.innerHTML = ""
  localStorage.clear()
})

// Option labels as rendered by Filter.operator_options / filter_types titleized
const LABELS = { header: "Header", payload: "Payload", exists: "Exists", equals: "Equals",
  matches: "Matches (wildcard)", regex: "Matches regex" }

// Markup helpers --------------------------------------------------------------------------------------------------

function row({ index, id = null, group = "default", type = "header", field = "", operator = "exists", value = "" }) {
  const option = (current, name) => `<option value="${name}" ${current === name ? "selected" : ""}>${LABELS[name]}</option>`
  const name = (attr) => `target[filters_attributes][${index}][${attr}]`

  return `
    <div class="relative" data-filters-target="row">
      <span data-and-label>and</span>
      ${id ? `<input type="hidden" name="${name("id")}" value="${id}">` : ""}
      <input type="hidden" name="${name("_destroy")}" value="false" class="destroy-field">
      <input type="hidden" name="${name("group_key")}" value="${group}" class="group-field">
      <select name="${name("filter_type")}">${option(type, "header")}${option(type, "payload")}</select>
      <input type="text" name="${name("field")}" value="${field}">
      <select name="${name("operator")}">${["exists", "equals", "matches", "regex"].map((o) => option(operator, o)).join("")}</select>
      <input type="text" name="${name("value")}" value="${value}">
      <button type="button" data-action="click->filters#removeFilter">x</button>
    </div>`
}

function group(name, rows) {
  return `
    <div data-filters-target="group">
      <div data-or-divider>or</div>
      <section>
        <button type="button" aria-expanded="true" data-collapse-toggle data-action="click->filters#toggleGroup">
          <svg data-collapse-icon></svg>
        </button>
        <input type="text" value="${name}" data-group-name data-action="input->filters#renameGroup">
        <span data-group-hint>All filters in this group must match</span>
        <button type="button" data-action="click->filters#removeGroup">Remove group</button>
        <p data-duplicate-warning hidden>duplicate</p>
        <button type="button" data-group-summary data-action="click->filters#toggleGroup" hidden></button>
        <div data-group-body>
          <div data-rows>${rows.join("")}</div>
          <p data-empty-hint hidden>empty</p>
          <button type="button" data-action="click->filters#addFilter">Add filter</button>
        </div>
      </section>
    </div>`
}

async function mount(groups, { storageKey = STORAGE_KEY } = {}) {
  document.body.innerHTML = `
    <div id="filters" data-controller="filters" data-filters-storage-key-value="${storageKey}">
      <button type="button" id="collapse-all" data-action="click->filters#collapseAll">Collapse all</button>
      <button type="button" id="expand-all" data-action="click->filters#expandAll">Expand all</button>
      <div data-filters-target="groups">${groups.join("")}</div>
      <template data-filters-target="groupTemplate">${group("", [row({ index: "NEW_INDEX" })])}</template>
      <template data-filters-target="rowTemplate">${row({ index: "NEW_INDEX" })}</template>
      <button type="button" id="add-group" data-action="click->filters#addGroup">Add group</button>
    </div>`
  await tick()
}

const tick = () => new Promise((resolve) => setTimeout(resolve, 0))

// Query helpers ---------------------------------------------------------------------------------------------------

const cards = () => [...document.querySelectorAll("[data-filters-target='groups'] > [data-filters-target='group']")]
const visibleCards = () => cards().filter((card) => !card.hidden)
const cardNamed = (name) => cards().find((card) => card.querySelector("[data-group-name]").value === name)
const rowsOf = (card) => [...card.querySelectorAll("[data-filters-target='row']")]
const groupKeys = (card) => rowsOf(card).map((r) => r.querySelector(".group-field").value)
// Stimulus connects actions of newly inserted elements asynchronously, so let it observe DOM changes after each event
async function click(element) {
  element.dispatchEvent(new MouseEvent("click", { bubbles: true }))
  await tick()
}
const storedNames = () => JSON.parse(localStorage.getItem(STORAGE_KEY) || "null")

async function rename(card, name) {
  const input = card.querySelector("[data-group-name]")
  input.value = name
  input.dispatchEvent(new Event("input", { bubbles: true }))
  await tick()
}

const reconciler = () => [
  group("ci-fail", [
    row({ index: 0, id: 10, group: "ci-fail", field: "X-GitHub-Event", operator: "equals", value: "check_suite" }),
    row({ index: 1, id: 11, group: "ci-fail", type: "payload", field: "$.check_suite.conclusion", operator: "equals", value: "failure" })
  ]),
  group("pr-closed", [
    row({ index: 2, id: 12, group: "pr-closed", field: "X-GitHub-Event", operator: "equals", value: "pull_request" })
  ])
]

// Rendering markers -----------------------------------------------------------------------------------------------

test("hides the OR divider of the first group and the AND label of the first row in each group", async () => {
  await mount(reconciler())

  assert.deepEqual(cards().map((c) => c.querySelector("[data-or-divider]").hidden), [true, false])
  assert.deepEqual(rowsOf(cardNamed("ci-fail")).map((r) => r.querySelector("[data-and-label]").hidden), [true, false])
  assert.deepEqual(rowsOf(cardNamed("pr-closed")).map((r) => r.querySelector("[data-and-label]").hidden), [true])
})

// Renaming --------------------------------------------------------------------------------------------------------

test("renaming a group updates the hidden group key of each of its rows", async () => {
  await mount(reconciler())

  await rename(cardNamed("ci-fail"), "  ci-failure ")

  assert.deepEqual(groupKeys(cards()[0]), ["ci-failure", "ci-failure"])
  assert.deepEqual(groupKeys(cardNamed("pr-closed")), ["pr-closed"])
})

test("a blank group name falls back to default", async () => {
  await mount(reconciler())

  await rename(cardNamed("pr-closed"), "   ")

  assert.deepEqual(groupKeys(cards()[1]), ["default"])
})

test("warns while two groups share a name and clears the warning once renamed", async () => {
  await mount(reconciler())
  const [first, second] = cards()

  await rename(second, "ci-fail")
  for (const card of [first, second]) {
    assert.equal(card.querySelector("[data-duplicate-warning]").hidden, false)
    assert.ok(card.querySelector("[data-group-name]").classList.contains("input-warning"))
  }

  await rename(second, "pr-merged")
  for (const card of [first, second]) {
    assert.equal(card.querySelector("[data-duplicate-warning]").hidden, true)
    assert.ok(!card.querySelector("[data-group-name]").classList.contains("input-warning"))
  }
})

// Adding ----------------------------------------------------------------------------------------------------------

test("adding a filter appends a row to that group with a fresh index and the group's key", async () => {
  await mount(reconciler())
  const card = cardNamed("pr-closed")

  await click(card.querySelector("[data-action='click->filters#addFilter']"))
  await click(card.querySelector("[data-action='click->filters#addFilter']"))

  const rows = rowsOf(card)
  assert.equal(rows.length, 3)
  assert.deepEqual(groupKeys(card), ["pr-closed", "pr-closed", "pr-closed"])
  assert.equal(rows[1].querySelector("[name$='[field]']").name, "target[filters_attributes][1000][field]")
  assert.equal(rows[2].querySelector("[name$='[field]']").name, "target[filters_attributes][1001][field]")
  assert.deepEqual(rows.map((r) => r.querySelector("[data-and-label]").hidden), [true, false, false])
})

test("adding a group names it default when free, otherwise a unique group-N", async () => {
  await mount([group("only", [row({ index: 0, id: 1, group: "only" })])])

  await click(document.getElementById("add-group"))
  await click(document.getElementById("add-group"))
  await click(document.getElementById("add-group"))

  const names = cards().map((c) => c.querySelector("[data-group-name]").value)
  assert.deepEqual(names, ["only", "default", "group-3", "group-4"])
  assert.deepEqual(groupKeys(cards()[2]), ["group-3"])
  assert.equal(cards()[2].querySelector("[data-or-divider]").hidden, false)
})

test("new groups get distinct nested attribute indexes", async () => {
  await mount(reconciler())

  await click(document.getElementById("add-group"))
  await click(cards()[2].querySelector("[data-action='click->filters#addFilter']"))

  const names = rowsOf(cards()[2]).map((r) => r.querySelector("[name$='[field]']").name)
  assert.deepEqual(names, ["target[filters_attributes][1000][field]", "target[filters_attributes][1001][field]"])
})

// Removing --------------------------------------------------------------------------------------------------------

test("removing a saved filter hides it and flags it for destruction", async () => {
  await mount(reconciler())
  const [first, second] = rowsOf(cardNamed("ci-fail"))

  await click(first.querySelector("[data-action='click->filters#removeFilter']"))

  assert.equal(first.hidden, true)
  assert.equal(first.querySelector(".destroy-field").value, "true")
  assert.equal(second.querySelector("[data-and-label]").hidden, true, "the next row becomes the first visible one")
})

test("removing a new filter drops it from the form", async () => {
  await mount(reconciler())
  const card = cardNamed("pr-closed")
  await click(card.querySelector("[data-action='click->filters#addFilter']"))

  await click(rowsOf(card)[1].querySelector("[data-action='click->filters#removeFilter']"))

  assert.equal(rowsOf(card).length, 1)
})

test("shows the empty hint once a group has no visible filters", async () => {
  await mount(reconciler())
  const card = cardNamed("pr-closed")

  await click(rowsOf(card)[0].querySelector("[data-action='click->filters#removeFilter']"))

  assert.equal(card.querySelector("[data-empty-hint]").hidden, false)
})

test("removing a saved group hides it and flags all of its filters for destruction", async () => {
  await mount(reconciler())
  const card = cardNamed("ci-fail")

  await click(card.querySelector("[data-action='click->filters#removeGroup']"))

  assert.equal(card.hidden, true)
  assert.deepEqual(rowsOf(card).map((r) => r.querySelector(".destroy-field").value), ["true", "true"])
  assert.equal(cardNamed("pr-closed").querySelector("[data-or-divider]").hidden, true, "next group becomes first")
})

test("removing a group with only new filters drops it from the form", async () => {
  await mount(reconciler())
  await click(document.getElementById("add-group"))

  await click(cards()[2].querySelector("[data-action='click->filters#removeGroup']"))

  assert.equal(cards().length, 2)
})

test("removed groups do not count as duplicates or take a name", async () => {
  await mount(reconciler())
  await click(cardNamed("pr-closed").querySelector("[data-action='click->filters#removeGroup']"))

  await rename(cards()[0], "pr-closed")

  assert.equal(cards()[0].querySelector("[data-duplicate-warning]").hidden, true)
})

// Collapsing ------------------------------------------------------------------------------------------------------

test("collapsing a group hides its filters and shows a summary", async () => {
  await mount(reconciler())
  const card = cardNamed("ci-fail")

  await click(card.querySelector("[data-collapse-toggle]"))

  assert.equal(card.querySelector("[data-group-body]").hidden, true)
  assert.equal(card.querySelector("[data-group-hint]").hidden, true)
  assert.equal(card.querySelector("[data-collapse-toggle]").getAttribute("aria-expanded"), "false")
  assert.equal(card.querySelector("[data-collapse-toggle]").title, "Expand group")
  const summary = card.querySelector("[data-group-summary]")
  assert.equal(summary.hidden, false)
  assert.equal(summary.textContent,
    "2 filters: Header X-GitHub-Event equals check_suite AND Payload $.check_suite.conclusion equals failure")
})

test("collapsed filters stay in the form so they are still submitted", async () => {
  await mount(reconciler())
  const card = cardNamed("ci-fail")

  await click(card.querySelector("[data-collapse-toggle]"))
  await rename(card, "ci-failure")

  assert.equal(card.querySelectorAll("[name^='target[filters_attributes]']").length, 14)
  assert.deepEqual(groupKeys(card), ["ci-failure", "ci-failure"])
})

test("the summary omits the value for exists filters, marks a missing field and reports empty groups", async () => {
  await mount([
    group("a", [row({ index: 0, id: 1, group: "a", field: "X-Api-Key", operator: "exists", value: "ignored" })]),
    group("b", [row({ index: 1, id: 2, group: "b", field: "", operator: "equals", value: "x" })]),
    group("c", [row({ index: 2, id: 3, group: "c", field: "X-Gone" })])
  ])
  await click(rowsOf(cardNamed("c"))[0].querySelector("[data-action='click->filters#removeFilter']"))

  await click(document.getElementById("collapse-all"))

  const summaries = cards().map((c) => c.querySelector("[data-group-summary]").textContent)
  assert.deepEqual(summaries, [
    "1 filter: Header X-Api-Key exists",
    "1 filter: Header ? equals x",
    "No filters - this group is ignored"
  ])
})

test("the summary names wildcard and regex operators by their labels", async () => {
  await mount([
    group("bots", [
      row({ index: 0, id: 1, group: "bots", field: "X-GitHub-Event", operator: "matches", value: "pull_request*" }),
      row({ index: 1, id: 2, group: "bots", type: "payload", field: "$.sender.login", operator: "regex", value: "\\A\\w+\\[bot\\]\\z" })
    ])
  ])

  await click(document.getElementById("collapse-all"))

  assert.equal(cardNamed("bots").querySelector("[data-group-summary]").textContent,
    "2 filters: Header X-GitHub-Event matches (wildcard) pull_request* AND Payload $.sender.login matches regex \\A\\w+\\[bot\\]\\z")
})

test("clicking the summary expands the group again", async () => {
  await mount(reconciler())
  const card = cardNamed("ci-fail")
  await click(card.querySelector("[data-collapse-toggle]"))

  await click(card.querySelector("[data-group-summary]"))

  assert.equal(card.querySelector("[data-group-body]").hidden, false)
  assert.equal(card.querySelector("[data-group-summary]").hidden, true)
  assert.equal(card.querySelector("[data-collapse-toggle]").getAttribute("aria-expanded"), "true")
})

test("collapse all and expand all apply to every visible group", async () => {
  await mount(reconciler())

  await click(document.getElementById("collapse-all"))
  assert.deepEqual(cards().map((c) => c.hasAttribute("data-collapsed")), [true, true])

  await click(document.getElementById("expand-all"))
  assert.deepEqual(cards().map((c) => c.hasAttribute("data-collapsed")), [false, false])
})

test("a newly added group starts expanded while others stay collapsed", async () => {
  await mount(reconciler())
  await click(document.getElementById("collapse-all"))

  await click(document.getElementById("add-group"))

  assert.deepEqual(cards().map((c) => c.hasAttribute("data-collapsed")), [true, true, false])
})

// Remembering collapsed groups ------------------------------------------------------------------------------------

test("remembers collapsed groups by name", async () => {
  await mount(reconciler())

  await click(cardNamed("pr-closed").querySelector("[data-collapse-toggle]"))
  assert.deepEqual(storedNames(), ["pr-closed"])

  await click(cardNamed("ci-fail").querySelector("[data-collapse-toggle]"))
  assert.deepEqual(storedNames(), ["ci-fail", "pr-closed"])
})

test("restores collapsed groups when the editor loads", async () => {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(["pr-closed", "no-longer-exists"]))

  await mount(reconciler())

  assert.deepEqual(cards().map((c) => c.hasAttribute("data-collapsed")), [false, true])
  assert.match(cardNamed("pr-closed").querySelector("[data-group-summary]").textContent, /^1 filter: Header X-GitHub-Event/)
})

test("renaming a collapsed group keeps it remembered under the new name", async () => {
  await mount(reconciler())
  const card = cardNamed("ci-fail")
  await click(card.querySelector("[data-collapse-toggle]"))

  await rename(card, "ci-failure")

  assert.deepEqual(storedNames(), ["ci-failure"])
})

test("removing a collapsed group forgets it", async () => {
  await mount(reconciler())
  const card = cardNamed("ci-fail")
  await click(card.querySelector("[data-collapse-toggle]"))

  await click(card.querySelector("[data-action='click->filters#removeGroup']"))

  assert.equal(localStorage.getItem(STORAGE_KEY), null)
})

test("expanding everything clears the stored state", async () => {
  await mount(reconciler())
  await click(document.getElementById("collapse-all"))

  await click(document.getElementById("expand-all"))

  assert.equal(localStorage.getItem(STORAGE_KEY), null)
})

test("does not store anything without a storage key (unsaved target)", async () => {
  await mount(reconciler(), { storageKey: "" })

  await click(document.getElementById("collapse-all"))

  assert.equal(localStorage.length, 0)
  assert.deepEqual(cards().map((c) => c.hasAttribute("data-collapsed")), [true, true])
})

test("ignores corrupted or unexpected stored state", async () => {
  localStorage.setItem(STORAGE_KEY, "{not json")
  await mount(reconciler())
  assert.deepEqual(cards().map((c) => c.hasAttribute("data-collapsed")), [false, false])

  localStorage.setItem(STORAGE_KEY, JSON.stringify({ "ci-fail": true }))
  await mount(reconciler())
  assert.deepEqual(cards().map((c) => c.hasAttribute("data-collapsed")), [false, false])
})

test("keeps working when storage is unavailable", async () => {
  const storage = Object.getPrototypeOf(localStorage)
  const { getItem, setItem } = storage
  storage.getItem = () => { throw new Error("blocked") }
  storage.setItem = () => { throw new Error("blocked") }

  try {
    await mount(reconciler())
    await click(document.getElementById("collapse-all"))

    assert.deepEqual(cards().map((c) => c.hasAttribute("data-collapsed")), [true, true])
  } finally {
    storage.getItem = getItem
    storage.setItem = setItem
  }
})
