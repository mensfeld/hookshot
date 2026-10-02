# Hookshot changelog

## 1.3.0 (Unreleased)
- [Feature] Add a "Matches regex" filter operator that takes a Ruby regular expression. Matches are unanchored (use `\A`/`\z`), case-sensitive unless prefixed with `(?i)`, and never match missing fields.
- [Enhancement] Invalid regular expressions are rejected when saving a target, with the parser's reason shown in the form.
- [Enhancement] Regex matching is limited to 100ms per filter; a timed-out match counts as no match and is logged.
- [Enhancement] The existing `Matches` operator is labeled "Matches (wildcard)" to tell it apart, and the form explains both operators.

## 1.2.1 (2026-10-02)
- [Enhancement] Target form edits filters as group cards: each group has its own card with a name field, AND markers between its filters and an OR divider between groups, plus per-group "Add filter" and "Remove group" actions and an "Add group" button.
- [Enhancement] Filter groups can be collapsed to a one-line summary, individually or with "Collapse all" / "Expand all". Collapsed groups are remembered per target in the browser (localStorage).
- [Enhancement] Warn when two groups in the editor share a name (they are merged on save) and flag groups with no filters.
- [Fix] Filters removed in the form stay removed when the form is re-rendered after a validation error instead of reappearing as kept.
- [Fix] Filter inputs on the target form stretch to their full column width.
- [Maintenance] Add JavaScript tests for the filter editor (`npm test`, Node test runner with jsdom) and run them in CI.

## 1.2.0 (2026-09-30)
- [Feature] Add filter groups to targets: filters within a group must all match (AND) and a webhook is delivered when any group fully matches (OR). This lets one target express several alternative conditions instead of maintaining one target per condition.
- [Feature] Admin target form gets a per-filter Group input with suggestions of existing groups; newly added rows default to the last used group.
- [Enhancement] Target details page and targets index render the filter logic as an explicit OR of ANDs.
- [Enhancement] Add Ruby warning category opt-in to test helpers
- [Fix] Untouched filter rows (no field and no value) in the admin form are now dropped instead of failing target validation (the type/operator selects always carry values, so `all_blank` never rejected them). Partially filled rows and blanked fields on existing filters still report validation errors.
- [Maintenance] Add `group_key` column to `filters` (defaults to `default`). Existing filters land in the default group, so existing targets keep their all-filters-must-match behavior. Run `bin/rails db:migrate` when upgrading.

## 1.1.0 (2026-04-09)
- [Feature] Add case-insensitive text search to webhooks index for filtering by headers or payload content.

## 1.1.0 (2026-01-28)
- [Feature] Add self-contained error tracking system with Rails 8 error reporter integration.
- [Feature] Error deduplication by fingerprint with automatic occurrence counting.
- [Feature] Admin UI for viewing, filtering (unresolved/resolved/all), and managing application errors.
- [Feature] Error resolution workflow with resolve/unresolve actions.
- [Feature] Automatic error capture from all Rails executions (controllers, jobs, console, rake tasks).
- [Feature] Context sanitization with sensitive data redaction (passwords, tokens, API keys).
- [Feature] Backtrace cleaning to remove gem paths and focus on application code.
- [Feature] Background job processing via Solid Queue for non-blocking error capture.
- [Feature] Rake task for cleaning up resolved errors older than 30 days (`rake errors:cleanup`).
- [Enhancement] Errors accessible at `/errors` route with HTTP Basic Auth.
- [Enhancement] Comprehensive test coverage (94.3% line, 86.11% branch) with 73 new specs.
- [Technical] Exclude DispatchJob errors (operational cases tracked via Delivery model).
- [Technical] Smart fingerprinting that normalizes UUIDs, numbers, hex addresses, and paths.

## 1.0.1 (2025-01-23)
- [Enhancement] Add configurable timezone via `TZ` environment variable with UTC as default fallback.
- [Enhancement] Document the `TZ` configuration option in README.

## 1.0.0 (2025-01-01)
- Initial release.
