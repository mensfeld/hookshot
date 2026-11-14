# Hookshot changelog

## 1.6.0 (Unreleased)
- [Feature] Per-endpoint signature verification of inbound webhooks through pluggable providers. Hookshot ships the GitHub provider (`X-Hub-Signature-256`); others subclass `VerificationProviders::Base` and are registered with `VerificationProviders.register` in an initializer. Several secrets can be set at once to rotate one without downtime; spaces around each secret are ignored. A missing or wrong signature answers 401 and is neither stored nor forwarded; the endpoint pages count rejected requests. An endpoint whose provider is no longer registered rejects every request. Endpoints without a provider accept every request as before. Run `bin/rails db:migrate`.
- [Feature] MCP tools to configure signature verification: `list_verification_providers` lists the registered providers, `set_endpoint_verification` sets an endpoint's provider and secrets or turns verification off, and `list_endpoints` shows each endpoint's provider, number of secrets and rejected requests. The tools never return the secrets.

## 1.5.0 (2026-11-09)
- [Feature] Endpoints: named inbound URLs (`POST /webhooks/receive/:slug`) that forward only to the targets attached to them, so one sender can route actions with identical payloads by posting to different URLs. Targets and endpoints are many-to-many and target filters still apply. The endpoint comes from the URL path only, never from the request body or query string.
- [Feature] Admin pages to create, edit, deactivate and delete endpoints, showing each receive URL with a copy button, its targets and recent activity.
- [Feature] The target form selects which endpoints a target receives from; new targets start on the default endpoint, and targets without endpoints are flagged.
- [Feature] MCP server at `/mcp` (Streamable HTTP, behind the admin HTTP Basic Auth) with tools to list endpoints, targets, webhooks and dispatches, show a webhook, activate or deactivate a target, replay a webhook and retry a dispatch.
- [Enhancement] Webhooks record the endpoint that received them, can be filtered by it, and replay to that endpoint's current targets.
- [Enhancement] Unknown or inactive endpoints answer 404 and store nothing.
- [Maintenance] Migration creates a `default` endpoint for the existing `/webhooks/receive` URL and attaches every existing target and webhook to it, so routing is unchanged after upgrading. Run `bin/rails db:migrate`.
- [Enhancement] Warn when a "Matches (wildcard)" filter's value looks like a regular expression (`\`, `|`, `.*`, `(?`, a leading `^` or trailing `$`, `[a-z]` ranges or `{n}` quantifiers). Wildcard matching treats everything except `*` literally, so such a filter never matches what was meant. The target form shows the warning live under the filter, and the target page marks the filter with a "looks like a regex" badge.
- [Change] Targets that are not attached to the receiving endpoint no longer get a delivery record at all (previously they got a `filtered` one when their filters rejected the webhook).
- [Change] Received bodies are stored and relayed to targets byte for byte, also when they are not valid UTF-8 (gzip, Latin-1, any binary). Previously invalid bytes were replaced before storage, so targets got different bytes and failed body signature (HMAC) checks. The admin webhook page shows such a body with invalid bytes replaced and a note. Run `bin/rails db:migrate` (the `webhooks.payload` column becomes binary); bodies stored before the upgrade keep their replaced bytes.
- [Change] `RETENTION_DAYS`, `MAX_PAYLOAD_SIZE` and `JOB_CONCURRENCY` must be positive integers written with digits only (underscores allowed, as in `1_000_000`) and are checked at boot: any other value (empty, `0`, negative, a `+` sign, surrounding whitespace, decimals, non-numeric or unit-suffixed such as `10MB`) now stops Hookshot from starting with an error naming the variable. Previously they were accepted: an empty, `0`, negative or non-numeric value deleted every webhook at the next cleanup, rejected every request body, or stopped all deliveries, and `10MB` was read as 10 days or 10 bytes.
- [Fix] A delivery that fails all 5 ActiveJob attempts moves to the recurring retry phase instead of raising `NameError` and stopping after 5 attempts; it is then retried 1 h, 2 h, 4 h, 8 h and 24 h apart, one attempt each, and given up after attempt 10.
- [Fix] Client errors (4xx) and deleted deliveries are no longer retried, in the ActiveJob or the recurring retry phase.
- [Fix] Webhooks with a malformed form or multipart body (bad percent-escapes, too deeply nested parameters, a broken multipart boundary) or a malformed query string on the receive URL are stored unchanged and answered 200 instead of being rejected with 400.
- [Fix] JSON bodies that are not valid UTF-8 (a Latin-1 value such as `{"name":"Jos\xE9"}`, or an invalid UTF-8 key) are stored unchanged and answered 200 instead of being rejected with 400 or 500. The receive controller no longer parses the body or query string, so the request log `Parameters:` line for the receive URL lists only the path parameters, not the body or query parameters.
- [Enhancement] The daily cleanup deletes old webhooks and their deliveries in batches of 500, each in a short transaction with a brief pause between batches, instead of one record at a time. Incoming webhooks no longer wait on the SQLite write lock while a large cleanup runs.
- [Enhancement] The receive URL answers after storing the webhook and enqueuing one routing job, instead of creating every target's delivery and dispatch job inside the request. Each received webhook used to take several separate SQLite writes while the sender waited, so a burst (hundreds of GitHub events a minute from busy CI) queued requests on the database write lock until some senders hit their 10 second timeout. The routing job runs ahead of the dispatch jobs, skips targets that already have a delivery of the webhook when it is retried, and retries up to 10 times. A webhook's deliveries now appear a moment after it is received rather than with it. Replays from the admin and MCP still route immediately.
- [Fix] Deleting a target that has deliveries failed with a 500 (`NOT NULL constraint failed: deliveries.target_id`); only targets that had never received anything could be deleted. Its deliveries are now kept as history, shown as "Deleted Target", can no longer be retried, and lose their scheduled retries; a delivery still queued when its target is deleted is marked failed with "Target was deleted" instead of being sent. Run `bin/rails db:migrate` (`deliveries.target_id` becomes nullable; SQLite rebuilds the `deliveries` table, which takes a moment on a large database).

## 1.4.0 (2026-10-09)
- [Feature] Bulk retry on the Dispatches page: select retryable rows (with a select-all checkbox and shift-click range selection) and use "Retry selected".
- [Feature] "Retry all matching" queues every retryable dispatch for the current status and target filters across all pages (up to 1000 per click, reporting how many remain).
- [Enhancement] Manual retries claim the delivery atomically, so double clicks or overlapping bulk retries queue each delivery only once.
- [Maintenance] README retry section now reflects the 10-attempt schedule and manual retry options.

## 1.3.0 (2026-10-02)
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
