# Hookshot changelog

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
