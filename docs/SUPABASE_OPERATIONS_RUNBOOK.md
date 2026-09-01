# Supabase Operations Runbook

Updated: 2026-08-31

This runbook covers the geographic Groups backend: Rwanda MoMo USSD with
consented Android receipt evidence, plus diaspora bank/Revolut transfers.
Collect never accepts a MoMo PIN or bank credential and never treats opening an
external payment surface as success.

## Safe Command Rules

- Do not print service-role keys, notification-provider keys, WhatsApp hook
  secrets, raw bank evidence, payer details, or customer phone numbers.
- Use synthetic data and rollback transactions for automated UAT.
- Apply database changes only from an allow-listed database network.

## Migration Deployment

Validate locally:

```sh
./scripts/migrations/validate_supabase_migrations.sh
```

Dry-run from an allow-listed network:

```sh
supabase db push --dry-run --skip-vault
```

Apply after review:

```sh
supabase db push --skip-vault
```

The reviewed local migration ledger must be compared with production by dry-run.
The explicit `--skip-vault` flag keeps this schema-only release from changing
configured Vault secrets as a side effect of a current Supabase CLI `db push`.
At the confirmed 2026-08-20 production checkpoint it ends at:

```text
supabase/migrations/20260820185500_revoke_direct_bank_transfer_intent_read.sql
```

The local chain below remains pending until a dry-run, controlled push,
migration-history readback, and RPC UAT prove it on the linked project:

```text
supabase/migrations/20260828100000_profile_country_session_independence.sql
supabase/migrations/20260831084239_expand_admin_queue_sla_support.sql
supabase/migrations/20260831084646_hybrid_geographic_payment_rails.sql
```

## Edge Functions

Active functions:

```text
auth-send-whatsapp-otp
dispatch-notifications
ingest-bank-email
ingest-bank-sms
ingest-bank-statement
ingest-payment-sms
parse-payment-sms
verify-play-integrity
send-notification
```

Validate:

```sh
./scripts/collect_edge_auth_contract_uat.sh
deno check supabase/functions/ingest-bank-email/index.ts \
  supabase/functions/ingest-bank-sms/index.ts \
  supabase/functions/ingest-bank-statement/index.ts \
  supabase/functions/ingest-payment-sms/index.ts \
  supabase/functions/parse-payment-sms/index.ts \
  supabase/functions/verify-play-integrity/index.ts
```

Deploy active functions through:

```sh
./scripts/supabase_deploy.sh
```

## Linked UAT

Admin/security:

```sh
./scripts/collect_admin_security_uat.sh
```

MoMo and bank reconciliation/allocation:

```sh
./scripts/collect_linked_uat.sh
```

The rollback UAT must prove scoped MoMo parsing/allocation plus maker-checker
bank governance, statement finality, balanced ledger posting and rollback.

## Controlled Rwanda MoMo UAT

1. Verify WhatsApp-derived Rwanda country/provider/07 number, then edit and save it.
2. Create a private group on a Play-Integrity-approved Android build.
3. Grant receipt access and verify the app has `RECEIVE_SMS` but no `READ_SMS`.
4. Create one exact RWF intent and approve it only in MoMo USSD.
5. Receive a synthetic safe receipt, verify authenticated ingestion and bounded parsing.
6. Prove one unique member/group allocation and one balanced ledger post.
7. Prove duplicates are idempotent and ambiguous/unmatched receipts remain in the admin queue.

## Controlled Bank Evidence UAT

Run with sanitized evidence:

1. Two independent administrators approve the real EUR beneficiary.
2. A member creates a bank-transfer contribution request.
3. The member authorizes the transfer outside Collect in their banking app.
4. Controlled SMS or email creates candidate evidence.
5. The parser extracts bounded transaction fields and deduplicates the event.
6. Candidate evidence never changes the member or group balance.
7. A controlled daily statement import provides bank finality.
8. Reconciliation matches the unique Collect reference and posts one balanced ledger transaction.
9. Ambiguous, duplicate, unmatched, or unauthorized events remain in exceptions.

## Admin PWA

Local:

```sh
./scripts/admin_pwa_release_build.sh
ADMIN_PWA_RENDER_EVIDENCE_DIR=.cache/admin_pwa_render_smoke/20260527T041454Z-sms-first-current ./scripts/admin_pwa_render_smoke.sh
```

Live:

```sh
ADMIN_PWA_LIVE_URL="https://<admin-host>" ./scripts/admin_pwa_live_gate.sh --json
```

## Release Status

```sh
make release-status-json
make supabase-go-live-gate-json
make supabase-platform-packet-json
make supabase-post-operator-checklist-json
```

Current blockers include linked migration/UAT, real Android SMS/USSD acceptance,
Google Play restricted-SMS approval, Play Integrity configuration, diaspora bank
acceptance, Admin PWA live proof, current store artifacts and accountable signoff.

## Incident Handling

- Stop writes before destructive recovery.
- Preserve raw evidence immutable.
- Use audited admin reparse/review for ambiguous parsed events.
- Do not manually post ledger entries outside approved database functions.
- After recovery, rerun linked UAT and Admin PWA gates.
