# Supabase Production Readiness Plan

Updated: 2026-05-31

This plan is aligned to the corrected SMS-first Groups product. It replaces the
older platform-blocker framing from the previous release packet.

## Current Decision

Current Supabase backend status is **blocked on linked migration drift**.
Overall release remains **NO-GO** until the contribution-intent sender-hash
migration is applied, Android SMS device UAT, release signing/scope evidence,
product signoff, and release-owner signoff are complete.

Fresh evidence:

- Local migration validation passes.
- Edge Function auth contract passes.
- Parser, ingestion, and allocation functions type-check.
- Linked admin/security rollback UAT passes.
- Linked contribution/allocation rollback UAT now fails because the linked
  project drops the contribution intent sender hash.
- `scripts/supabase_production_readiness.sh` cannot be claimed green until
  linked contribution UAT passes again.
- Legacy Edge Functions for manual allocation and public-collection requests
  were removed from the linked project.

Older CAPTCHA/HIBP/plan/PITR findings are not current release blockers unless a
fresh readiness run reproduces them.

## Required Backend Work

1. Apply `supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql`
   to the linked project, then rerun `scripts/collect_linked_uat.sh`.
2. Deploy active Edge Functions only:
   - `auth-send-whatsapp-otp`
   - `ingest-payment-sms`
   - `parse-payment-sms`
   - `allocate-payment`
3. Run Android SMS access UAT so the backend receives real MoMo SMS rows,
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
./scripts/supabase_production_readiness.sh
```

## Release Gate Semantics

Release status now reports only current SMS-first blockers:

- `product_signoff`
- `android_sms_access_uat`
- `android_release_signing_review`
- `ios_release_scope`
- `linked_supabase_sms_first_migration`
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
