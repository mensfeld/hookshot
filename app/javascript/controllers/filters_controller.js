import { Controller } from "@hotwired/stimulus"

const DEFAULT_GROUP = "default"

export default class extends Controller {
  static targets = ["row", "template"]
  static values = { index: { type: Number, default: 1000 } }

  add() {
    const template = this.templateTarget.innerHTML.replace(/NEW_INDEX/g, this.indexValue)
    const newRow = document.createElement("div")
    newRow.innerHTML = template
    const row = newRow.firstElementChild

    // Prefill the group with the last used one so adding another filter to the same group is one click
    const groupField = row.querySelector(".group-field")
    if (groupField) groupField.value = this.lastGroup()

    this.templateTarget.before(row)
    this.indexValue++
  }

  remove(event) {
    const row = event.target.closest("[data-filters-target='row']")
    const destroyField = row.querySelector(".destroy-field")

    if (destroyField) {
      // Existing record - mark for destruction
      destroyField.value = "true"
      row.style.display = "none"
    } else {
      // New record - just remove from DOM
      row.remove()
    }
  }

  lastGroup() {
    const visibleRows = this.rowTargets.filter((row) => row.style.display !== "none")
    const lastRow = visibleRows[visibleRows.length - 1]
    const value = lastRow?.querySelector(".group-field")?.value.trim()

    return value || DEFAULT_GROUP
  }
}
