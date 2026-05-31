# Supabase Operations Runbook

Updated: 2026-05-27

This runbook covers operational steps for the SMS-first Groups backend. It
intentionally avoids the older release-packet platform-blocker model.

## Safe Command Rules

- Do not print service-role keys, OpenAI keys, WhatsApp hook secrets, raw SMS,
  MoMo numbers, or customer phone numbers.
- Use synthetic data and rollback transactions for automated UAT.
- Apply database changes only from an allow-listed database network.

## Migration Deployment

Validate locally:

```sh
./scripts/migrations/validate_supabase_migrations.sh
```

Dry-run from an allow-listed network:

```sh
supabase db push --dry-run
```

Apply after review:

```sh
supabase db push
```

Current required migration:

```text
supabase/migrations/202605270001_sms_first_group_payment_intents.sql
```

## Edge Functions

Active functions:

```text
auth-send-whatsapp-otp
ingest-payment-sms
parse-payment-sms
allocate-payment
```

Validate:

```sh
./scripts/collect_edge_auth_contract_uat.sh
deno check supabase/functions/parse-payment-sms/index.ts \
  supabase/functions/ingest-payment-sms/index.ts \
  supabase/functions/allocate-payment/index.ts
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

Contribution/allocation:

```sh
./scripts/collect_linked_uat.sh
```

If contribution/allocation UAT fails because the linked project lacks `create_group_with_owner`, the linked project is behind the local migration.

## Android SMS Access UAT

Run with sanitized evidence:

1. Android creator completes profile with receiver MoMo.
2. Creator creates a group and grants SMS access.
3. Contributor creates payment intent and pays through MoMo USSD.
4. Receiver phone receives MoMo SMS.
5. SMS row appears in Supabase.
6. Parser creates structured transaction fields.
7. Allocation matches the payment intent and Collect ID where present.
8. Ledger entry posts once.
9. Ambiguous/expired/unauthorized events stay in exceptions.

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
