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
- PASS: `flutter test --no-pub --concurrency=1 --coverage` completed with 408
  passing tests and 77.74% line coverage (9,219 of 11,858 lines).
- PASS: RWF integer formatting tests.
- PASS: reduced-motion widget behavior test.
- PASS: security hygiene tests for production SMS permissions and obvious checked-in secret patterns.
- PASS: security hygiene tests for ignored local env files and placeholder-only Codex environment config.
- PASS: security hygiene tests for Supabase operator scripts using local CLI fallbacks.
- PASS: Release artifact verification includes a refreshed production APK, production AAB, and refreshed admin web `main.dart.js`.
- PASS: The unused platform-icon dependency and font were removed; clean
  Admin web and Android release builds package only Inter plus the tree-shaken
  Material semantic-icon font.
- PASS: Dense Groups and Activity panels disable viewport-spanning backdrop
  blur beyond eight rows and isolate dense content from surrounding repaint
  work. The amount field disables blur while focused, and typing no longer
  rebuilds the complete contribution screen.
- PASS: The Flutter frame recorder now distinguishes missed frames (UI build or
  raster duration over 16.667 ms) from `totalSpan` latency, matching the bundled
  Flutter scheduler contract. The v2 target marker rejects stale AOT output.
- PASS: Two accepted API 36 controlled-emulator runs cover startup, dense
  Groups, route transition, dense Activity, sheet open/close, and amount entry.
  The repeat recorded 0/154 Groups, 0/191 Activity, and 1/45 amount-entry
  UI-or-raster budget misses; p90 raster durations were 2.285 ms, 2.642 ms, and
  6.052 ms respectively.
- PASS: `make supabase-ready` code-owned linked readiness checks pass, including migration parity, RLS, Edge Function probes, and linked rollback UAT.
- BLOCKED: Physical-device repetition, long-session thermal testing, authorized
  crash/ANR reporting, and assistive-technology performance remain external
  release evidence.
- BLOCKED: `make supabase-ready-strict` fails on Supabase platform settings: CAPTCHA/bot protection and PITR are disabled.
