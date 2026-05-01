# Go-Live QA/UAT Readiness Report - 2026-05-01

## Verdict

Recommended launch decision: **No-Go for production launch**.

Release readiness score: **76/100**.

The code-level local gates are largely healthy after this pass, but production
promotion is blocked by release-operation issues:

- The project is intentionally production-only. This is supported, but UAT must
  be production-safe: backup first, use scoped test accounts, avoid destructive
  broad writes, and require explicit operator approval for any live mutation.
- Supabase credentials exposed outside the operator shell must be rotated before
  linked linting, migration apply, or deployment.
- Local Supabase Postgres is not running, so local `supabase db lint` and pgTAP
  execution could not run.
- Full mobile release builds and connected-device UAT were not executed in this
  environment.

## QA Matrix

| Category | Command / Evidence | Status | Notes |
| --- | --- | --- | --- |
| Build verification - admin web | `npm --prefix apps/admin run build:ci` | Pass | Vite build passed; bundle budget passed at 1071.76 KB total. |
| Build verification - website | `npm --prefix apps/website run build` | Pass | Static site built successfully. |
| Build verification - PWA | `make pwa-check` | Pass | PWA is intentionally retired/fail-closed as a Cloudflare Pages stub. |
| Build verification - Android/iOS | `COOL_PRODUCTION_ONLY_RELEASE=1 scripts/qa/verify_android_flavors.sh`, `COOL_PRODUCTION_ONLY_RELEASE=1 scripts/qa/verify_ios_flavors.sh` | Blocked | Requires valid production release secrets and device/build environment. Staging flavor is skipped in production-only mode. |
| Lint/static - admin web | `npm --prefix apps/admin run lint` | Pass | TypeScript check passed. |
| Lint/static - Flutter | `scripts/dev/flutterw analyze --fatal-infos` | Pass | Added analyzer excludes for vendored `flutter_contacts`; app code passes. |
| Lint/static - Edge Functions | `deno lint --rules-exclude=no-unversioned-import,require-await supabase/functions/**/*.ts` | Pass | Fixed ten lint findings before rerun. |
| Unit/widget - Flutter critical pack | Curated `flutter test --concurrency=1 ...` | Pass | 57 tests passed across security docs, RLS contracts, auth, admin roles, audit log, groups, BioPay, and MoMo SMS. |
| Unit/widget - full Flutter suite | `flutter test --concurrency=4 --exclude-tags=integration` | Blocked | Toolchain/volume instability: VM segfault on first run, SDK read errors after interruption. Isolated affected tests passed. |
| Integration smoke - Flutter host | `flutter test --concurrency=4 test/integration_smoke` | Pass | App boot, deep link, and MoMo route smoke passed. |
| Web component/safety tests | Admin data table, surface registry, UI safety scripts | Pass | 2 + 3 + 2 Deno tests passed. |
| Web browser smoke | `npm --prefix apps/admin run smoke:admin-browser` | Pass | Core admin page headings/search controls passed. |
| Admin search smoke | `npm --prefix apps/admin run smoke:admin-search` | Pass after fix | Fixed env loading and unsupported embedded `or()` filters. |
| Supabase migration validation | `bash scripts/migrations/validate_supabase_migrations.sh` | Pass | 191 migrations validated. |
| Supabase db lint | `supabase db lint --local --schema public --fail-on error` | Blocked | Local Postgres refused connection on `127.0.0.1:54322`. |
| RLS/permission tests | Static Flutter tests + pgTAP SQL files | Partial | Static tests pass; pgTAP SQL not executed because DB unavailable. |
| Edge Function tests | `deno test --allow-env=... $(find supabase/functions -name '*_test.ts')` | Pass | 86 tests passed. |
| Edge Function type check | `deno check $(find supabase/functions -name '*.ts')` | Pass | 70 files checked. |
| Payment safety | Static tests + Edge reconciliation tests | Pass local | Payment instruction vs confirmation boundaries covered locally; live UAT still required. |
| Agent workflow tests | Repo inventory | Blocked | Agent folders are docs/contracts only; no production agent runtime exists to execute. |
| Channel adapter tests | Edge tests and docs | Partial | Google Workspace fail-closed tests pass; WhatsApp/real outbound channel UAT not executed. |
| Accessibility | Existing targeted Flutter tests not fully rerun | Partial | Critical accessibility regression pack should run on stable Flutter/toolchain before launch. |
| Performance/bundle | Admin bundle budget | Pass web / Blocked mobile | Admin bundle passes; mobile performance/device profiling not executed. |
| Release rollback | Docs/scripts review | Partial | Release scripts exist; rollback rehearsal must be a production-safe backup/restore and redeploy drill. |
| Backend config contract | `COOL_PRODUCTION_ONLY_RELEASE=1 bash scripts/qa/validate_backend_config.sh` | Pass in production-only mode | Staging/project separation is intentionally skipped only when `COOL_PRODUCTION_ONLY_RELEASE=1` is set. |
| Release metadata | `bash scripts/qa/verify_release_metadata.sh` | Pass | Android metadata present; iOS release metadata explicitly de-scoped. |

## UAT Checklist

Run this checklist against production only after credentials are rotated and a
fresh backup/restore point is confirmed. Each item needs tester, role,
device/browser, evidence link, result, defect id, and cleanup status.

| Journey | Required Result | Status |
| --- | --- | --- |
| New user opens app | App leaves splash, creates/recovers session, shows usable home state. | Automated host smoke passed; device UAT pending. |
| Anonymous user browses | Public routes/content visible; restricted actions prompt auth. | Pending manual. |
| User becomes role-specific actor | Role assignment changes route/menu access only after backend role is present. | Pending production-safe UAT. |
| Admin logs in | Admin sees admin workspace, users, health, settings, audit routes. | Browser smoke passed; live auth UAT pending. |
| Manager/bank admin logs in | Manager sees only scoped groups/reviews and cannot access other tenant scope. | Pending RLS pgTAP + UAT. |
| Savings/group action | Create group, invite, contribute, statements, empty/error states. | Flutter group journey pack passed locally; live UAT pending. |
| Order/booking/prediction/trip action | Route either works with backend state or is explicitly non-production. | Not present as active separate surfaces; pending product scope confirmation. |
| External payment instruction generated | Instruction status remains distinct from paid/fulfilled. | Local payment tests pass; live UAT pending. |
| Manual payment marked | Only authorized actor can mark; audit log records actor/source/status. | Local tests pass; pgTAP/live UAT pending. |
| Agent receives public message | Public message is routed without privileged tool access. | Blocked: no production agent runtime in repo. |
| Agent receives manager/admin message | Agent identity, permission, and audit context are enforced. | Blocked: no production agent runtime in repo. |
| Agent uses privileged tool | Tool call requires backend permission and audit log. | Blocked: no production agent runtime in repo. |
| Admin approves campaign/action | Approval requires admin role and creates audit record. | Local contract tests pass; live UAT pending. |
| Audit log records sensitive action | Audit screen/search shows actor/action/target details. | Widget test passed; live UAT pending. |
| Unauthorized user is blocked | Backend denies direct API/RPC/table access, not just UI. | Static/RLS contract partial; pgTAP pending. |
| Cross-tenant data is not visible | Tenant A cannot read Tenant B groups/payments/reviews. | pgTAP pending. |
| Backend failure handling | UI shows retryable error/empty states without leaking internals. | Covered in selected widgets/functions; device/browser UAT pending. |

## Test Account Plan

Create clearly labeled production UAT accounts. Do not reuse real customer
identities. Each account must have a cleanup owner and all financial/payment
actions must use tiny controlled amounts or dry-run/manual-review paths.

| Account | Purpose | Required Setup |
| --- | --- | --- |
| `uat_anon_device` | Anonymous browse/session | Fresh install or cleared app data. |
| `uat_user_a` | Standard user Tenant A | Verified phone, no admin roles. |
| `uat_user_b` | Cross-tenant negative user Tenant B | Verified phone, member of separate group. |
| `uat_group_owner_a` | Group/savings owner | Owns Tenant A group with one pending contribution. |
| `uat_group_member_a` | Group member | Member, not owner/admin. |
| `uat_bank_admin_a` | Scoped manager/admin | Active bank/group admin role scoped to Tenant A only. |
| `uat_platform_admin` | Platform admin | Can manage users, config, campaigns, audit. |
| `uat_auditor` | Read-only audit review | Read-only audit/report access, no writes. |
| `uat_campaign_approver` | Sensitive campaign approval | Permission to approve notification campaigns. |
| `uat_blocked_user` | Negative authorization | Suspended/no roles. |

## Test Data Plan

- Two isolated production UAT tenants/groups with names prefixed `UAT_DO_NOT_USE`
  to catch accidental broad searches or joins.
- Pending, instructed, manually confirmed, fulfilled, disputed, refunded, and
  cancelled payment records where schema supports them.
- One approved, one pending, one expired, and one revoked notification campaign.
- MoMo SMS samples for exact match, ambiguous match, unknown sender, duplicate,
  missing amount, and manual-review routing.
- Audit log fixtures for role assignment, manual allocation, campaign approval,
  config update, and denied sensitive action.
- File/OCR samples: valid JPEG/PNG/PDF under 5 MiB, invalid MIME, malformed
  base64, oversized payload.
- Browser/device matrix: Chrome desktop, Safari desktop, Android Chrome,
  Android app production build with UAT accounts, iOS Safari if iOS remains
  web-only.

## Bugs Found And Fixes Implemented

| Bug | Impact | Fix |
| --- | --- | --- |
| Admin search smoke did not load app/root env files. | Local/CI smoke failed unless shell manually exported Supabase vars. | `apps/admin/scripts/smoke-admin-search.mjs` now loads root/app `.env` without overriding process env. |
| Admin search smoke used unsupported embedded PostgREST `or()` filters. | Smoke failed against real Supabase with logic-tree parse errors. | Smoke now filters on base-table searchable columns while still selecting embedded relation data. |
| Edge Function Deno lint findings. | Release lint gate failed on unused helpers/imports/params, unused variable, and loose `any`. | Cleaned affected tests/functions and typed Google Workspace metadata as `unknown`. |
| Flutter analyzer included vendored `flutter_contacts`. | App-level strict lints failed on third-party vendored source. | Excluded `apps/mobile/third_party/**` and `third_party/**` in `analysis_options.yaml`. |

## Commands Run

Passed:

```bash
bash scripts/migrations/validate_supabase_migrations.sh
npm --prefix apps/admin run lint
npm --prefix apps/admin run test:data-table-controller
npm --prefix apps/admin run test:surface-registry
npm --prefix apps/admin run test:ui-safety
npm --prefix apps/admin run build:ci
npm --prefix apps/admin run smoke:admin-browser
npm --prefix apps/admin run smoke:admin-search
npm --prefix apps/website run build
make pwa-check
deno lint --rules-exclude=no-unversioned-import,require-await supabase/functions/**/*.ts
deno check $(find supabase/functions -type f -name '*.ts' | sort)
deno test --allow-env=SUPABASE_SERVICE_ROLE_KEY,AUTH_PHONE_PASSWORD_SECRET,OTP_CODE_HASH_SECRET,OTP_TEST_PHONE,OTP_TEST_CODE,GOOGLE_SERVICE_ACCOUNT_EMAIL,GOOGLE_PRIVATE_KEY,AI_AUDIT_SHEET_ID $(find supabase/functions -type f -name '*_test.ts' | sort)
scripts/dev/flutterw analyze --fatal-infos
scripts/dev/flutterw test --concurrency=4 test/integration_smoke
scripts/dev/flutterw test test/core/fcm_service_test.dart
scripts/dev/flutterw test test/core/quick_action_navigation_test.dart
scripts/dev/flutterw test --concurrency=1 test/docs/security_privacy_hardening_test.dart test/docs/rls_payment_status_contract_test.dart test/docs/migration_manifest_test.dart test/core/config/env_config_test.dart test/core/router/app_redirects_test.dart test/features/auth/auth_repository_test.dart test/features/admin/manage_admin_roles_screen_test.dart test/features/admin/audit_log_screen_test.dart test/features/groups/group_journeys_test.dart test/features/biopay/biopay_home_screen_test.dart test/features/momo/momo_sms_autoread_service_test.dart
bash scripts/qa/verify_release_metadata.sh
git diff --check
```

Failed or blocked:

```bash
supabase db lint --local --schema public --fail-on error
scripts/dev/flutterw test --concurrency=4 --exclude-tags=integration
```

## Release Blockers

1. **P0: Rotate exposed Supabase credentials before linked operations.** Do not
   run `supabase db lint --linked`, `supabase db push --linked`, deployments, or
   production smoke tests until rotation is complete.
2. **P0: Production-only UAT needs a confirmed backup/restore point before any
   live mutation.** No staging exists, so all UAT writes must use scoped
   `UAT_DO_NOT_USE` accounts/data and documented cleanup.
3. **P1: Execute pgTAP/RLS tests against a running local or production database.**
   Static coverage exists, but live policy evaluation is still required.
4. **P1: Run full Android build and connected-device UAT.** Host tests are not a
   replacement for SMS permission, camera, App Check, push, deep links, and
   payment-instruction device behavior.
5. **P1: Rehearse rollback in production-safe mode.** Verify backup restore
   readiness, migration rollback notes, feature-flag disablement, and previous
   build redeploy before launch.

## Post-Launch Monitoring Checklist

- Supabase auth error rate, Edge Function 4xx/5xx rates, and p95 latency.
- OTP send/verify conversion, abuse/rate-limit events, and App Check rejects.
- MoMo SMS parse/reconciliation success, manual-review backlog, duplicate rate.
- Payment intent status transitions by source and manual confirmation audit.
- Admin audit volume for role, config, campaign, and payment actions.
- Notification send success, opt-out skips, campaign approval linkage.
- Crashlytics fatal/non-fatal trend by app version/flavor.
- Web Core Web Vitals for admin and website, plus admin bundle growth.
- Cross-tenant/RLS denied-access telemetry and suspicious repeated denials.
- Support queue volume for onboarding, payment, SMS permission, and BioPay.
