// Tests for row selection on the dispatches index (app/javascript/controllers/bulk_select_controller.js).
// The markup mirrors app/views/admin/dispatches/index.html.erb, whose server-side structure is covered by
// spec/requests/admin/dispatches_spec.rb.
import { test, beforeEach, before, after } from "node:test"
import assert from "node:assert/strict"
import { JSDOM } from "jsdom"

const dom = new JSDOM("<!doctype html><html><body></body></html>", { url: "http://localhost/" })
for (const key of ["window", "document", "MutationObserver", "Element", "HTMLElement", "Node", "Event",
  "KeyboardEvent", "MouseEvent", "CustomEvent"]) {
  globalThis[key] = key === "window" ? dom.window : dom.window[key]
}

const { Application } = await import("@hotwired/stimulus")
const { default: BulkSelectController } = await import("../../app/javascript/controllers/bulk_select_controller.js")

let application
let navigations

before(() => {
  application = Application.start(document.documentElement)
  application.register("bulk-select", BulkSelectController)
})

after(() => application.stop())

beforeEach(() => {
  document.body.innerHTML = ""
  navigations = 0
})

async function mount(ids) {
  document.body.innerHTML = `
    <div data-controller="bulk-select">
      <form id="bulk-retry-form">
        <button type="submit" data-bulk-select-target="submit" disabled>
          Retry selected (<span data-bulk-select-target="count">0</span>)
        </button>
      </form>
      <table>
        <thead><tr><th><input type="checkbox" data-bulk-select-target="all" data-action="change->bulk-select#toggleAll"></th></tr></thead>
        <tbody>
          ${ids.map((id) => `
            <tr data-row>
              <td data-action="click->bulk-select#stop">
                <input type="checkbox" name="delivery_ids[]" value="${id}" form="bulk-retry-form"
                       data-bulk-select-target="item" data-action="click->bulk-select#toggle">
              </td>
              <td class="cell">#${id}</td>
            </tr>`).join("")}
        </tbody>
      </table>
    </div>`
  // Stands in for the row's inline onclick navigation (jsdom does not run inline handlers)
  document.querySelectorAll("[data-row]").forEach((row) => row.addEventListener("click", () => { navigations++ }))
  await tick()
}

const tick = () => new Promise((resolve) => setTimeout(resolve, 0))
const items = () => [...document.querySelectorAll("[data-bulk-select-target='item']")]
const all = () => document.querySelector("[data-bulk-select-target='all']")
const submit = () => document.querySelector("[data-bulk-select-target='submit']")
const count = () => document.querySelector("[data-bulk-select-target='count']").textContent
const checked = () => items().filter((item) => item.checked).map((item) => item.value)

// A real click toggles the checkbox before listeners run, which is what the controller relies on
function clickItem(index, { shiftKey = false } = {}) {
  items()[index].dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, shiftKey }))
}

function toggleAll(value) {
  all().checked = value
  all().dispatchEvent(new Event("change", { bubbles: true }))
}

test("starts with nothing selected and the submit button disabled", async () => {
  await mount([1, 2, 3])

  assert.equal(submit().disabled, true)
  assert.equal(count(), "0")
  assert.equal(all().checked, false)
  assert.equal(all().indeterminate, false)
})

test("selecting a row enables the button and updates the count", async () => {
  await mount([1, 2, 3])

  clickItem(1)

  assert.deepEqual(checked(), ["2"])
  assert.equal(submit().disabled, false)
  assert.equal(count(), "1")
  assert.equal(all().indeterminate, true)
})

test("unselecting the last row disables the button again", async () => {
  await mount([1, 2, 3])

  clickItem(0)
  clickItem(0)

  assert.equal(submit().disabled, true)
  assert.equal(count(), "0")
  assert.equal(all().indeterminate, false)
})

test("select all checks every row and unselect all clears them", async () => {
  await mount([1, 2, 3])

  toggleAll(true)
  assert.deepEqual(checked(), ["1", "2", "3"])
  assert.equal(count(), "3")
  assert.equal(all().indeterminate, false)

  toggleAll(false)
  assert.deepEqual(checked(), [])
  assert.equal(submit().disabled, true)
})

test("the select-all checkbox becomes checked once every row is selected by hand", async () => {
  await mount([1, 2])

  clickItem(0)
  clickItem(1)

  assert.equal(all().checked, true)
  assert.equal(all().indeterminate, false)
})

test("shift-click selects the range since the last clicked row", async () => {
  await mount([1, 2, 3, 4, 5])

  clickItem(1)
  clickItem(4, { shiftKey: true })

  assert.deepEqual(checked(), ["2", "3", "4", "5"])
  assert.equal(count(), "4")
})

test("shift-click works upwards and can unselect a range", async () => {
  await mount([1, 2, 3, 4, 5])
  toggleAll(true)

  clickItem(3)
  clickItem(1, { shiftKey: true })

  assert.deepEqual(checked(), ["1", "5"])
})

test("shift-click without a previous click only toggles that row", async () => {
  await mount([1, 2, 3])

  clickItem(2, { shiftKey: true })

  assert.deepEqual(checked(), ["3"])
})

test("select all resets the range anchor", async () => {
  await mount([1, 2, 3, 4])
  clickItem(0)
  toggleAll(false)

  clickItem(3, { shiftKey: true })

  assert.deepEqual(checked(), ["4"])
})

test("clicking a checkbox does not trigger the row navigation", async () => {
  await mount([1, 2])

  clickItem(0)

  assert.equal(navigations, 0)
})

test("clicking elsewhere in the row still navigates", async () => {
  await mount([1, 2])

  document.querySelector(".cell").dispatchEvent(new MouseEvent("click", { bubbles: true }))

  assert.equal(navigations, 1)
})

test("reflects checkboxes the browser kept checked (e.g. after navigating back)", async () => {
  await mount([1, 2])
  items()[0].checked = true

  application.getControllerForElementAndIdentifier(document.querySelector("[data-controller]"), "bulk-select").connect()

  assert.equal(submit().disabled, false)
  assert.equal(count(), "1")
})

test("works without a select-all checkbox when no rows are selectable", async () => {
  document.body.innerHTML = `
    <div data-controller="bulk-select">
      <button type="submit" data-bulk-select-target="submit" disabled>Retry</button>
    </div>`
  await tick()

  assert.equal(submit().disabled, true)
})
