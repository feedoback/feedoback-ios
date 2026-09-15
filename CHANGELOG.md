# Changelog

## 0.1.0 — unreleased

First release.

- The feedback sheet, opened from a control the app already owns, or from an
  optional floating launcher.
- Screenshots with redaction: secure text fields are found on their own, and
  `Feedoback.redact(_:)` marks anything else.
- `identify()` and `setContext()`, with an offline queue that survives a
  relaunch.
- Appearance — the accent, the launcher's word and mark, whether stars are
  asked for — read from the project, so it changes without an app release.
- A privacy manifest declaring the one required-reason API the SDK uses.
