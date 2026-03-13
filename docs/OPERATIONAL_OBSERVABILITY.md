# Operational Observability

Updated: 2026-03-13

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

- Google Wallet issuance is handled by
  `supabase/functions/wallet-issuer/index.ts`.
- Wallet readiness depends on the ticket already being confirmed.

## Release Dashboard

The admin release dashboard lives at `/admin/operations`.

It reads from:

- `public.get_operational_release_dashboard()`
- `public.get_operational_triage_issues()`
- `public.get_recent_operational_health_events(...)`

The dashboard tracks these monitored surfaces:

- SMS ingest
- MoMo parsing
- Payment sync
- Wallet sync
- Partner checkout
- Edge Functions
- Config hygiene

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

- SMS ingest
  - listener activation
  - inbox recovery success/failure
  - raw SMS capture and parse-queue success/failure
- MoMo parsing
  - parse + reconcile success
  - manual-review outcomes
  - parse failures
- Wallet sync
  - successful wallet pass preparation
  - unexpected wallet issuance failures
- Partner checkout
  - successful ticket/shop/support handoff creation
  - checkout failures before payment sync starts
- Edge Function failures
  - shared failure logging for critical Supabase functions

## Release Use

Before cutting a release candidate:

1. Run the normal automated readiness checks.
2. Open Admin > Operations.
3. Confirm there are no critical triage issues.
4. Confirm payment sync and Edge Functions are not in a failing state.
5. Treat config-hygiene warnings as release work, not post-release cleanup.
