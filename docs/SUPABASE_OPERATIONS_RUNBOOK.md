# Supabase operations runbook: Rwanda MoMo release

Updated: 2026-09-28. This runbook covers the current Rwanda-only RWF/MTN MoMo/Airtel Money product. Older bank/Stripe/geographic migrations and functions remain historical source or deployed-state questions, not current release capabilities. No production change is authorized by this document alone.

## Safe execution

- Use synthetic records and a disposable full-schema project for destructive UAT. Do not print service-role, notification, WhatsApp or signing secrets, raw SMS, payer details or customer phone numbers.
- Use approved allow-listed database/network access. Preserve a pre-change migration/function/grant readback and a rollback/roll-forward plan.
- Treat missing credentials, skipped checks, and absent deployed readback as blocked rather than passed.

## Source and migration validation

```sh
./scripts/migrations/validate_supabase_migrations.sh
COLLECT_SKIP_DOTENV=1 SUPABASE_DB_QUERY_MODE=local ./scripts/collect_linked_uat.sh
```

The historical 20 August checkpoint ended at `20260820185500_revoke_direct_bank_transfer_intent_read.sql`; it is not evidence of the current linked project state. Compare the exact reviewed commit and full local migration ledger with an authorized timestamped deployed readback. Rehearse all pending numbered migrations and the staged SQL in `deploy/hardening/` in a disposable full-schema project first. The staged SQL is not registered or executed production migration evidence.

A production dry-run or push, where authorized, must be reviewed against the pinned CLI behavior and an approved plan; do not execute it merely because local validation passed. Check RLS, grants, security-definer functions, direct table writes, actor revocation, replay, account switch, retry, reversal and ledger balance before and after.

## Edge Functions and legacy routes

Compare Rwanda functions `auth-send-whatsapp-otp`, `dispatch-notifications`, `ingest-payment-sms`, `parse-payment-sms`, `verify-play-integrity` and `send-notification` with the deployed inventory and exact source hashes. Run negative and positive HTTP tests with synthetic payloads, signed hooks and supported Play verdicts. Confirm actual WhatsApp provider timeouts/quotas, notification delivery, key rotation and safe public errors.

Bank evidence and Stripe functions from historical releases may exist in source or deployment. For the Rwanda-only candidate, prove that unsupported bank routes, grants and UI entry points cannot create current member financial state. Preserve historical data/migrations; disable or scope runtime exposure only through a reviewed deployment plan.

## Controlled Rwanda UAT

1. Verify Rwanda WhatsApp identity, profile, provider/07 number, Collect ID and account-switch isolation.
2. Create an eligible private group on an exact signed Android build; test SMS consent, denial, revocation and Play Integrity behavior.
3. Create an exact whole-RWF intent and hand off only to provider USSD. Never enter a PIN or real funds in synthetic UAT.
4. Exercise new receipt capture, protected queue, owner-bound encrypted storage, durable exact ACK, offline/reboot/overflow and key-loss recovery on supported devices.
5. Exercise bounded parsing, unique matching, ambiguity, duplicate/replay, timeout, reversal, approved reconciliation and immutable balanced posting in an isolated database.
6. Verify Admin roles, revocation, audited exception/reveal workflow, complete history paging, notifications and accurate unavailable states.
7. With authorized live access, independently reconcile actual provider/statement evidence and a controlled pilot; retain sanitized evidence, daily close and stop criteria.

## Web, backup and release

Build and inspect member/public and Admin artifacts from a clean protected commit. Test deployed response headers, auth isolation, warm cache updates, logout and offline behavior. Set RPO/RTO and restore database, Storage, configuration/auth and evidence to an isolated environment, then reconcile ledger balances.

Run existing source/readiness scripts against the exact candidate, record pass/fail/skip separately, and attach current artifact hashes, deployment readback, physical device/provider results, monitoring/incident rehearsals and accountable owner decision. The current 28 September integration is **NO-GO** because those external and production artifacts are not yet verified.
