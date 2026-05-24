# Supabase Production Readiness Plan

Status: active
Project ref: `lhbowpbcpwoiparwnwgt`
Last live audit: 2026-05-24

This plan is the working checklist for taking the Collect Supabase project from a clean schema to production/go-live readiness. It is based on the current repo state, the linked Supabase project, and current Supabase guidance for production, RLS, query optimization, Edge Function secrets/auth, backups, and monitoring.

## Current Evidence

- Linked Supabase project is `ACTIVE_HEALTHY` on Postgres `17.6.1.021` in `us-east-2`.
- Remote `public` schema has exactly the expected repo-owned objects: `160` expected, `160` remote, `0` extra, `0` missing.
- Remote Edge Functions are limited to the seven repo-owned functions:
  - `auth-send-whatsapp-otp`
  - `ingest-payment-sms`
  - `parse-payment-sms`
  - `allocate-payment`
  - `manual-allocate-payment`
  - `request-public-collection`
  - `review-public-collection`
- `supabase db lint --linked --schema public --fail-on error` passes.
- `supabase db push --dry-run` reports the remote database is up to date.
- `supabase migration list --linked` shows local and remote migration history matched from `202605230001` through `20260523213113`.
- `make supabase-ready` runs the linked production-readiness gate without printing secret values.
- Public-schema database function execution has been removed from PostgreSQL `PUBLIC`; only intended `anon`, `authenticated`, and `service_role` grants remain.
- Edge Function auth mode is now checked from source/config: only the Supabase Auth SMS hook has JWT verification disabled, service functions require `INTERNAL_FUNCTION_SECRET`, and user functions require a Supabase user JWT.
- Database SSL enforcement is enabled.
- Live Auth config is now checked by `make supabase-ready`; safe live Auth hardening has been applied for redirects, anonymous sign-ins, email auth, phone auth, WhatsApp OTP hook delivery, password length, and password-update reauthentication.
- Database network restrictions are applied to a narrow operator workstation allowlist; public IPv4/IPv6 database access is no longer allowed.
- `make supabase-operational-report` returns read-only live database health and performance signals: cache hit ratio, table row/dead-row estimates, index scan usage, and slow-query data from `pg_stat_statements`.
- `make supabase-ready-strict` is the release gate and currently fails on four remaining platform items until CAPTCHA provider config, HIBP leaked-password protection on a paid plan, PITR, and paid-plan/project-pause risk are handled.
- `flutter analyze` reports no issues.
- `flutter test --no-pub --concurrency=1` passes.

## Production Gates

| Gate | Status | Evidence / Next action |
| --- | --- | --- |
| Schema ownership | Done | Only repo-owned public tables, views, policies, and functions remain remotely. |
| Migration history | Done | `202605230001` through `20260523213113` are applied remotely. |
| RLS enabled | Done | All `public` base tables have RLS enabled. |
| RLS lint | Done | Linked database lint has no schema errors. |
| RLS performance hardening | Done for current schema | Stable auth calls are wrapped, policy/query indexes are present, broad admin write policies are split by action, and policy roles remain explicit. |
| RPC exposure hardening | Done for current code-owned schema | Public function execution is revoked by default, service-role execution is explicit, authenticated RPCs are allowlisted, and anonymous direct execute is limited to public read helpers required by caller-context views. |
| Edge Function secrets | Done | Required function secrets are present remotely. |
| Edge Function allowlist | Done | Only seven expected functions are deployed. |
| Edge Function auth review | Done | Readiness enforces the local auth contract: only `auth-send-whatsapp-otp` has `verify_jwt=false`; internal functions call `requireInternalRequest`; user functions call `requireUser`. |
| SQL privileges | Done | Readiness enforces exact app-role table/view grants, including RLS-scoped authenticated receiver reads, and fails if any public-schema function remains executable by PostgreSQL `PUBLIC`. |
| Backups/PITR | Blocked on plan/add-on decision | Current backup check shows `pitr_enabled=false`; Supabase docs describe PITR as a paid add-on that must be enabled for the project before go-live if low RPO is required. |
| Organization plan | Blocked on plan/exception decision | Live Management API evidence shows organization `EasyMo` is on the Free plan. Supabase billing guidance says paid plans prevent projects from being paused. |
| SSL enforcement | Done | Database SSL enforcement is enabled. |
| Network restrictions | Done for current operator workstation | Public database CIDRs are removed; current direct Postgres access is restricted to explicit operator IPv4/IPv6 CIDRs. Add any stable CI/operator CIDRs with `make supabase-network-restrict` before expecting linked DB checks from those networks. |
| Auth production config | Blocked on CAPTCHA and paid-plan HIBP | Live Auth config is checked by readiness. Resolved live: production-only redirect allowlist, anonymous sign-ins disabled, email auth disabled for this WhatsApp/phone-OTP app, phone auth enabled, Send SMS Auth hook wired to `auth-send-whatsapp-otp`, password minimum length raised to 8, password-update reauthentication enabled, and Flutter passes CAPTCHA tokens to OTP calls when CAPTCHA is enabled. Remaining: CAPTCHA requires provider secret/config, and HIBP leaked-password protection requires a paid Supabase plan. |
| Monitoring | Done for go-live gate | `make supabase-ready` checks linked DB lint, Supabase security/performance advisors at error level, warning-level advisor inventory via `make supabase-advisor-warnings`, migration drift, schema drift, RLS, app-contract columns, index presence, SQL grants, Edge Function auth mode/inventory, secret names, live Auth config, SSL, network restrictions, and PITR status. Warning-level performance advisors currently report no code-owned issues. `make supabase-operational-report` reports cache, table growth, index usage, and slow-query visibility without printing secrets. `make supabase-ready-strict` fails release approval on unresolved platform warnings. |
| Load/UAT | Partially automated; live signoff pending | `make supabase-ready` runs linked rollback database UAT and admin/security UAT. Human-operated staging load and end-to-end mobile flows against production-like Supabase still need recorded signoff before public launch. |
| Rollback/restore runbook | Done for Supabase-owned operations | DB restore, function redeploy, secret rotation, emergency listing disablement, and logical backup fallback are documented in `docs/SUPABASE_OPERATIONS_RUNBOOK.md`. |

## Task Backlog

### P0: Required Before Go-Live

1. Keep the public schema clean and reproducible.
   - `supabase db push --dry-run` must show no pending migrations.
   - Remote public objects must exactly match repo migrations.
   - Remote Edge Functions must exactly match the local function allowlist.

2. Harden RLS for security and performance.
   - Ensure all exposed base tables have RLS.
   - Use explicit policy roles.
   - Use `(select auth.uid())` and `(select public.current_user_is_platform_admin())` for stable per-statement values.
   - Keep row-dependent helper checks indexed by their input columns.
   - Add indexes on columns used in policies, joins, and common query filters.

3. Lock down sensitive direct access.
   - No service-role key in Flutter or `.env.json`.
   - No broad `anon`/`authenticated` grants on sensitive base tables.
   - No public-schema function may remain executable by PostgreSQL `PUBLIC`.
   - Public reads must stay on safe views or explicit RPCs.
   - Raw SMS, parsed phone data, ledger rows, and service tables must remain service/admin scoped.

4. Finish Edge Function hardening.
   - Keep secrets in Supabase Function Secrets.
   - Keep user functions JWT-protected.
   - Keep service-only/internal flows guarded by `INTERNAL_FUNCTION_SECRET`.
   - Keep the Supabase Auth SMS hook guarded by Standard Webhooks signature verification.
   - Add deployment inventory and auth-mode validation to CI/readiness.

5. Configure platform production controls.
   - Database SSL enforcement is enabled.
   - Database network access is restricted to explicit operator IPv4/IPv6 CIDRs.
   - Enable PITR add-on if the product requires better-than-daily recovery.
   - Confirm project plan will not pause in production; current live organization plan is `free`, so upgrade or record an accepted exception before go-live.

6. Confirm Auth production settings.
   - Production `site_url` is HTTPS.
   - Production redirect allowlist is limited to `https://easymo.vercel.app`.
   - Anonymous sign-ins are disabled.
   - Confirm WhatsApp OTP hook behavior and rate limits.
   - Phone auth is enabled and the Send SMS Auth hook points to the deployed `auth-send-whatsapp-otp` Edge Function.
   - Email auth is disabled for this WhatsApp/phone-OTP app, avoiding an unused SMTP/auth surface.
   - Password minimum length is 8.
   - Password updates require recent reauthentication.
   - HIBP leaked-password protection is release-blocking for strict production readiness and requires a paid Supabase plan.
   - Configure CAPTCHA/bot protection with a provider secret.

### P1: Production Quality

7. Add operational checks.
   - Slow query report from `pg_stat_statements` is available through `make supabase-operational-report`.
   - Index/cache hit-rate report is available through `make supabase-operational-report`.
   - Table row count and growth report is available through `make supabase-operational-report`.
   - Live schema contract inventory is available through `make supabase-schema-inventory` and reports current public tables, views, functions, types, policies, app-role grants, RLS coverage, and exact expected-vs-remote object counts.
   - Redacted release evidence bundling is available through `make supabase-go-live-evidence` and captures strict status, final go-live gate result, operator blockers, platform exception-gate result, schema inventory, advisor warning inventory, operational report, code-owned readiness, secret scan, command exit codes, and a summary JSON under `.cache/`.
   - Final Supabase go-live decisioning is available through `make supabase-go-live-gate`, which returns `GO`, `GO-WITH-EXCEPTIONS`, or `NO-GO` from strict status plus validated platform exceptions.
   - Structured platform exception validation is available through `make supabase-platform-exception-gate`; only Free-plan project-pause risk and PITR/RPO risk may be accepted by signed exception, while CAPTCHA and HIBP remain non-exceptionable strict blockers.
   - Function deployment inventory check is enforced by `make supabase-ready`.
   - Secret-name inventory check without printing values is enforced by `make supabase-ready`.

8. Add Supabase CI gates.
   - `supabase db lint --linked --schema public --fail-on error`
   - `supabase db push --dry-run`
   - exact schema object diff
   - exact SQL privilege contract
   - exact function allowlist diff
   - exact Edge Function auth-mode contract
   - exact Edge Function secret-name inventory
   - `flutter analyze`
   - `flutter test --no-pub --concurrency=1`
   - linked Supabase readiness and operational report job in GitHub Actions when Supabase repository secrets are configured on a trusted branch/runner

Command:

```sh
make supabase-ready
```

This command is intentionally linked-project aware and never prints secret values. It fails on code-owned drift, fails if warning-level Supabase advisor inventory grows, and emits warnings for operator-owned platform settings such as SSL enforcement, network restrictions, and PITR.

Live schema inventory:

```sh
make supabase-schema-inventory
make supabase-schema-inventory-json
```

Current linked evidence: expected public objects `160`, remote public objects
`160`, extra `0`, missing `0`; public base-table RLS `28/28`; policies `61`;
views `9`; functions `57`; all `57/57` public functions have pinned
`search_path` settings.

Go-live evidence bundle:

```sh
make supabase-go-live-evidence
```

The bundle is generated under `.cache/supabase_go_live_evidence/` and is the
single local handoff folder for release review evidence. It is not committed and
does not include `.env` values. It now includes
`post_operator_checklist.json`, a redacted follow-up checklist for the operator
steps that must be verified after CAPTCHA, HIBP, organization-plan, or PITR
changes, and `acceptance_matrix.json`, a requirement-by-requirement status map
for release review.

Acceptance matrix:

```sh
make supabase-acceptance-matrix
make supabase-acceptance-matrix-json
```

The matrix reads a generated evidence bundle and marks each Supabase production
requirement as `pass`, `blocked`, or `fail` with the exact evidence file used.
It is the fastest way to see whether remaining work is platform/operator-owned
or code/schema-owned.

Final go-live gate:

```sh
make supabase-go-live-gate
make supabase-go-live-gate-json
```

Current linked decision remains `NO-GO` because CAPTCHA and HIBP are
non-exceptionable blockers.

Platform exception gate:

```sh
make supabase-platform-exception-gate
```

The gate validates `docs/release/SUPABASE_PLATFORM_EXCEPTIONS.json` against the
current strict blocker keys. It only allows `supabase_organization_plan` and
`supabase_pitr` after a signed, dated, expiring release-owner record. CAPTCHA
and HIBP blockers cannot be cleared by exception.

Post-operator verification checklist:

```sh
make supabase-post-operator-checklist
make supabase-post-operator-checklist-json
```

Use this immediately after the Supabase Dashboard or billing changes. It
summarizes the remaining blocker keys, redacted input presence, exact
remediation commands, pass conditions, and the final verification sequence
without printing secret values.

Warning inventory:

```sh
make supabase-advisor-warnings
```

This command allows known warning-level security debt to decrease, blocks new warning types or increased counts, and requires warning-level performance advisors to stay clean.

The GitHub Actions `Supabase Readiness` workflow is opt-in for linked project
checks because it uses production Supabase secrets. Use a trusted protected
branch/runner, then either dispatch the workflow with `run_linked_readiness=true`
or set the repository variable `SUPABASE_RUN_LINKED_READINESS=true`.

Release approval command:

```sh
make supabase-ready-strict
```

This command fails on unresolved platform settings. Current live release blockers are:

- CAPTCHA/bot protection is disabled and requires provider secret/configuration.
- HIBP leaked-password protection is disabled and requires a paid Supabase plan.
- Supabase organization is on the Free plan and requires upgrade or an accepted project-pause risk exception.
- PITR is disabled.

Generate a redacted operator handoff for those strict platform blockers:

```sh
make supabase-platform-packet
```

For automation, use:

```sh
make supabase-platform-packet-json
```

9. Add staging/preview validation.
   - Use Supabase branching or a separate staging project for migration rehearsals.
   - Run realistic SMS ingestion, parse, allocation, public listing, and invite flows.

10. Add incident and rollback documents.
    - Function redeploy/rollback steps are documented in `docs/SUPABASE_OPERATIONS_RUNBOOK.md`.
    - Migration restore/PITR steps are documented in `docs/SUPABASE_OPERATIONS_RUNBOOK.md`.
    - Secret rotation steps for Supabase, OpenAI, and WhatsApp are documented in `docs/SUPABASE_OPERATIONS_RUNBOOK.md`.
    - Emergency public listing disable/review process is documented in `docs/SUPABASE_OPERATIONS_RUNBOOK.md`.

## Research Basis

- Supabase production checklist: https://supabase.com/docs/guides/deployment/going-into-prod
- Supabase RLS guide and performance recommendations: https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase query optimization guide: https://supabase.com/docs/guides/database/query-optimization
- Supabase Edge Function secrets: https://supabase.com/docs/guides/functions/secrets
- Supabase Edge Function auth: https://supabase.com/docs/guides/functions/auth
- Supabase backups and PITR: https://supabase.com/docs/guides/platform/backups
- Supabase billing and paid plans: https://supabase.com/docs/guides/platform/billing-on-supabase
- Supabase database monitoring/inspection: https://supabase.com/docs/guides/database/inspect
