import { Controller } from "@hotwired/stimulus"

const DEFAULT_GROUP = "default"

// Edits filters as group cards: filters inside a card are AND-ed, cards are OR-ed.
// Each card has a name input (not submitted) that is mirrored into the hidden group_key field of its rows.
export default class extends Controller {
  static targets = ["groups", "group", "row", "groupTemplate", "rowTemplate"]
  static values = { index: { type: Number, default: 1000 }, storageKey: String }

  connect() {
    this.restoreCollapsed()
    this.refresh()
  }

  addGroup() {
    const group = this.build(this.groupTemplateTarget)
    group.querySelector("[data-group-name]").value = this.uniqueGroupName()
    this.groupsTarget.append(group)
    group.scrollIntoView({ block: "nearest" })

    this.syncGroup(group)
    this.refresh()
    group.querySelector("[data-group-name]").select()
  }

  addFilter(event) {
    const group = event.target.closest("[data-filters-target='group']")
    const row = this.build(this.rowTemplateTarget)
    group.querySelector("[data-rows]").append(row)

    this.syncGroup(group)
    this.refresh()
    row.querySelector("input[type='text']")?.focus()
  }

  removeFilter(event) {
    this.discardRow(event.target.closest("[data-filters-target='row']"))
    this.refresh()
  }

  removeGroup(event) {
    const group = event.target.closest("[data-filters-target='group']")
    group.querySelectorAll("[data-filters-target='row']").forEach((row) => this.discardRow(row))

    // Keep the card (hidden) while it still holds rows that must be submitted for destruction
    if (group.querySelector("[data-filters-target='row']")) {
      group.hidden = true
    } else {
      group.remove()
    }
    this.refresh()
    this.storeCollapsed()
  }

  toggleGroup(event) {
    const group = event.target.closest("[data-filters-target='group']")
    this.setCollapsed(group, !group.hasAttribute("data-collapsed"))
    this.storeCollapsed()
  }

  collapseAll() {
    this.visible(this.groupTargets).forEach((group) => this.setCollapsed(group, true))
    this.storeCollapsed()
  }

  expandAll() {
    this.visible(this.groupTargets).forEach((group) => this.setCollapsed(group, false))
    this.storeCollapsed()
  }

  // A collapsed group keeps its fields in the form (they are still submitted) and shows a one-line summary instead
  setCollapsed(group, collapsed) {
    const toggle = group.querySelector("[data-collapse-toggle]")
    const summary = group.querySelector("[data-group-summary]")

    group.toggleAttribute("data-collapsed", collapsed)
    group.querySelector("[data-group-body]").hidden = collapsed
    group.querySelector("[data-group-hint]").hidden = collapsed
    group.querySelector("[data-collapse-icon]").classList.toggle("-rotate-90", collapsed)
    toggle.setAttribute("aria-expanded", String(!collapsed))
    toggle.title = collapsed ? "Expand group" : "Collapse group"
    toggle.setAttribute("aria-label", toggle.title)
    summary.hidden = !collapsed
    if (collapsed) summary.textContent = this.summarize(group)
  }

  summarize(group) {
    const rows = this.visible([...group.querySelectorAll("[data-filters-target='row']")])
    if (rows.length === 0) return "No filters - this group is ignored"

    const conditions = rows.map((row) => {
      const text = (selector) => row.querySelector(selector)?.value.trim() || ""
      const label = (selector) => row.querySelector(selector)?.selectedOptions[0]?.text || ""
      const operator = label("select[name$='[operator]']").toLowerCase()
      const value = operator === "exists" ? "" : ` ${text("input[name$='[value]']")}`
      return `${label("select[name$='[filter_type]']")} ${text("input[name$='[field]']") || "?"} ${operator}${value}`
    })
    const count = rows.length === 1 ? "1 filter" : `${rows.length} filters`

    return `${count}: ${conditions.join(" AND ")}`
  }

  renameGroup(event) {
    this.syncGroup(event.target.closest("[data-filters-target='group']"))
    this.refresh()
    this.storeCollapsed()
  }

  // Collapsed groups are remembered per target (by group name) in this browser only; storage may be unavailable
  restoreCollapsed() {
    if (!this.storageKeyValue) return

    let names = []
    try {
      names = JSON.parse(localStorage.getItem(this.storageKeyValue) || "[]")
    } catch {
      return
    }
    if (!Array.isArray(names)) return

    this.visible(this.groupTargets).forEach((group) => {
      if (names.includes(this.groupName(group))) this.setCollapsed(group, true)
    })
  }

  storeCollapsed() {
    if (!this.storageKeyValue) return

    const names = this.visible(this.groupTargets)
      .filter((group) => group.hasAttribute("data-collapsed"))
      .map((group) => this.groupName(group))

    try {
      if (names.length > 0) {
        localStorage.setItem(this.storageKeyValue, JSON.stringify(names))
      } else {
        localStorage.removeItem(this.storageKeyValue)
      }
    } catch {
      // Storage blocked (private mode, disabled site data) - collapsing still works for this page view
    }
  }

  // Existing records are hidden and flagged for destruction, new ones are dropped from the DOM
  discardRow(row) {
    const destroyField = row.querySelector(".destroy-field")
    const persisted = row.querySelector("input[name$='[id]']")

    if (persisted) {
      destroyField.value = "true"
      row.hidden = true
    } else {
      row.remove()
    }
  }

  syncGroup(group) {
    const name = this.groupName(group)
    group.querySelectorAll(".group-field").forEach((field) => { field.value = name })
  }

  // Shows OR between visible groups and AND between visible rows of a group, flags empty groups and duplicate names
  refresh() {
    const groups = this.visible(this.groupTargets)
    const counts = {}
    groups.forEach((group) => {
      const name = this.groupName(group)
      counts[name] = (counts[name] || 0) + 1
    })

    groups.forEach((group, groupIndex) => {
      group.querySelector("[data-or-divider]").hidden = groupIndex === 0

      const rows = this.visible([...group.querySelectorAll("[data-filters-target='row']")])
      rows.forEach((row, rowIndex) => { row.querySelector("[data-and-label]").hidden = rowIndex === 0 })
      group.querySelector("[data-empty-hint]").hidden = rows.length > 0

      const duplicate = counts[this.groupName(group)] > 1
      group.querySelector("[data-group-name]").classList.toggle("input-warning", duplicate)
      group.querySelector("[data-duplicate-warning]").hidden = !duplicate
    })
  }

  build(template) {
    const wrapper = document.createElement("div")
    wrapper.innerHTML = template.innerHTML.replace(/NEW_INDEX/g, this.indexValue)
    this.indexValue++
    return wrapper.firstElementChild
  }

  groupName(group) {
    return group.querySelector("[data-group-name]").value.trim() || DEFAULT_GROUP
  }

  uniqueGroupName() {
    const taken = new Set(this.visible(this.groupTargets).map((group) => this.groupName(group)))
    if (!taken.has(DEFAULT_GROUP)) return DEFAULT_GROUP

    let number = taken.size + 1
    while (taken.has(`group-${number}`)) number++
    return `group-${number}`
  }

  visible(elements) {
    return elements.filter((element) => !element.hidden)
  }
}
