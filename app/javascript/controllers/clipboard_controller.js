import { Controller } from "@hotwired/stimulus"

// Copies a value to the clipboard and briefly confirms it on the button.
export default class extends Controller {
  static targets = ["button"]
  static values = { text: String, copiedLabel: { type: String, default: "Copied" } }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
      this.flash(this.copiedLabelValue)
    } catch {
      this.flash("Copy failed")
    }
  }

  flash(label) {
    if (!this.hasButtonTarget) return

    this.originalLabel ??= this.buttonTarget.textContent
    this.buttonTarget.textContent = label
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => { this.buttonTarget.textContent = this.originalLabel }, 1500)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
