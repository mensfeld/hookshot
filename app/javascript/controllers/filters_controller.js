import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "template"]
  static values = { index: { type: Number, default: 1000 } }

  add() {
    const template = this.templateTarget.innerHTML.replace(/NEW_INDEX/g, this.indexValue)
    const newRow = document.createElement("div")
    newRow.innerHTML = template
    this.templateTarget.before(newRow.firstElementChild)
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
}
