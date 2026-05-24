# Performance Optimization Report

## Changes

- Added derived Riverpod providers for collection summaries, home collection slices, pending payment count, raised total, and per-collection ledger rows.
- Updated home, collections, and ledger screens to watch narrower provider selections instead of rebuilding from the full repository state where avoidable.
- Added admin table/card implementations with compact and wide layouts, stable row rendering, horizontal overflow handling, and tabular figures for operational amounts.
- Kept ledger and payment feeds on safe repository views and existing limits; no raw SMS or parser JSON bulk loading was introduced.
- Changed RWF formatting to accept integer RWF only and added formatting tests.
- Preserved reduced-motion behavior and added a widget test for `MediaQuery.disableAnimations`.

## Boundaries

- No financial allocation, payment execution, SMS ingestion, or Supabase authorization behavior was intentionally changed.
- No floats were introduced for money.
- No broad Dart syntax rewrite was performed.

## Verification

- PASS: `flutter analyze`
- PASS: `flutter test --no-pub --concurrency=1` completed with `62` passing tests.
- PASS: RWF integer formatting tests.
- PASS: reduced-motion widget behavior test.
- PASS: security hygiene tests for production SMS permissions and obvious checked-in secret patterns.
- PASS: security hygiene tests for ignored local env files and placeholder-only Codex environment config.
- PASS: security hygiene tests for Supabase operator scripts using local CLI fallbacks.
- PASS: Release artifact verification includes a refreshed production APK, production AAB, and refreshed admin web `main.dart.js`.
- PASS: Refreshed admin web and Android APK release builds resolve the earlier missing `CupertinoIcons` font warning.
- PASS: `make supabase-ready` code-owned linked readiness checks pass, including migration parity, RLS, Edge Function probes, and linked rollback UAT.
- BLOCKED: `make supabase-ready-strict` fails on Supabase platform settings: CAPTCHA/bot protection and PITR are disabled.
