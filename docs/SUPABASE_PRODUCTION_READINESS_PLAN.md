# Supabase Production Readiness Plan

Updated: 2026-05-27

This plan is aligned to the corrected SMS-first Groups product. It replaces the
older platform-blocker framing from the previous release packet.

## Current Decision

Current Supabase status is **NO-GO** because the linked project is not yet on
the local SMS-first payment-intent allocation contract.

Fresh evidence:

- Local migration validation passes.
- Edge Function auth contract passes.
- Parser, ingestion, and allocation functions type-check.
- Linked admin/security rollback UAT passes.
- Linked contribution/allocation UAT fails because the remote database is missing the current `create_group_with_owner` RPC.
- `supabase db push --dry-run` is blocked from the current operator IP by the
  Supabase tenant database allowlist.

Older CAPTCHA/HIBP/plan/PITR findings are not current release blockers unless a
fresh readiness run after the SMS-first migration reproduces them.

## Required Backend Work

1. Apply or dry-run `supabase/migrations/202605270001_sms_first_group_payment_intents.sql`
   from an allow-listed database network.
2. Rerun `scripts/collect_linked_uat.sh`.
3. Rerun `scripts/collect_admin_security_uat.sh`.
4. Deploy active Edge Functions only:
   - `auth-send-whatsapp-otp`
   - `ingest-payment-sms`
   - `parse-payment-sms`
   - `allocate-payment`
5. Run Android SMS access UAT so the backend receives real MoMo SMS rows,
   parser output, allocation results, exceptions, and ledger entries.

## Current Validation Commands

```sh
./scripts/migrations/validate_supabase_migrations.sh
./scripts/collect_edge_auth_contract_uat.sh
deno check supabase/functions/parse-payment-sms/index.ts \
  supabase/functions/ingest-payment-sms/index.ts \
  supabase/functions/allocate-payment/index.ts
./scripts/collect_admin_security_uat.sh
./scripts/collect_linked_uat.sh
supabase db push --dry-run
```

## Release Gate Semantics

Release status now reports only current SMS-first blockers:

- `product_signoff`
- `linked_supabase_sms_first_migration`
- `android_sms_access_uat`
- `admin_pwa_live_url`
- `release_owner_signoff`

Use:

```sh
make release-status-json
make supabase-go-live-gate-json
make supabase-platform-packet-json
```

## Data And Privacy Requirements

- Use Collect ID, payment intent, amount, receiver, and timing for allocation.
- Keep raw SMS private by default.
- Keep ambiguous events in exception queues.
- Do not reintroduce manual SMS paste, contributor-reported transaction IDs,
  public campaign review, or manual ledger posting shortcuts.
