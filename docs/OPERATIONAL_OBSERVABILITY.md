# Operational Observability

Updated: 2026-03-22

This document is the current operational truth for the COOL payment-adjacent
flows. It replaces older audit conclusions that predated the restored Android
SMS ingest path and the admin operations dashboard.

## Current Flow Truth

### SMS ingest

- Android SMS autoread is implemented in app code via
  `lib/features/momo/services/momo_sms_autoread_service.dart`.
- Captured messages are normalized and inserted through
  `lib/features/momo/repositories/momo_sms_ingestion_repository.dart`.
- Raw messages land in `public.momo_sms_raw`.
- The client immediately queues `parse-momo-sms` for server-side parsing.
- Sensitive retention is now bounded by
  `public.redact_momo_sms_artifacts_due(...)`, which redacts raw SMS bodies
  after successful parse + matched reconciliation and clears stored AI payloads
  after the retention window.

### MoMo parsing and reconciliation

- `supabase/functions/parse-momo-sms/index.ts` parses raw SMS text and writes:
  - `public.momo_sms_parsed`
  - `public.momo_ledger_entries`
  - `public.momo_reconciliations`
- Reconciliation drives pending app payments toward confirmation and surfaces
  manual-review states when automatic matching is not safe.

### Partner checkout

- Rayon ticket, shop, and support checkout still open via MoMo/USSD from the
  mobile client.
- Checkout creation happens in
  `lib/features/partners/repositories/rayon_sports_repository.dart`.
- All partner checkout flows still depend on the downstream SMS parse +
  reconciliation pipeline before the backend marks payment-linked records as
  confirmed/paid/valid.

### Wallet sync

- Google Wallet remains deferred to Phase 2 and is not part of the current
  release surface.
- The backend implementation can stay parked in
  `supabase/functions/wallet-issuer/index.ts`, but Phase 1 release readiness
  does not depend on wallet issuance.

## Release Dashboard

The admin release dashboard lives at `/admin/operations`.

It reads from:

- `public.get_operational_release_dashboard()`
- `public.get_operational_triage_issues()`
- `public.get_momo_sms_operational_summary()`
- `public.get_recent_operational_health_events(...)`

The release-truth cards intentionally track only server-trusted surfaces:

- MoMo parsing
- Payment sync
- Edge Functions
- Config hygiene

Mobile-reported SMS ingest and partner checkout signals remain visible in the
recent-signal feed, but they do not drive release status because they originate
from authenticated app telemetry rather than server-observed state.

The same admin screen now also includes a dedicated M-Money SMS summary block
for:

- device-reported sync success/failure and duplicate pressure
- device-reported sender drift from unapproved SMS sender IDs that still look transactional
- device-reported retry-queue pressure for locally queued failed ingests
- server-observed parse backlog and parse failures
- server-observed unsupported sender inventory and acknowledgement backlog
- server-observed migration safety for legacy `group_contributions.status = 'completed'` rows
- reconciliation open-review pressure and closed-review throughput
- retention/redaction backlog

This block is operationally useful, but only the server-observed metrics should
be treated as release-gating truth.

There is now also a scheduled trusted server-side verifier for M-Money SMS
migration safety. It runs through Supabase cron, inserts `system`-origin
`sms_ingest` health events, and surfaces in the top release dashboard as trusted
`SMS Ingest` health instead of relying only on device telemetry or manual
database checks.

For repeatable environment verification from the repo, use
`scripts/verify_momo_sms_supabase_rollout.sh`. It checks the expected M-Money
SMS migrations, cron jobs, legacy contribution-row invariants, summary metrics,
release-dashboard status, and latest trusted migration-safety event against the
target database referenced by `DATABASE_URL` or `SUPABASE_DB_URL`.

The same verifier is now wired into `scripts/release_readiness.sh` as an opt-in
remote gate and can run automatically in GitHub Actions when `SUPABASE_DB_URL`
is configured.

For repo-local regression coverage, `scripts/check_momo_sms_contracts.sh`
validates the verifier scripts and workflows, then runs the focused Flutter and
Deno M-Money SMS contract tests. The main CI workflow exposes this as the
`M-Money SMS Contracts` job.

For mobile-runtime coverage, the repo now also ships
`scripts/run_momo_sms_device_integration.sh` and the nightly/on-demand GitHub
workflow `momo-sms-device-integration.yml`. That lane seeds approved sender SMS
rows into an Android emulator inbox, grants SMS permissions, runs the real
`Telephony.getInboxSms()` sync path, and stores logcat plus seeded inbox
snapshots as artifacts.

The same admin surface now also includes a generic M-Money SMS manual-review
queue for items that do not belong to the bank allocation workflow. Admins can
close single reviews or bulk-close the visible queue as "not app-linked"
without deleting the underlying wallet history stored in
`momo_sms_raw` / `momo_sms_parsed` / `momo_ledger_entries`.

The MoMo SMS operations workspace now also exposes an admin-only sender
inventory for unsupported or legacy raw SMS senders. That turns hidden sender
drift in `momo_sms_raw` into a visible backlog with parse and reconciliation
outcomes, even when no recent mobile telemetry exists in
`operational_health_events`.

Operators can now explicitly acknowledge a sender as reviewed legacy history.
That acknowledgement does not approve the sender for future intake and does not
mutate raw SMS records. It only records that the unsupported sender backlog was
reviewed.

## Triage Queue

The triage queue is intentionally narrow. It focuses on the release blockers
that must be visible before users report them:

- failed payment sync
  - pending transactions stuck beyond the acceptable window
  - reconciliations that require manual review
- failed function invocation
  - unexpected Edge Function failures recorded by shared instrumentation
- stale config
  - missing or expired review windows for required `app_config` keys

## Health Emitters

These flows now emit operational health events into
`public.operational_health_events`:

- MoMo parsing
  - parse + reconcile success
  - manual-review outcomes
  - parse failures
- Edge Function failures
  - shared failure logging for critical Supabase functions

Mobile client telemetry is relayed through the `record-operational-health` Edge
Function and stamped with `ingest_origin = mobile_app`:

- SMS ingest
  - listener activation
  - inbox recovery success/failure
  - raw SMS capture and parse-queue success/failure
- Partner checkout
  - successful ticket/shop/support handoff creation
  - checkout failures before payment sync starts

These mobile-origin events are useful for debugging and support triage, but
they are not treated as release-gating truth.

Authenticated clients no longer insert directly into
`public.operational_health_events`. The table now expects service-role writes,
with mobile telemetry entering only through the relay function.

## Release Use

Before cutting a release candidate:

1. Run the normal automated readiness checks.
2. Open Admin > Operations.
3. Confirm there are no critical triage issues.
4. Confirm payment sync, MoMo parsing, and Edge Functions are not in a failing
   state.
5. Treat config-hygiene warnings as release work, not post-release cleanup.

Do not block the current release on Google Wallet readiness. That surface is
deferred until Phase 2.
