import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "template"]

  add() {
    const template = this.templateTarget.innerHTML
    const newRow = document.createElement("div")
    newRow.innerHTML = template
    this.templateTarget.before(newRow.firstElementChild)
  }

  remove(event) {
    event.target.closest("[data-headers-target='row']").remove()
  }
}
