# Supabase Operations Runbook

Status: active
Project ref: `lhbowpbcpwoiparwnwgt`
Last updated: 2026-05-24

This runbook is for production Supabase operations that are outside normal Flutter app tests: migration deployment, Edge Function deployment, network restrictions, PITR/restore, rollback, and secret rotation. Commands intentionally avoid printing secret values.

## Required Local Environment

The local `.env` must provide:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_REF`
- `SUPABASE_DB_PASSWORD`
- `DATABASE_URL`

Optional fallback for direct Postgres mode:

- `SUPABASE_READINESS_DATABASE_URL` or `DATABASE_POOLER_URL`

Readiness database checks use `supabase db query --linked` by default. If an
operator intentionally sets `SUPABASE_DB_QUERY_MODE=direct`, Supabase direct
database connections are IPv6-only. In that mode, networks without IPv6 should
use the project Dashboard `Connect` panel to copy the Supavisor session pooler
connection string and set it as `SUPABASE_READINESS_DATABASE_URL`. This leaves
`DATABASE_URL` unchanged.

Edge Function secrets must be stored as Supabase Function Secrets, not committed files:

- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- `WHATSAPP_CLOUD_API_TOKEN`
- `WHATSAPP_PHONE_NUMBER_ID`
- `WHATSAPP_AUTH_TEMPLATE_NAME`
- `SEND_SMS_HOOK_SECRET`
- `INTERNAL_FUNCTION_SECRET`
- `SMS_INGEST_HMAC_SECRET`

## Deploy

Use this for routine Supabase deploys:

```sh
make supabase-deploy
```

The deploy script:

1. pushes pending migrations with `supabase db push`
2. deploys the seven allowlisted Edge Functions; `auth-send-whatsapp-otp` is
   deployed with `--no-verify-jwt` because Supabase Auth calls it as a signed
   webhook
3. runs the linked readiness gate

Use this after changing Auth-related environment variables or after rotating the SMS hook secret:

```sh
make supabase-auth-harden
```

The Auth hardening script:

1. keeps production redirects on the production HTTPS URL
2. disables anonymous and email auth
3. enables phone auth
4. wires the Send SMS Auth hook to `auth-send-whatsapp-otp`
5. rotates `SEND_SMS_HOOK_SECRET` into Standard Webhooks format when needed
6. updates the Edge Function secret and live Auth hook secret together
7. enables CAPTCHA only when `AUTH_CAPTCHA_PROVIDER`, `AUTH_CAPTCHA_SITE_KEY`,
   and `AUTH_CAPTCHA_SECRET` are provided together

Expected Edge Functions:

- `auth-send-whatsapp-otp`
- `ingest-payment-sms`
- `parse-payment-sms`
- `allocate-payment`
- `manual-allocate-payment`
- `request-public-collection`
- `review-public-collection`

## Readiness Gates

Use the normal gate during development:

```sh
make supabase-ready
```

Use the strict gate for release approval:

```sh
make supabase-ready-strict
```

The strict gate fails if platform settings are not production-ready. The normal gate fails on code-owned drift and warns on operator-owned platform settings.

Generate the operator handoff packet for any strict platform blockers:

```sh
make supabase-platform-packet
```

Use JSON for automation or ticket attachment:

```sh
make supabase-platform-packet-json
```

The packet is derived from the redacted `make release-status-json` output. It
lists only presence/missing flags, blocker keys, required operator inputs, safe
commands, and Supabase documentation links; it does not print provider secrets
or Supabase secret values.

After the operator changes Supabase Dashboard settings or adds approved
exceptions, generate the post-operator verification checklist:

```sh
make supabase-post-operator-checklist
make supabase-post-operator-checklist-json
```

This checklist is derived from the same redacted status JSON and gives one
ordered handoff for CAPTCHA, HIBP, organization-plan, and PITR follow-up. It
prints only placeholder commands and presence/missing flags.

The readiness gate now enforces these code-owned security invariants:

- local and remote migrations are aligned
- remote public schema objects match the repo-owned migration contract
- every public base table has RLS enabled
- expected indexes and app-contract columns exist
- app-role table/view grants match the narrow allowlist
- no public-schema function is executable by PostgreSQL `PUBLIC`
- Edge Function auth mode matches source/config expectations
- deployed Edge Function inventory and secret names match the repo allowlists

Use the live schema inventory when reviewing whether only needed public tables,
views, functions, types, policies, and app-role grants are present:

```sh
make supabase-schema-inventory
```

Use JSON when attaching the inventory to a release ticket or comparing counts in
automation:

```sh
make supabase-schema-inventory-json
```

The inventory is read-only catalog metadata. It does not query application table
rows and does not print secret values.

Build a redacted go-live evidence bundle before release review:

```sh
make supabase-go-live-evidence
```

By default this writes to `.cache/supabase_go_live_evidence/<utc timestamp>/`
and includes `summary.json`, `release_status.json`, `go_live_gate.json`,
`platform_packet.json`, `platform_exception_gate.txt`,
`post_operator_checklist.json`, `acceptance_matrix.json`,
`schema_inventory.json`, `advisor_warnings.txt`, `operational_report.json`,
`supabase_ready.txt`, `release_secret_scan.txt`, and `commands.tsv`.

Review the requirement-by-requirement acceptance matrix:

```sh
make supabase-acceptance-matrix
make supabase-acceptance-matrix-json
```

By default this reads `.cache/supabase_go_live_evidence/latest-test`. Pass a
specific bundle with `--bundle-dir` when reviewing a timestamped evidence
folder. The matrix marks schema, RLS, functions, advisors, readiness, Edge
Functions, secret scan, operations, platform controls, exceptions, operator
handoff, and the final go-live gate as `pass`, `blocked`, or `fail`.

To write to a known path:

```sh
SUPABASE_EVIDENCE_BUNDLE_DIR=.cache/supabase_go_live_evidence/manual-review make supabase-go-live-evidence
```

The bundle is intentionally local and ignored by git.

Run the final Supabase go-live decision gate:

```sh
make supabase-go-live-gate
make supabase-go-live-gate-json
```

This command combines the strict release status with the platform exception
gate. It returns `GO` only when strict Supabase readiness passes,
`GO-WITH-EXCEPTIONS` only when remaining blockers are exceptionable and covered
by a valid signed exception file, and `NO-GO` otherwise.

Validate signed platform risk exceptions before any release owner accepts a
strict gate exception:

```sh
make supabase-platform-exception-gate
```

This gate only permits structured exceptions for:

- `supabase_organization_plan`
- `supabase_pitr`

It deliberately rejects exceptions for CAPTCHA/bot protection and HIBP
leaked-password protection. Those must be resolved in Supabase before public
launch. To prepare an exception file, copy
`docs/release/SUPABASE_PLATFORM_EXCEPTIONS.example.json` to
`docs/release/SUPABASE_PLATFORM_EXCEPTIONS.json`, fill every field, keep an
expiry date, and attach the signed release-owner evidence. Do not create the
real exception file without release-owner approval.

Use the read-only operational report before go-live and during incident review:

```sh
make supabase-operational-report
```

It prints JSON with table row/dead-row estimates, cache hit ratio, index scan
usage, installed diagnostic extensions, and slow-query rows from
`pg_stat_statements` when available. The command does not print configured
secret values.

## CI Readiness

Linked Supabase readiness in GitHub Actions is opt-in because it checks the
production-linked project and requires production Supabase secrets. Database
contract checks use `supabase db query --linked` by default, so they do not
require a direct IPv6 Postgres path unless `SUPABASE_DB_QUERY_MODE=direct` is
set intentionally.

Use one of these patterns:

- Preferred: run linked readiness from a protected runner with access to the
  required repository secrets.
- Manual: dispatch the `Supabase Readiness` workflow with
  `run_linked_readiness=true` only after confirming the branch and secrets are
  appropriate for linked production checks.
- Repository opt-in: set `SUPABASE_RUN_LINKED_READINESS=true` only for trusted
  branches/runners.

Required GitHub secrets:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_REF`
- `SUPABASE_DB_PASSWORD`
- `DATABASE_URL`
- `SUPABASE_READINESS_DATABASE_URL` or `DATABASE_POOLER_URL` only when the
  runner intentionally uses `SUPABASE_DB_QUERY_MODE=direct` and needs an
  IPv4-compatible Supavisor pooler connection

## Network Restrictions

Do not guess CIDRs. Supabase network restrictions replace the whole database allowlist, so include every operator and CI CIDR that must keep direct Postgres access.

Example:

```sh
SUPABASE_DB_ALLOWED_CIDRS="203.0.113.10/32 2001:db8:1234::/64" make supabase-network-restrict
```

Notes:

- Avoid `0.0.0.0/0` and `::/0` in production.
- The helper refuses public CIDRs unless `ALLOW_PUBLIC_DB_CIDR=1` is explicitly set for an intentional rollback.
- Supabase network restrictions apply to Postgres and the database pooler, not the HTTPS APIs.
- Supabase documentation notes that direct database access from Edge Functions is blocked when restrictions are enabled; use Supabase client APIs from functions rather than direct Postgres connections.
- If direct Postgres checks need to run from CI, add stable CI egress CIDRs before enabling that CI job. GitHub-hosted runners do not provide one small stable static CIDR by default.

Rollback to public database access, only if direct DB access is accidentally locked out:

```sh
ALLOW_PUBLIC_DB_CIDR=1 SUPABASE_DB_ALLOWED_CIDRS="0.0.0.0/0 ::/0" make supabase-network-restrict
```

## SSL Enforcement

Database SSL enforcement is enabled for this project as of 2026-05-23. Verify it with:

```sh
set -a; . ./.env; set +a
supabase ssl-enforcement get --project-ref "$SUPABASE_PROJECT_REF" --experimental
```

Supabase applies SSL enforcement to direct Postgres and pooler connections. HTTPS APIs already require SSL.

## Auth Production Settings

The readiness gate reads live Auth configuration through the Supabase Management API and does not print secret values.
If the Management API hides function or secret inventory for the current
operator role, the gate falls back to live function endpoint probes and local
environment presence checks. It still fails on code-owned drift, missing
migrations, missing RLS, broken function auth gates, or missing local secrets
needed for the probes.

The gate also runs rollback-only database UAT against the linked project:

- `scripts/collect_linked_uat.sh` creates temporary Auth users inside one
  transaction, exercises profile creation, private collection creation, public
  approval, payment intent instructions, deterministic allocation, idempotency,
  ambiguous-review behavior, manual allocation audit logging, recurring period
  creation, and public anonymity views, then rolls the transaction back.
- `scripts/collect_admin_security_uat.sh` proves admin RBAC lanes, raw-SMS
  metadata masking, compliance reveal with sensitive-access/audit logging,
  moderation approval, payments-admin allocation, and support/read-only denial
  paths, then rolls the transaction back.

For a live OpenAI/Edge parser smoke, run:

```sh
./scripts/collect_live_parser_uat.sh
```

This creates temporary committed rows, invokes the deployed `parse-payment-sms`
function, verifies parser metadata, allocation, ledger posting, public anonymity
output, and then cleans up the rows. If OpenAI returns HTTP 429, the script
reports a controlled skip by default because provider quota/rate state is
external. Set `COLLECT_PARSER_UAT_STRICT=1` to make provider throttling fail the
gate.

Normal check:

```sh
make supabase-advisors
make supabase-ready
```

Release check:

```sh
make supabase-ready-strict
```

Current applied settings:

- Keep `site_url` on the final production HTTPS URL.
- Redirect allowlist is limited to the production HTTPS URL.
- Anonymous sign-ins are disabled.
- Email auth is disabled for this WhatsApp/phone-OTP app.
- Phone auth is enabled.
- The Send SMS Auth hook points to the deployed `auth-send-whatsapp-otp` Edge Function.
- Password minimum length is set to 8.
- Password updates require recent reauthentication.
- HIBP leaked-password protection is strict-release blocking and requires a paid Supabase plan.

Current release hardening decisions to close:

- Configure CAPTCHA/bot protection with the chosen provider, public site key,
  and provider secret.
- Upgrade the Supabase organization and rerun Auth hardening so HIBP leaked-password protection can be enabled.
- Enable PITR if low-RPO restore is required, or record a signed recovery objective exception.
- Decide whether user MFA enrollment should be required, optional, or only available to administrators.

The Flutter login flow already passes `captchaToken` to Supabase OTP requests when built with:

- `--dart-define=AUTH_CAPTCHA_ENABLED=true`
- `--dart-define=AUTH_CAPTCHA_PROVIDER=hcaptcha` or `turnstile`
- `--dart-define=AUTH_CAPTCHA_SITE_KEY=<provider site key>`

Enable the live Supabase CAPTCHA setting by providing the provider, public site
key, and provider secret to the Auth hardening script:

```sh
AUTH_CAPTCHA_PROVIDER=hcaptcha AUTH_CAPTCHA_SITE_KEY="<provider-site-key>" AUTH_CAPTCHA_SECRET="<provider-secret>" make supabase-auth-harden
```

Do not commit the provider secret or site key unless the site key is intentionally public for the shipped client.

Relevant Supabase Management API endpoint:

```sh
set -a; . ./.env; set +a
curl -fsS "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN"
```

Do not paste the raw response into tickets or chat because it includes provider configuration keys and secret-bearing fields.

## PITR And Restore

Before launch, enable PITR if the recovery objective requires better-than-daily backups. Verify current backup state with:

```sh
set -a; . ./.env; set +a
supabase backups list --project-ref "$SUPABASE_PROJECT_REF" -o json
```

Current live state is `pitr_enabled=false`. Supabase documents PITR as a paid
add-on for eligible projects and compute sizes. The project currently exposes
these PITR add-on variants through the Supabase Management API:

- `pitr_7`: 7 days, `$100/month`
- `pitr_14`: 14 days, `$200/month`
- `pitr_28`: 28 days, `$400/month`

The repo includes a guarded helper so the billable action is explicit:

```sh
PITR_ADDON_VARIANT=pitr_7 make supabase-pitr-enable
```

That command reports the current and requested PITR state, then stops. To apply
the billable add-on, rerun with the exact confirmation token printed by the
script:

```sh
PITR_ADDON_VARIANT=pitr_7 CONFIRM_ENABLE_PITR="$SUPABASE_PROJECT_REF:pitr_7" make supabase-pitr-enable
```

After PITR is enabled, rerun:

```sh
make supabase-ready-strict
```

Restore should be rehearsed against staging before production use. Supabase CLI supports PITR restore with `supabase backups restore`; use the exact timestamp from the incident decision record.

Temporary logical backup fallback while PITR is not enabled:

```sh
make supabase-logical-backup
```

By default this creates a schema-only dump under `.cache/supabase_backups/`. To include public table data on the local machine, run:

```sh
INCLUDE_DATA=1 make supabase-logical-backup
```

Data dumps can include sensitive operational data. The `.cache/` directory is ignored and should not be committed or shared.

## Secret Rotation

Rotate secrets immediately if they are exposed in chat, logs, screenshots, issue trackers, CI logs, or committed files.

Sequence:

1. Generate a replacement secret in the provider dashboard.
2. Update the Supabase Function Secret using `supabase secrets set`.
   Supabase-provided `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
   `SUPABASE_SERVICE_ROLE_KEY` are reserved runtime names and may be skipped by
   the CLI when setting secrets manually.
3. Redeploy affected Edge Functions with `make supabase-deploy`.
4. Run `make supabase-ready`.
5. Revoke the old provider secret.
6. Record the rotation time and affected functions.

## Incident Rollback

Database migrations:

- Prefer forward-fix migrations for normal bugs.
- Use PITR only for severe data corruption or destructive migration incidents.
- Freeze writes before a PITR restore decision.

Edge Functions:

1. Identify the last known-good commit.
2. Check out that commit in a clean worktree.
3. Deploy only the affected function or run `make supabase-deploy`.
4. Run `make supabase-ready`.

Public collections:

- Use `review-public-collection` to disable or reject unsafe public listings.
- Keep raw SMS and parsed payment review data behind service/admin access only.

## CI Secrets

Configure these GitHub repository secrets to activate linked Supabase readiness in CI:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_REF`
- `SUPABASE_DB_PASSWORD`
- `DATABASE_URL`
- `SUPABASE_READINESS_DATABASE_URL` or `DATABASE_POOLER_URL` only when using
  `SUPABASE_DB_QUERY_MODE=direct` from a runner without direct IPv6 DB access

The CI job skips linked readiness if those secrets are missing, so pull requests from contexts without secrets still run the Flutter gates.
