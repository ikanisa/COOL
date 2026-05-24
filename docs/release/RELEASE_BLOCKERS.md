# Collect Release Blockers

Audit date: 2026-05-24

Decision impact: NO-GO while any P0 remains.

## Summary

| Severity | Count |
| --- | ---: |
| P0 | 5 |
| P1 | 2 |
| P2 | 2 |
| P3 | 0 |

## P0 Blockers

| ID | Area | Finding | Evidence | Required action |
| --- | --- | --- | --- | --- |
| P0-001 | Supabase Auth | CAPTCHA/bot protection is disabled. | Latest runner cannot confirm live Auth status because of `database_connectivity`; local `.env` still has no `AUTH_CAPTCHA_SECRET`, `AUTH_CAPTCHA_PROVIDER`, or `AUTH_CAPTCHA_SITE_KEY`, and earlier strict evidence showed CAPTCHA disabled. | Choose hCaptcha or Cloudflare Turnstile, obtain provider site key and secret, run `AUTH_CAPTCHA_PROVIDER=<provider> AUTH_CAPTCHA_SITE_KEY=<site-key> AUTH_CAPTCHA_SECRET=<secret> make supabase-auth-harden`, ship the Flutter auth build with `AUTH_CAPTCHA_ENABLED=true`, provider, and site key, then rerun `make supabase-ready-strict` from a trusted/allow-listed database path. |
| P0-002 | Supabase Auth | HIBP leaked-password protection is disabled. | Latest runner cannot confirm live Auth status because of `database_connectivity`; earlier strict evidence showed `password_hibp_enabled=false`, and the Free plan rejected hardening with HTTP 402. | Upgrade the Supabase organization to a paid plan, rerun `make supabase-auth-harden`, and confirm `password_hibp_enabled=true` from a trusted/allow-listed database path. |
| P0-003 | Supabase backups | PITR is disabled. | Latest runner cannot confirm live backup status because of `database_connectivity`; earlier strict evidence showed PITR disabled and no selected PITR add-on. | Enable PITR if production requires better-than-daily recovery, confirm billing/compute implications, then rerun `make supabase-ready-strict`. Guarded helper: `PITR_ADDON_VARIANT=pitr_7 CONFIRM_ENABLE_PITR="$SUPABASE_PROJECT_REF:pitr_7" make supabase-pitr-enable`. If the business accepts daily backups only, document the signed recovery objective exception after non-exceptionable blockers are resolved. |
| P0-004 | Supabase billing/plan | Organization is on the Free plan. | Latest runner cannot confirm live plan status because of `database_connectivity`; earlier Management API evidence showed organization `EasyMo`, plan `free`. | Upgrade the Supabase organization to a paid production plan, or record an accepted project-pause risk exception after non-exceptionable blockers are resolved. |
| P0-005 | Release verification | Current runner cannot refresh strict Postgres checks. | Latest `make release-status-json` returns blocker key `database_connectivity`; latest `make supabase-go-live-gate-json` exits non-zero with `database_connectivity`. The Supabase tenant allow-list rejected this runner address, so platform controls are `unknown` in that run rather than passed. | Rerun release gates from trusted linked query mode or from an allow-listed Supavisor pooler/direct database path before final approval. |

## P1 Blockers

| ID | Area | Finding | Evidence | Required action |
| --- | --- | --- | --- | --- |
| P1-001 | Android dependency future-proofing | Transitive `shared_preferences_android` still applies Kotlin Gradle Plugin. | APK/AAB builds pass after app-side Built-in Kotlin migration, but Flutter still warns that `shared_preferences_android` applies KGP and may fail in future Flutter versions. | Track/upgrade to a plugin release that supports Built-in Kotlin, or replace the dependency path when available. |
| P1-002 | Human UAT signoff | Full persona UAT still needs release-owner signoff before launch. | Automated linked rollback UAT, admin/security UAT, Android device smoke UAT, APK/AAB builds, and admin web build pass. Human signoff remains pending in `docs/release/UAT_SIGNOFF_CHECKLIST_2026-05-24.md`. | Execute all ten persona walkthroughs against the release environment and record sanitized signoff evidence. |

## P2 Items

| ID | Area | Finding | Evidence | Required action |
| --- | --- | --- | --- | --- |
| P2-001 | Dependency hygiene | Dependency drift remains. | `flutter pub outdated` reports newer Riverpod/go_router major versions and transitive updates. | Review separately from this SDK migration; avoid broad churn in the release branch. |
| P2-002 | Worktree hygiene | The repository contains broad unrelated drift. | `git status --short` shows many unrelated deletions/additions outside the SDK upgrade path. | Review/stage intentionally; do not release from an unreviewed dirty tree. |

## Current Green Evidence

- Flutter SDK: `/Volumes/PRO-G40/flutter_3_44`, Flutter `3.44.0`, Dart `3.12.0`.
- `dart format . --set-exit-if-changed`: pass.
- `flutter analyze --no-pub`: pass.
- `flutter test --no-pub --concurrency=1`: pass, `79` tests.
- `flutter test --no-pub -d emulator-5554 --flavor production integration_test/app_uat_smoke_test.dart`: pass, `2` tests on Pixel 5 API 34 emulator.
- `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build apk --release --flavor production --no-pub`: pass, `build/app/outputs/flutter-apk/app-production-release.apk`.
- `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home /Volumes/PRO-G40/flutter_3_44/bin/flutter build appbundle --release --flavor production --no-pub`: pass, `build/app/outputs/bundle/productionRelease/app-production-release.aab`.
- `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-24.sha256`: SHA-256 manifest for the current APK, AAB, and admin web bundle.
- `flutter build web --release -t lib/main_admin.dart --no-wasm-dry-run --no-pub`: pass, `build/web/main.dart.js`.
- `supabase db lint --linked --schema public --fail-on error`: pass, no schema errors found.
- `make supabase-advisors`: pass, linked security/performance advisors report no error-level findings.
- `make supabase-operational-report`: pass, reports cache hit ratio, table estimates, index usage, and slow-query visibility without printing secrets.
- `scripts/collect_admin_security_uat.sh`: pass through linked rollback UAT for admin RBAC, raw-SMS reveal audit logging, moderation approval, payments-admin allocation, and denial paths.
- `make supabase-ready`: earlier pass evidence exists for code-owned linked readiness; latest release refresh is blocked by `database_connectivity`, so rerun from a trusted/allow-listed database path before approval.
- `make supabase-schema-inventory`: pass, expected public objects `160`, remote public objects `160`, extra `0`, missing `0`, RLS `28/28`, policies `61`, views `9`, functions `57`, pinned function search paths `57/57`.
- `make supabase-go-live-gate`: ready; earlier evidence bundle returns NO-GO while CAPTCHA/HIBP remain non-exceptionable blockers. Latest runner refresh returns NO-GO with `database_connectivity` until the runner is trusted or allow-listed.
- `make supabase-go-live-evidence`: pass, writes a redacted local evidence bundle under `.cache/supabase_go_live_evidence/` with command exit codes, summary JSON, final go-live gate result, and the platform exception-gate result.
- `make supabase-platform-exception-gate`: ready; currently fails while CAPTCHA/HIBP remain strict blockers, and later validates signed exceptions only for Free-plan project-pause risk and PITR/RPO risk.
- `make release-status-json`: earlier evidence reports CAPTCHA, HIBP leaked-password protection, Free-plan project-pause risk, and PITR blockers; latest runner refresh reports `database_connectivity` without printing secrets.
- `make supabase-platform-packet-json`: redacted operator handoff for CAPTCHA, HIBP, Free-plan project-pause risk, and PITR blockers.
- Production Android manifest excludes `READ_SMS` and `RECEIVE_SMS`; restricted SMS permissions are isolated to `internal_receiver`.

## References

- Supabase CAPTCHA protection: https://supabase.com/docs/guides/auth/auth-captcha
- Supabase password security and HIBP protection: https://supabase.com/docs/guides/auth/password-security
- Supabase backups and PITR: https://supabase.com/docs/guides/platform/backups
- Supabase PITR usage and billing: https://supabase.com/docs/guides/platform/manage-your-usage/point-in-time-recovery
- Supabase billing plans: https://supabase.com/docs/guides/platform/billing-on-supabase
