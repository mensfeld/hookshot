import { Controller } from "@hotwired/stimulus"

// Row selection for bulk actions: a "select all" checkbox, shift-click range selection and a submit button that is
// enabled only while something is selected.
export default class extends Controller {
  static targets = ["item", "all", "submit", "count"]

  connect() {
    this.lastIndex = null
    this.update()
  }

  toggle(event) {
    const index = this.itemTargets.indexOf(event.target)

    if (event.shiftKey && this.lastIndex !== null && index !== -1) {
      const [from, to] = [this.lastIndex, index].sort((a, b) => a - b)
      this.itemTargets.slice(from, to + 1).forEach((item) => { item.checked = event.target.checked })
    }

    this.lastIndex = index === -1 ? null : index
    this.update()
  }

  toggleAll() {
    this.itemTargets.forEach((item) => { item.checked = this.allTarget.checked })
    this.lastIndex = null
    this.update()
  }

  // Keeps clicks on the selection cell from triggering the row's own click handler (navigation)
  stop(event) {
    event.stopPropagation()
  }

  update() {
    const total = this.itemTargets.length
    const selected = this.itemTargets.filter((item) => item.checked).length

    if (this.hasAllTarget) {
      this.allTarget.checked = total > 0 && selected === total
      this.allTarget.indeterminate = selected > 0 && selected < total
      this.allTarget.disabled = total === 0
    }
    if (this.hasSubmitTarget) this.submitTarget.disabled = selected === 0
    if (this.hasCountTarget) this.countTarget.textContent = String(selected)
  }
}
