# QA and UAT

The latest detailed report is [go-live QA/UAT readiness report - 2026-05-01](go-live-qa-uat-report-2026-05-01.md). This page is the durable checklist for future releases.

## QA matrix

| Category | Required evidence |
| --- | --- |
| Build verification | Admin, website, PWA stub, Flutter analyze, mobile release metadata. |
| Static analysis | TypeScript, Deno lint/check, Flutter analyze. |
| Unit/widget tests | Flutter critical flows, admin scripts, Edge Function unit tests. |
| Integration tests | Flutter integration smoke, admin browser/search smoke, Supabase SQL contracts. |
| Security tests | RLS, role boundaries, cross-tenant denial, payment status transitions, Edge auth. |
| Accessibility | Critical mobile screens, admin forms/tables, keyboard navigation, contrast. |
| Device UAT | Android/iOS app install, login, SMS permission, camera, push, deep links, payment guidance. |
| Production smoke | Scoped UAT accounts only, backup confirmed, cleanup owner assigned. |
| Rollback | Previous web artifact, feature disable path, migration recovery plan, mobile rollout halt. |

## Core commands

```bash
make verify-structure
npm --prefix apps/admin run lint
npm --prefix apps/admin run test:data-table-controller
npm --prefix apps/admin run test:surface-registry
npm --prefix apps/admin run test:ui-safety
npm --prefix apps/admin run build:ci
npm --prefix apps/admin run smoke:admin-browser
npm --prefix apps/admin run smoke:admin-search
npm --prefix apps/website run build
make pwa-check
bash scripts/migrations/validate_supabase_migrations.sh
supabase db lint --workdir supabase --local --schema public --fail-on error
deno lint --rules-exclude=no-unversioned-import,require-await supabase/functions/**/*.ts
deno check $(find supabase/functions -type f -name '*.ts' | sort)
deno test --allow-env=SUPABASE_SERVICE_ROLE_KEY,AUTH_PHONE_PASSWORD_SECRET,OTP_CODE_HASH_SECRET,OTP_TEST_PHONE,OTP_TEST_CODE,GOOGLE_SERVICE_ACCOUNT_EMAIL,GOOGLE_PRIVATE_KEY,AI_AUDIT_SHEET_ID $(find supabase/functions -type f -name '*_test.ts' | sort)
scripts/dev/flutterw analyze --fatal-infos
scripts/dev/flutterw test --concurrency=4 test/integration_smoke
bash scripts/qa/verify_release_metadata.sh
```

## Production-safe UAT evidence

Every UAT journey must capture:

- Tester and role.
- Account id or test alias.
- Device/browser and app build.
- Tenant/group/payment/campaign fixture id.
- Timestamp.
- Expected result and actual result.
- Evidence link or screenshot/video reference.
- Cleanup status.

## Critical journeys

- Anonymous user browses and is blocked from restricted actions.
- User logs in and sees only their scoped data.
- Admin logs in and sees admin surfaces backed by backend permissions.
- Manager/bank admin cannot see another tenant/group/custodian scope.
- Group/savings contribution and statement flow handles loading, empty, error, and success states.
- Payment instruction is generated without marking paid.
- Manual payment confirmation requires authorized actor and writes audit log.
- Campaign approval/send respects consent, approval, and audit rules.
- Unauthorized user receives backend denial, not only UI hiding.
- Cross-tenant data is not visible through direct API/RPC attempts.

## Blocked categories to resolve before broad launch

- pgTAP/RLS execution against a real database when local Supabase is unavailable.
- Connected-device Android/iOS UAT for platform permissions and release builds.
- Agent workflow UAT until a production agent runtime exists.
- Production rollback rehearsal in a controlled, non-destructive window.
