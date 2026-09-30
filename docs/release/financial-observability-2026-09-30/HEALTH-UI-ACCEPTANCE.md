# Operational health — current local implementation

The Admin health page now uses the installed migration 148 contract. It validates
all 19 top-level fields, 31 measurements, 13 alert rules, the 60-second expiry and
the three evidence limitations before rendering. Metadata and counts require
integers; missing measurements remain missing. Unknown, expired and malformed
samples cannot become healthy by default. Expired samples hide measurements,
alerts and the old scheduler state. Refresh is explicit; the expiry timer does
not fetch or retry a request.

The page uses Collect's shared card, section, status and button components under
the owner-selected Revolut skill. It preserves receipt, payment and notification
terminology. The operator layout is a supported product adaptation; this packet
does not establish complete visual parity with an authenticated source product.

## Actual evidence

- `../admin-full-coverage-2026-09-30/sql-reads148-attempt3/result.json`
  records 15 actual read receipts on the installed 148-migration fixture, including
  an approved synthetic operator, a group, posted payment and suppressed SMS.
  The health test fixture equals that actual SQL receipt. All 146 table
  fingerprints, catalog controls and cron records were restored after rollback.
- `../admin-full-coverage-2026-09-30/sql-reads148-attempt4-extended/result.json`
  adds actual queue SLA and WhatsApp approval reads: 17 receipts and the same
  complete rollback equivalence.
- `health-ui-attempt2/validation.json` records 39 passing contract/widget tests
  and two clean analyzer inputs using Flutter 3.44.4. It binds the owned health
  code/test/fixture, all library sources, both local fork runtimes, package
  declarations and the package binding unchanged at capture.
- The tests reject decimal/string/negative/unsafe counts, false aliases,
  normalized invalid calendar dates, missing/duplicate alerts, weakened
  thresholds and injected diagnostic text. They verify unknown versus zero,
  the inclusive backlog threshold, expiry and clock skew, no timer fetch,
  explicit refresh, disposal, compact 320x568 at 1x/2x text, semantics and actual
  keyboard activation.

The first health packet is retained. Its 37 passing tests and clean analyzer
were followed by two test-harness failures: semantics handles were disposed
after the framework's end-of-test check. Disposal was corrected and all 39
tests passed in the fresh second packet. Earlier SQL fixture failures are also
retained with authoritative post-failure restoration checks.

## Other local observability evidence

Migration 148 was installed with ordinary owner privileges. The installed SQL
suite passes 36 assertions and restores all 146 tables/catalog/cron records.
The current receipt telemetry integration has 76 actual loopback HTTP checks
and 309 Edge unit tests against the frozen Deno 2.5.6 dependency lock. Telemetry
accepts fixed event codes and bounded duration only, times out within its
bounded budget, and never changes a durable receipt outcome.

These are local, generated-fixture and handler results. They do not prove
provider delivery, device receipt, configured unattended hosting or complete
final-source browser/native acceptance. L19 remains open for its remaining
concurrency/performance, response-procedure and final integration coverage.
