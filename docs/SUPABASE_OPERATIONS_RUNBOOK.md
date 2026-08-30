# Supabase Operations Runbook

Updated: 2026-08-28

This runbook covers the bank-transfer-only Groups backend. Collect does not
initiate payments. Beneficiary-bank SMS and email are candidate evidence; only
independently imported daily statements can finalize reconciliation and ledger
posting.

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

The later local migration below adds independent profile country/currency,
conditional European Revolut identity, and the profile update RPC. Treat it as
pending until a dry-run, controlled push, migration-history readback, and RPC
UAT prove it on the linked project:

```text
supabase/migrations/20260828100000_profile_country_session_independence.sql
```

## Edge Functions

Active functions:

```text
auth-send-whatsapp-otp
dispatch-notifications
ingest-bank-email
ingest-bank-sms
ingest-bank-statement
send-notification
```

Validate:

```sh
./scripts/collect_edge_auth_contract_uat.sh
deno check supabase/functions/ingest-bank-email/index.ts \
  supabase/functions/ingest-bank-sms/index.ts \
  supabase/functions/ingest-bank-statement/index.ts
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

Bank-transfer reconciliation and allocation:

```sh
./scripts/collect_linked_uat.sh
```

The rollback UAT proves maker-checker beneficiary governance, exact-once bank
evidence, statement finality, balanced ledger posting, daily close, and rollback.

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

Current release blockers are limited to current SMS-first evidence gaps:
product signoff, linked migration/UAT, Android SMS UAT, Admin PWA live proof,
current Android release APK/AAB artifacts, and release-owner signoff.

## Incident Handling

- Stop writes before destructive recovery.
- Preserve raw evidence immutable.
- Use audited admin reparse/review for ambiguous parsed events.
- Do not manually post ledger entries outside approved database functions.
- After recovery, rerun linked UAT and Admin PWA gates.
