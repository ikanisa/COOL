# Production-Only UAT Runbook - 2026-05-01

Use this runbook when COOL has no staging Supabase project and QA must validate
against production.

## Preconditions

Do not start production-only UAT until all items are true:

- Exposed Supabase credentials have been rotated.
- A fresh production backup/restore point is confirmed.
- The operator shell has the intended production env only.
- Test accounts and test groups are prefixed `UAT_DO_NOT_USE`.
- Payment tests use tiny controlled amounts, dry-run paths, or manual-review
  flows. Never infer payment from instructions.
- One release manager owns the start/stop decision and cleanup sign-off.

## Production-Only Command Prefix

Set this flag for all release validation commands:

```bash
export COOL_PRODUCTION_ONLY_RELEASE=1
```

This intentionally skips staging/project-separation checks while keeping
production config validation active.

## Required Gates

```bash
COOL_PRODUCTION_ONLY_RELEASE=1 bash scripts/qa/validate_backend_config.sh
bash scripts/migrations/validate_supabase_migrations.sh
scripts/dev/flutterw analyze --fatal-infos
npm --prefix apps/admin run lint
npm --prefix apps/admin run build:ci
npm --prefix apps/admin run smoke:admin-browser
npm --prefix apps/admin run smoke:admin-search
npm --prefix apps/website run build
deno lint --rules-exclude=no-unversioned-import,require-await supabase/functions/**/*.ts
deno check $(find supabase/functions -type f -name '*.ts' | sort)
deno test --allow-env=SUPABASE_SERVICE_ROLE_KEY,AUTH_PHONE_PASSWORD_SECRET,OTP_CODE_HASH_SECRET,OTP_TEST_PHONE,OTP_TEST_CODE,GOOGLE_SERVICE_ACCOUNT_EMAIL,GOOGLE_PRIVATE_KEY,AI_AUDIT_SHEET_ID $(find supabase/functions -type f -name '*_test.ts' | sort)
```

After credential rotation, run linked production checks from the secured
operator shell:

```bash
supabase db lint --linked --schema public --fail-on error
```

Only apply migrations after backup confirmation and release manager approval:

```bash
RUN_MIGRATION_APPLY=1 COOL_PRODUCTION_ONLY_RELEASE=1 bash scripts/qa/release_readiness.sh
```

## Production UAT Data Rules

- Use only UAT users, UAT groups, UAT payment intents, and UAT campaign records.
- Prefix operator-created records with `UAT_DO_NOT_USE`.
- Record every UAT write in the release log with actor, time, record ids, and
  cleanup status.
- Do not run broad cleanup SQL. Delete or close only known UAT records by id.
- Preserve audit logs; do not delete audit evidence.

## Rollback Drill

Before launch approval:

- Confirm latest backup timestamp and restore path.
- Confirm previous mobile/web build artifacts are available.
- Confirm Edge Function redeploy command for the previous version.
- Confirm feature/config toggles needed to disable risky flows.
- Confirm a named operator can execute the rollback within the target RTO.

## Exit Criteria

Production-only UAT can pass only when:

- All required gates pass.
- pgTAP/RLS checks pass against a real database.
- Connected-device Android UAT passes for auth, SMS permission, BioPay/camera,
  deep links, push, and payment guidance.
- Admin permission, manual payment, campaign approval, and audit-log UAT pass.
- UAT records are cleaned up or intentionally retained with labels.
