# Production Documentation

This directory is the operating index for the Cool platform. A senior developer should be able to read this page plus the linked canonical docs in under one hour and understand the deployable surfaces, backend boundaries, security model, release gates, and known launch risks.

## One-hour reading path

1. [Architecture overview](architecture/overview.md) - system map, source of truth, and production-only constraints.
2. [Apps](architecture/apps.md) - buildable app surfaces, commands, and app ownership.
3. [Backend](architecture/backend.md) - Supabase schema, migrations, Edge Functions, and verification commands.
4. [Permissions and RLS](security/permissions-rls.md) - role boundaries and tenant isolation rules.
5. [Audit logs](security/audit-logs.md) - required audit trails for sensitive actions.
6. [QA/UAT](testing/qa-uat.md) - production-safe test matrix and evidence expectations.
7. [Go-live checklist](release/go-live-checklist.md) - final release gates and command sequence.
8. [Rollback](release/rollback.md) - production-only rollback and recovery procedures.

## Canonical docs

- [Architecture overview](architecture/overview.md)
- [Apps](architecture/apps.md)
- [Backend](architecture/backend.md)
- [Agents](architecture/agents.md)
- [Permissions and RLS](security/permissions-rls.md)
- [Audit logs](security/audit-logs.md)
- [Go-live checklist](release/go-live-checklist.md)
- [Rollback](release/rollback.md)
- [Admin guide](operations/admin-guide.md)
- [Agent operations](operations/agent-ops.md)
- [QA/UAT](testing/qa-uat.md)
- [Channel integrations](integrations/channels.md)
- [Payment integrations](integrations/payments.md)

## Build and verification quickstart

Run these from the repository root unless a doc says otherwise.

```bash
make verify-structure
npm --prefix apps/admin run build:ci
npm --prefix apps/website run build
bash scripts/migrations/validate_supabase_migrations.sh
deno lint --rules-exclude=no-unversioned-import,require-await supabase/functions/**/*.ts
deno check $(find supabase/functions -type f -name '*.ts' | sort)
deno test --allow-env=SUPABASE_SERVICE_ROLE_KEY,AUTH_PHONE_PASSWORD_SECRET,OTP_CODE_HASH_SECRET,OTP_TEST_PHONE,OTP_TEST_CODE,GOOGLE_SERVICE_ACCOUNT_EMAIL,GOOGLE_PRIVATE_KEY,AI_AUDIT_SHEET_ID $(find supabase/functions -type f -name '*_test.ts' | sort)
scripts/dev/flutterw analyze --fatal-infos
scripts/dev/flutterw test --concurrency=4 test/integration_smoke
```

For production-only release checks, set this explicitly so scripts do not expect a staging project:

```bash
COOL_PRODUCTION_ONLY_RELEASE=1 bash scripts/qa/validate_backend_config.sh
COOL_PRODUCTION_ONLY_RELEASE=1 bash scripts/qa/verify_android_flavors.sh
COOL_PRODUCTION_ONLY_RELEASE=1 bash scripts/qa/verify_ios_flavors.sh
```

## Environment and secret rules

- Environment variable names are documented in app, backend, channel, and payment docs. Values must stay in operator shells, CI secret stores, Supabase secrets, or mobile platform config files.
- Do not commit `.env`, service-role keys, database URLs, private keys, signing keys, OTP secrets, or webhook secrets.
- Production-only operation is supported, but every live mutation needs a backup point, named UAT account, scoped test data, evidence capture, and cleanup owner.

## Known non-production or constrained surfaces

- `apps/pwa` is intentionally retired and fail-closed. It is verified with `make pwa-check`, not deployed as an active user app.
- `agents/` contains operating contracts only. No production agent runtime, prompts, tools, memory, or workspaces are active in this repo.
- `integrations/` is a boundary folder. Active adapters currently live in Supabase functions and mobile services until a shared adapter is justified.
- Historical audit and plan docs may mention placeholder or coming-soon states as evidence. Product governance docs may also mention these terms as prohibited patterns. Active admin production paths are checked with `make structure-check` and the product surface registry.

## Roadmap

1. Execute pgTAP/RLS tests against a running local database or a controlled production-safe database window.
2. Complete connected Android/iOS UAT for SMS, camera, App Check, push, deep links, and payment guidance.
3. Add real staging or preview infrastructure before broad feature development resumes.
4. Promote channel adapters and agent runtimes only when their backend permission, audit, and test contracts are implemented.
5. Continue reducing production-only risk with feature flags, reversible migrations, and documented rollback drills.
