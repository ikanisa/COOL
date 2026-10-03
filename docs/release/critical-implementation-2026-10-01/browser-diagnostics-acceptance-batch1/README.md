# Immutable browser diagnostic unit acceptance

Dated 2 October 2026. Eleven exact observer, caller, test and Dart diagnostic-contract inputs were copied into a fresh task-owned source tree. The maintained tests ran from that immutable copy. The complete TAP log is retained in `tests.tap`.

All 58 tests passed with zero failures, cancellations, skips or todos. Ten MJS files passed syntax checks. Current source and captured-source hashes match the independent before/after inventories. This supplements the already sealed `browser-diagnostics-batch1` receipt without modifying it.

The tested code catches handled log-level errors, startup timeout and suppression; rejects unknown/malformed/extra/duplicate diagnostic data without raw-text reporting; preserves existing runtime exceptions and console assertions; and binds the actual observer and recorder bytes in all seven QA consumers. Missing/changed observer provenance refuses Public artifact reuse.

The CDP handler tests use synthetic events and the Playwright-compatible listener test uses EventEmitter. No browser socket, app build, render, route capture, provider, hosted write or production acceptance ran. Root owns CI registration and PublicAppMedia Ruby/publisher source closure and receipt enforcement. New actual source-bound browser acceptance remains pending.

CI command: `node --test scripts/tests/collect_diagnostic_observer_test.mjs scripts/tests/public_browser_served_resource_test.mjs`.
