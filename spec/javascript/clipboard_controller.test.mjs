// Tests for the copy-to-clipboard button on endpoint URLs (app/javascript/controllers/clipboard_controller.js).
import { test, beforeEach, before, after } from "node:test"
import assert from "node:assert/strict"
import { JSDOM } from "jsdom"

const dom = new JSDOM("<!doctype html><html><body></body></html>", { url: "http://localhost/" })
for (const key of ["window", "document", "MutationObserver", "Element", "HTMLElement", "Node", "Event",
  "KeyboardEvent", "MouseEvent", "CustomEvent"]) {
  globalThis[key] = key === "window" ? dom.window : dom.window[key]
}

const { Application } = await import("@hotwired/stimulus")
const { default: ClipboardController } = await import("../../app/javascript/controllers/clipboard_controller.js")

let application
let copied

before(() => {
  application = Application.start(document.documentElement)
  application.register("clipboard", ClipboardController)
})

after(() => application.stop())

beforeEach(() => {
  copied = []
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: { clipboard: { writeText: async (text) => { copied.push(text) } } }
  })
})

const tick = (ms = 0) => new Promise((resolve) => setTimeout(resolve, ms))
const button = () => document.querySelector("button")

async function mount(text = "https://hookshot.example.com/webhooks/receive/deploys") {
  document.body.innerHTML = `
    <div data-controller="clipboard" data-clipboard-text-value="${text}">
      <button type="button" data-clipboard-target="button" data-action="click->clipboard#copy">Copy</button>
    </div>`
  await tick()
}

test("copies the URL and confirms on the button, then restores the label", async () => {
  await mount()

  button().click()
  await tick()

  assert.deepEqual(copied, ["https://hookshot.example.com/webhooks/receive/deploys"])
  assert.equal(button().textContent, "Copied")

  await tick(1600)
  assert.equal(button().textContent, "Copy")
})

test("reports a failure when the clipboard is unavailable", async () => {
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: { clipboard: { writeText: async () => { throw new Error("denied") } } }
  })
  await mount()

  button().click()
  await tick()

  assert.equal(button().textContent, "Copy failed")
})

test("restores the original label after repeated clicks", async () => {
  await mount()

  button().click()
  await tick()
  button().click()
  await tick()
  await tick(1600)

  assert.equal(button().textContent, "Copy")
  assert.equal(copied.length, 2)
})
