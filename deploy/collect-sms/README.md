# OpenSMS application and PostgreSQL schema

This package contains the OpenSMS application, PostgreSQL adapter and request
handler for the `collect-sms` Supabase Edge Function. Its entry point is
[`supabase/functions/collect-sms/index.ts`](../../supabase/functions/collect-sms/index.ts).
The separate [receipt-only Worker fixture](../managed-sms/README.md) shares the
application and SQL compiler.

## Source and scope

The Drive archive is `1j5Xg6iMIYilauzBkIaFCIUc9v07UnInn`, SHA-256 `fbb65c024d8b1c1340245ea0014d525f7b1e2009910598e34de56c2ca0eb4909`. `upstream/provenance.json` records each original TypeScript and migration digest. Original migrations are retained under `upstream/migrations`; `tools/port_schema.py` deterministically generates `supabase/migrations/20261101012503_collect_sms_gateway.sql`. The original license is retained.

The port changes imports, storage, SQL compatibility and runtime hosting. Device identity, assignment versions, payload digests, event IDs, idempotency keys, public response fields and Android handoff semantics are preserved. The Android sender remains the phone/radio endpoint. Supabase holds every durable gateway record.

## Database contract

The private `collect_sms` schema contains 29 tables and the `attempt_evidence` view. All 25 distinct upstream trigger definitions are preserved, including multipart evidence, no suppression after handoff/unknown, OTP limits, callback outbox generation, immutable source facts and no content rehydration. The evidence view uses `security_invoker=true` so forced RLS does not silently hide delivery evidence.

`collect_sms_runtime` is a non-login, non-superuser role without RLS bypass. REST roles and `collect_runtime` receive no schema access. The managed integration uses a dedicated login with permission to set this role. No HTTP route accepts SQL or credentials. The adapter bounds queued transactions, parameters, statement size and timeouts. It acquires one PostgreSQL advisory transaction lock before its first query, preserving the source's serial write ordering for limits, device assignment, campaign budgets and multi-statement guards. Statement triggers also serialize direct internal writes. A future scalability change must preserve these ordering guarantees and rerun concurrency qualification.

[`gateway-connection.ts`](src/gateway-connection.ts) validates the dedicated
SMS login and pins the TLS server name. [`gateway-runtime.ts`](src/gateway-runtime.ts)
requires the managed deployment profile, source identity and explicit gateway
enablement. [`edge.ts`](src/edge.ts) handles the existing function paths and
holds the original admission through response completion. Dispatch defaults
to paused and FCM and automatic retention purge default to off.

## Source, epoch and work admission

`20261101030502_collect_sms_application_fence.sql` adds narrow gateway-only work functions and the immutable `private.collect_sms_fence_admissions` ownership map. Each HTTP request and maintenance invocation registers against the actual deployment profile, current Collect source and epoch. It holds the existing shared WORK lease while local work remains active. Every database batch, including reads, checks that original admission; every gateway mutation trigger also checks the original tuple under the shared WRITE lock. A cached profile check or the gateway's serial writer lock cannot authorize a new request during quiesce or after a source change.

The gateway login receives no general application/runtime/owner privilege. Its functions cannot inspect or close another lane's admission. Original admitted work may finish in quiescing mode; new health, API and maintenance work is refused. Callback/FCM fetches and deferred work remain attached to the original admission, and uncertain outcomes retain their counters. Lost registration or close acknowledgements do not cause a replacement registration or blind close replay.

These controls establish application and database admission. A phone can still hold an acknowledged job, and callbacks or FCM can have an unknown result. During cutover or recovery, pause new dispatch and reconcile the original phone and provider evidence. The gateway never replays a message to resolve an uncertain outcome.

OTP and contribution receipts require separate application identities, allowed kinds and tokens. OTP accepts only `otp`; the receipt application accepts only `receipt`. Both need `messages:write` and `messages:read` for immutable submission and readback. Permission to administer applications does not establish recipient consent or authorize a Collect receipt.

## Collect receipt adapter

`supabase/functions/_shared/opensms-receipts.js` implements the actual OpenSMS HTTP contract, including the UTF-8 length-prefixed payload digest. It issues one POST with the retained deterministic message ID and a key below 128 characters, then reads that original ID. A lost result is unknown. Reconciliation only issues GET and never creates a replacement message.

The Admin gateway adapter uses a short-lived one-use grant returned only with the first acknowledged send start. The database stores its hash, original attempt, exact application/message identity and expiry. Final dispatch rechecks the live policy, consent, payment/ledger source, hashes, privacy barrier and exact recent-email proof. An accepted gateway job is not a confirmed phone send, provider settlement or verified recipient delivery.

## Privacy, backups and restore

`external:collect_sms` is an explicit blocked copy class in the Collect retention inventory. There is no approved principal-to-gateway erasure selector. Raw bodies/recipients, OTP verifier and replay records, staff/app credentials, schedules, source snapshots, callbacks and device evidence remain covered by that unresolved inventory. Android queues, the Android system SMS store, carrier records and FCM infrastructure are additional copies. A zero subject count in `app` or `private` cannot establish absence in this schema.

Encrypted backups and restore rehearsals must include `collect_sms` tables, the invoker view, indexes, trigger functions, RLS policies, least-privilege grants and the private gateway work-ownership map. That map is an explicit blocked shared operational copy. Content minimization preserves uncertain jobs and immutable replay identities. A redacted body cannot be silently recreated or sent to a new recipient through an old source event.

## Verification

From the repository root, run the frozen Deno gateway suite for routing,
readiness and authentication with synthetic database responses. Run the
receipt regression for amount and replay behavior. The separate
[Worker tests](../managed-sms/README.md) exercise SQL transactions on an owned
PostgreSQL fixture.

```sh
deno test --frozen --allow-env --config=supabase/functions/deno.json --lock=supabase/functions/deno.lock deploy/collect-sms/test/edge.test.ts
node --experimental-transform-types --test deploy/collect-sms/test/ledger_snapshot_receipt_guard.test.mjs
```
