# Signed OTP uncertain-send recovery

## Local implementation and verification

Migration **145**, `20260930130000_signed_otp_uncertain_recovery.sql`, installs the previously staged signed-hook quota contract in the canonical chain, preserves the existing atomic per-phone rolling quota, and adds an attempt/revision fence plus immutable outcome evidence. The private policy has no invented configuration row. Its owner explicitly configures hourly/daily limits and enables it; the rollback UAT tests both disabled and enabled operation.

The actual Edge handler now verifies the signed body and timestamp, builds the complete provider message before reserving quota, obtains a one-time durable send claim, and records a bounded provider acknowledgement as **accepted**. A transport error, timeout, HTTP error, malformed acknowledgement or oversized response is **ambiguous**. It does not imply that the request was not sent. No retry, alternate transport or quota refund occurs after uncertainty.

A four-second total hook deadline and a 2.5-second provider deadline bound body/RPC/transport waits. The actual pinned Supabase SDK RPC builder receives the abort signal. A durable operation can still finish after its HTTP acknowledgement is lost; exact hook replay reads its recorded outcome and does not launch a second send. Sending leases expire into ambiguity after one minute; unsent reservations expire after five minutes. Both retain quota history.

The recovery RPC is service-only. It binds the exact hook, payload, attempt, expected revision, bounded evidence text and its SHA-256. Evidence must use the declared trusted source and contain only seven permitted reference/outcome fields. Accepted and delivered are distinct. Confirmed not-sent, failed and expired return distinct fixed error codes. Terminal contradictions, stale revisions, wrong provider-message hashes, extra private fields and cross-attempt evidence are rejected. Every successful reconciliation appends immutable evidence. The SQL evidence hash proves integrity, **not provider authenticity**: the trusted operator must independently verify the provider status before invoking recovery. The implementation adds no provider webhook or fabricated delivery receipt.

Only reference hashes, outcome, revision and timestamps are stored for this workflow. Raw OTP, phone, provider token, signature and provider response body are not stored in the reservation or evidence tables and are not logged or returned. Hook errors use an explicit fixed-code allowlist and the documented `{error:{http_code,message}}` response contract. Successful responses remain `{}`.

## Verification captured here

`verification.json` binds **50 source/dependency files**, unchanged before/after these commands, and Deno 2.5.6, Bun, Python and Ruby binary/version evidence:

- **53 OTP Deno tests passed:** signed/key-rotation/stale hook handling; eight simultaneous same-hook calls with one send and one charge; lost begin/completion acknowledgements; accepted/delivered/not-sent/failed/expired outcomes; changed bodies and malformed durable receipts; provider errors/timeouts/body limits; never-resolving transport, body and RPC waits; redaction.
- **55 existing mocked HTTP tests passed:** 45 general Edge cases and 10 roster cases. This run uses the existing Bun host/dependency adapter because standalone `tsc` is unavailable.
- **16 existing static integration checks passed.** These are source checks, not runtime acceptance.
- Actual OTP entry point and tests typechecked against **Supabase JS 2.112.0**, using the frozen packet `sdk.lock`; OTP lint and formatting passed.
- Concurrency Ruby source passed syntax validation. The guarded upgrade SQL emitter succeeded. No database/provider mutation was executed by this worker.

Initial Deno 2.9.6 logs and pinned attempts are preserved. Pinned attempt 2 failed two outdated test expectations after the implementation began distinguishing failed/expired from not-sent; corrected expectations pass in `pinned-validation/`. The previous staged-v2 SQL is preserved under `sources/`, with SHA-256 `c053dde0c0ba93d0d8d342c1b0a285fd5d1fbb16e58bd2a8fdae5a6fea58a8f6`, matching the imported Drive inventory. Its active old installer now fails closed so it cannot later overwrite v3 fencing.

## Root-owned local database steps still required

1. Back up and verify the exact `collect_fin_concurrency_qa_20260929` fixture after migration 144. Apply 145 with the ordinary installer role and record the registry entry and source hash. Verify that unrelated application data is unchanged and the fresh quota policy is disabled/unconfigured.
2. Run `scripts/tests/signed_otp_recovery_uat.sql` with the explicit fixture binding `SET collect.otp_qa_fixture='collect_fin_concurrency_qa_20260929'`. It uses a transaction and rolls back; capture full before/after table fingerprints and actual assertion count.
3. Emit the staged-v2 upgrade/reapply rollback SQL with `scripts/tests/signed_otp_recovery_upgrade_uat.py --emit-source-only --migration-sha256 <verified-current-SHA>`, then execute it on that exact fixture with the same binding. It temporarily recreates only OTP objects inside its rollback transaction, preserves historical acceptance/unknown outcomes and quota, and checks reapply identity preservation.
4. Run the concurrency harness only after registry 145, with `--execute-local145`, the exact `COLLECT_OTP_MIGRATION_SHA`, and a new `COLLECT_OTP_CHECKPOINT` path. It verifies actual two-session blocking for duplicate reservation/begin, accepted-versus-ambiguous completion, contradictory delivery/failure recovery, final global quota slot and stale repeatable-read snapshots. It requires providers/cron disabled, records owned rows/XIDs and full application fingerprints before mutation, and checks data restoration inside its cleanup transaction before commit. Sequences are explicitly not restored.
5. Include these sources in the final clean/populated migration-set rehearsal and broader local acceptance record. No SQL runtime, real WhatsApp delivery or production readiness is claimed by this packet.

## Safe operating procedure

- For a repeated signed hook, inspect its exact durable state; do not resend its payload.
- For accepted/delivered, replay may acknowledge the existing outcome.
- For sending/ambiguous, retain the reservation and reconcile only independently verified provider evidence bound to its attempt. If authoritative evidence is unavailable, leave ambiguity intact.
- For proven not-sent/failure/expiry, finish this hook terminally. A user-initiated fresh OTP request must arrive as a new signed hook and consumes a new quota reservation.
- Disable the private policy to stop new begins while retaining accepted/outcome evidence. Do not delete unknown attempts to reopen quota.

## Primary contract references

Supabase documents the empty successful Send SMS response in [Send SMS Hook](https://supabase.com/docs/guides/auth/auth-hooks/send-sms-hook). Its [Auth Hooks error and timeout contract](https://supabase.com/docs/guides/auth/auth-hooks#error-handling) specifies the nested error object and five-second HTTP hook deadline. Meta's official [Statuses Object reference](https://www.postman.com/meta/whatsapp-business-platform/folder/fuaee8l/statuses-object) treats sent, delivered and failed as separate message statuses. These references were checked on 2026-09-30; the implementation deliberately treats the send API response as acceptance and requires independent status evidence for delivery.
