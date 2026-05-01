# Go-live Checklist

This checklist is for a production-only deployment model. There is currently no staging project, so the release process must be conservative, evidence-driven, and easy to stop.

## Preflight

- Confirm launch owner, database operator, mobile release owner, web release owner, and incident lead.
- Confirm a fresh production backup or restore point before migrations or live UAT writes.
- Confirm all environment values live in CI secrets, Supabase secrets, platform configs, or operator shell only.
- Confirm `COOL_PRODUCTION_ONLY_RELEASE=1` is set only for production-only release checks.
- Review [QA/UAT](../testing/qa-uat.md) and the latest [go-live QA report](../testing/go-live-qa-uat-report-2026-05-01.md).
- Review [rollback](rollback.md) and assign a rollback operator.

## Code and docs gates

```bash
git status --short
make verify-structure
npm --prefix apps/admin run build:ci
npm --prefix apps/website run build
make pwa-check
bash scripts/migrations/validate_supabase_migrations.sh
deno lint --rules-exclude=no-unversioned-import,require-await supabase/functions/**/*.ts
deno check $(find supabase/functions -type f -name '*.ts' | sort)
deno test --allow-env=SUPABASE_SERVICE_ROLE_KEY,AUTH_PHONE_PASSWORD_SECRET,OTP_CODE_HASH_SECRET,OTP_TEST_PHONE,OTP_TEST_CODE,GOOGLE_SERVICE_ACCOUNT_EMAIL,GOOGLE_PRIVATE_KEY,AI_AUDIT_SHEET_ID $(find supabase/functions -type f -name '*_test.ts' | sort)
scripts/dev/flutterw analyze --fatal-infos
scripts/dev/flutterw test --concurrency=4 test/integration_smoke
bash scripts/qa/verify_release_metadata.sh
```

## Database gates

```bash
bash scripts/migrations/validate_supabase_migrations.sh
supabase db lint --workdir supabase --local --schema public --fail-on error
# Run pgTAP/RLS tests in supabase/tests when DB is available.
```

If local Supabase is unavailable, record it as a release risk and run the RLS SQL tests during an approved database window before broad launch.

## Production-safe UAT gates

- Use UAT accounts and `UAT_DO_NOT_USE` data only.
- Capture tester, role, browser/device, timestamp, evidence, result, defect id, and cleanup status.
- Test anonymous browse, login, role-based access, group/savings flow, MoMo evidence, payment instruction, manual confirmation, campaign approval, audit log, unauthorized access denial, and cross-tenant isolation.
- Do not run broad destructive tests in production. Use narrow fixtures and reversible changes.

## Deploy sequence

1. Freeze unrelated changes.
2. Confirm backup/restore point.
3. Run code and database gates.
4. Apply migrations from a secured operator shell using documented scripts.
5. Deploy Edge Functions.
6. Deploy admin and website.
7. Build and submit mobile release or continue phased rollout.
8. Run production smoke/UAT checklist with scoped accounts.
9. Monitor errors, audit logs, payment transitions, OTP, MoMo SMS parsing, and support channels.

## Launch blockers

- RLS or cross-tenant tests fail or cannot be executed before launch approval.
- Payment status transition can be changed by an unauthorized actor.
- Manual confirmation lacks audit fields.
- Edge Functions fail auth, validation, or type checks.
- Admin UI exposes destructive or sensitive action without backend enforcement.
- Mobile release build or connected-device UAT fails for SMS, camera, App Check, push, auth, or payment guidance.
- Backup/rollback owner or restore point is missing.
