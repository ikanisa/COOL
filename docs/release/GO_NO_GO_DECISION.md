# Collect GO/NO-GO Decision

Audit date: 2026-05-24

Decision: NO-GO for public production launch until the latest Supabase release
verification path is restored, non-exceptionable Auth blockers are closed,
exceptionable platform risks are resolved or validly accepted, and human UAT
signoff is recorded.

## Rationale

The Flutter/Dart 3.44/3.12 gates are green, Android APK/AAB and admin web
release artifacts build, Android emulator smoke UAT passes, and earlier linked
Supabase schema/RLS/advisor/admin UAT evidence was clean. The latest
authoritative release refresh is still NO-GO because this runner cannot reach
the trusted Supabase Postgres path and reports blocker key
`database_connectivity`. That prevents final code-owned readiness, remote Edge
Function endpoint/secret-name checks, and platform controls from being
reconfirmed for release approval.

Earlier successful platform evidence also showed four operator-owned Supabase
project settings that must still be resolved or, where allowed, exceptioned:

- CAPTCHA/bot protection is disabled.
- HIBP leaked-password protection is disabled.
- The Supabase organization is on the Free plan.
- PITR is disabled.
- Human persona UAT signoff is not recorded.

`make supabase-ready-strict` and `make supabase-go-live-gate-json` are the
release approval gates. In the latest evidence bundle
`.cache/supabase_go_live_evidence/20260524T085150Z`, the final gate is NO-GO,
the acceptance matrix is `7` pass / `5` blocked, and `database_connectivity` is
the active blocker. That does not clear the four platform blockers above; it
means the final decision must be refreshed from trusted linked query mode or an
allow-listed runner before any release-owner approval.

## Counts

| Severity | Count |
| --- | ---: |
| P0 | 5 |
| P1 | 2 |
| P2 | 2 |
| P3 | 0 |

## Current Gate Summary

| Command | Result |
| --- | --- |
| `make release-status` | Informational summary: NO-GO while strict Supabase blockers remain; does not print secrets |
| `make release-status-json` | Machine-readable strict release status; does not print secrets. Latest runner refresh reports `database_connectivity`; earlier evidence reports CAPTCHA, HIBP leaked-password protection, Free-plan project-pause risk, and PITR. |
| `/Volumes/PRO-G40/flutter_3_44/bin/flutter --version` | Pass: Flutter `3.44.0`, Dart `3.12.0` |
| `/Volumes/PRO-G40/flutter_3_44/bin/dart --version` | Pass: Dart `3.12.0` |
| `codex mcp list` | Pass: global `dart` MCP enabled with `/Volumes/PRO-G40/flutter_3_44/bin/dart mcp-server --force-roots-fallback` |
| `flutter clean` | Pass |
| `flutter pub get` | Pass |
| `flutter pub outdated` | Pass with dependency drift classified |
| `dart format . --set-exit-if-changed` | Pass |
| `flutter analyze --no-pub` | Pass |
| `flutter test --no-pub --concurrency=1` | Pass: `79` tests |
| `flutter test --no-pub -d emulator-5554 --flavor production integration_test/app_uat_smoke_test.dart` | Pass: `2` integration tests on Pixel 5 API 34 emulator |
| `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build apk --release --flavor production --no-pub` | Pass: `build/app/outputs/flutter-apk/app-production-release.apk`; checksum manifest recorded. |
| `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build appbundle --release --flavor production --no-pub` | Pass: `build/app/outputs/bundle/productionRelease/app-production-release.aab`; checksum manifest recorded. |
| `flutter build web --release -t lib/main_admin.dart --no-wasm-dry-run --no-pub` | Pass: `build/web/main.dart.js` |
| `make supabase-ready` | Earlier pass evidence exists, but latest release refresh is blocked by `database_connectivity`; rerun from a trusted/allow-listed DB path before approval. |
| `make supabase-operational-report` | Pass: read-only cache, table, index, and slow-query report returned |
| `make supabase-edge-auth-uat` | Pass: local Edge Function auth contract UAT passed and is included in the latest evidence bundle. |
| `make supabase-go-live-evidence` | NO-GO: `.cache/supabase_go_live_evidence/20260524T085150Z`, acceptance matrix `7` pass / `5` blocked, blocker key `database_connectivity`. |
| `make supabase-ready-strict` | Blocked on latest runner by `database_connectivity`; earlier strict evidence also failed CAPTCHA/bot protection, HIBP leaked-password protection, organization Free plan, and PITR. |

## Required Next Actions

1. Configure Supabase CAPTCHA/bot protection.
   - Choose hCaptcha or Cloudflare Turnstile.
   - Store provider secret outside the repo and keep the public site key in the release build configuration.
   - Run `AUTH_CAPTCHA_PROVIDER=<provider> AUTH_CAPTCHA_SITE_KEY=<site-key> AUTH_CAPTCHA_SECRET=<secret> make supabase-auth-harden`.
   - Build the Flutter auth client with `AUTH_CAPTCHA_ENABLED=true`, provider, and site key.

2. Enable HIBP leaked-password protection after plan upgrade.
   - Rerun `make supabase-auth-harden` after the organization is on a paid plan.
   - Confirm live Auth config reports `password_hibp_enabled=true`.

3. Decide and configure PITR.
   - If low RPO is required, enable PITR in Supabase project settings and confirm billing/compute implications.
   - The guarded CLI path is `PITR_ADDON_VARIANT=pitr_7 CONFIRM_ENABLE_PITR="$SUPABASE_PROJECT_REF:pitr_7" make supabase-pitr-enable`.
   - If daily backups are accepted, record the recovery objective exception before go-live.

4. Upgrade the Supabase organization plan or document an accepted project-pause risk exception.
   - Live Management API evidence shows organization `EasyMo` is currently on the Free plan.
   - Supabase billing guidance says paid plans prevent project pausing.

5. Restore a trusted release verification path if the runner reports `database_connectivity`.
   - Use linked query mode from a trusted environment, or provide an allow-listed Supavisor pooler/direct database path.
   - Confirm `make release-status-json` no longer reports `database_connectivity`.

6. Rerun release approval.
   - `make supabase-ready-strict`
   - Repeat Flutter format/analyze/test/build gates if any source, dependency, or platform config changes.
   - Complete `docs/release/UAT_SIGNOFF_CHECKLIST_2026-05-24.md`.

## Production Readiness Impact

Public production launch remains NO-GO. The release owner needs a fresh
trusted Supabase verification run with no `database_connectivity` blocker, the
non-exceptionable CAPTCHA/HIBP blockers resolved, any remaining exceptionable
plan/PITR risks validly signed, and human UAT signoff recorded.
