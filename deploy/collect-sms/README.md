# OpenSMS on self-hosted Supabase

This is the PostgreSQL and Supabase Edge port of the owner's OpenSMS v0.3 source. It retains the inspected application, device, staff, OTP, campaign, template, schedule, callback, metrics, history and content-redaction APIs. It contains no D1 database, Cloudflare deployment binding or second business backend.

## Source and scope

The Drive archive is `1j5Xg6iMIYilauzBkIaFCIUc9v07UnInn`, SHA-256 `fbb65c024d8b1c1340245ea0014d525f7b1e2009910598e34de56c2ca0eb4909`. `upstream/provenance.json` records each original TypeScript and migration digest. Original migrations are retained under `upstream/migrations`; `tools/port_schema.py` deterministically generates `supabase/migrations/20261101012503_collect_sms_gateway.sql`. The original license is retained.

The port changes imports, storage, SQL compatibility and runtime hosting. Device identity, assignment versions, payload digests, event IDs, idempotency keys, public response fields and Android handoff semantics are preserved. The Android sender remains the phone/radio endpoint. Supabase holds every durable gateway record.

## Database contract

The private `collect_sms` schema contains 29 tables and the `attempt_evidence` view. All 25 distinct upstream trigger definitions are preserved, including multipart evidence, no suppression after handoff/unknown, OTP limits, callback outbox generation, immutable source facts and no content rehydration. The evidence view uses `security_invoker=true` so forced RLS does not silently hide delivery evidence.

`collect_sms_runtime` is a non-login, non-superuser role without RLS bypass. REST roles and `collect_runtime` receive no schema access. The installer provisions a distinct login that can set this role, represented by `COLLECT_SMS_DATABASE_URL`. No HTTP route accepts SQL or credentials. The adapter bounds queued transactions, parameters, statement size and timeouts. It acquires one PostgreSQL advisory transaction lock before its first query, preserving the source's serial write ordering for limits, device assignment, campaign budgets and multi-statement guards. Statement triggers also serialize direct internal writes. A future scalability change must preserve these ordering guarantees and rerun concurrency qualification.

Database TLS requires certificate verification and the exact database hostname. `COLLECT_DB_CA_PEM` supplies the private CA. Plain loopback transport is accepted only by the explicit synthetic fixture constructor. Production does not disable certificate verification.

## Source, epoch and work admission

`20261101030502_collect_sms_application_fence.sql` adds narrow gateway-only work functions and the immutable `private.collect_sms_fence_admissions` ownership map. Each HTTP request and maintenance invocation registers against the actual deployment profile, current Collect source and epoch. It holds the existing shared WORK lease while local work remains active. Every database batch, including reads, checks that original admission; every gateway mutation trigger also checks the original tuple under the shared WRITE lock. A cached profile check or the gateway's serial writer lock cannot authorize a new request during quiesce or after a source change.

The gateway login receives no general application/runtime/owner privilege. Its functions cannot inspect or close another lane's admission. Original admitted work may finish in quiescing mode; new health, API and maintenance work is refused. Callback/FCM fetches and deferred work remain attached to the original admission, and uncertain outcomes retain their counters. Lost registration or close acknowledgements do not cause a replacement registration or blind close replay.

These controls establish local process and database admission. A physical phone can still hold an already acknowledged job, and external callbacks or FCM can have an unknown result. Local completion does not settle those obligations. An operator must pause device dispatch and reconcile the retained phone/provider evidence as part of cutover and recovery; the gateway does not infer physical settlement from a stopped process or elapsed timeout.

## Runtime and dormant defaults

`supabase/functions/collect-sms/index.ts` starts the dedicated Edge handler. Requests under `/functions/v1/collect-sms/` retain their original `/v1/…` paths. `src/edge.ts` exports an importable factory for host integration.

Production defaults are `COLLECT_SMS_ENABLED=false`, `DISPATCH_PAUSED=true`, `FCM_ENABLED=false` and `RETENTION_AUTO_PURGE=false`. Enabling requires the verified self-hosted profile, a build source hash, an explicit gateway approval digest, a distinct database URL and strong root/HMAC secrets. The optional maintenance endpoint requires a separate maintenance token; an application or device token cannot invoke it. Actual activation and device/provider qualification are operator actions outside local implementation tests.

| Setting | Purpose |
| --- | --- |
| `COLLECT_SMS_DATABASE_URL`, `COLLECT_DB_CA_PEM` | Gateway-only PostgreSQL login and verified TLS CA |
| `COLLECT_SMS_ENABLED`, `COLLECT_SMS_APPROVAL_SHA256`, `BUILD_SOURCE_ID` | Explicit deployment enablement and reviewed source/approval identity |
| `COLLECT_DEPLOYMENT_PROFILE`, `COLLECT_DEPLOYMENT_PROFILE_SHA256` | Canonical public deployment identity |
| `ROOT_ADMIN_TOKEN`, `OTP_HMAC_KEY` | High-entropy bootstrap capability and OTP verifier HMAC secret |
| `DISPATCH_PAUSED`, `OTP_REQUIRE_READY_GATEWAY`, `OTP_SEGMENT_INTERVAL_MS`, `REQUIRE_ACTUAL_PARTS` | Dispatch admission and device evidence requirements |
| `FCM_ENABLED`, `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY` | Optional payload-free Android wake transport |
| `CALLBACK_ENCRYPTION_KEY`, `CALLBACK_ALLOWED_HOSTS` | Dedicated **64-hex-character** encryption key and explicit HTTPS callback hosts |
| `MESSAGE_RETENTION_DAYS`, `RETENTION_AUTO_PURGE` | Optional bounded content minimization; retained identity/evidence is preserved |
| `COLLECT_SMS_MAINTENANCE_TOKEN` | Separate protected maintenance admission |

The browser never receives these secrets. OTP and contribution receipts require separate application identities, allowed kinds and tokens. OTP accepts only `otp`; the receipt application accepts only `receipt`. Both need `messages:write` and `messages:read` for immutable submission and readback. Permission to administer applications does not establish recipient consent or authorize a Collect receipt.

## Collect receipt adapter

`supabase/functions/_shared/opensms-receipts.js` implements the actual OpenSMS HTTP contract, including the UTF-8 length-prefixed payload digest. It issues one POST with the retained deterministic message ID and a key below 128 characters, then reads that original ID. A lost result is unknown. Reconciliation only issues GET and never creates a replacement message.

The Admin gateway adapter uses a short-lived one-use grant returned only with the first acknowledged send start. The database stores its hash, original attempt, exact application/message identity and expiry. Final dispatch rechecks the live policy, consent, payment/ledger source, hashes, privacy barrier and exact recent-email proof. An accepted gateway job is not a confirmed phone send, provider settlement or verified recipient delivery.

## Privacy, backups and restore

`external:collect_sms` is an explicit blocked copy class in the Collect retention inventory. There is no approved principal-to-gateway erasure selector. Raw bodies/recipients, OTP verifier and replay records, staff/app credentials, schedules, source snapshots, callbacks and device evidence remain covered by that unresolved inventory. Android queues, the Android system SMS store, carrier records and FCM infrastructure are additional copies. A zero subject count in `app` or `private` cannot establish absence in this schema.

Encrypted backups and restore rehearsals must include `collect_sms` tables, the invoker view, indexes, trigger functions, RLS policies, least-privilege grants and the private gateway work-ownership map. That map is an explicit blocked shared operational copy. Content minimization preserves uncertain jobs and immutable replay identities. A redacted body cannot be silently recreated or sent to a new recipient through an old source event.

## Local verification

The ported original API/Android suite plus six added PostgreSQL cases passes 34 tests on the isolated PostgreSQL 17 fixture. The added cases cover private schema access, template version immutability, schedule eligibility/concurrency, staff rotation, retention/no rehydration, immutable ledger snapshots and callback generations. No real phones, carrier submissions, FCM credentials or callback destinations are used.

The maintained test runner requires `COLLECT_CI_SYNTHETIC=true`, `COLLECT_SELFHOST_NATIVE_PROFILE=reviewed_current_self_hosted` and `COLLECT_SMS_FIXTURE_FILE` naming the expressly provisioned fresh original16 fixture. It installs the reviewed current additions exactly once, verifies the loopback host/database/normal owner, reaches the real inactive fence before binding its qualification profile, and runs under an actual gateway work admission. There is no schema-drop or reset path. The separate `scripts/supabase/testing/gateway-fence.ts` uses another fresh database and an actual restricted login to test source/profile refusal, mutation guards, held work, quiesce, unknown callback/FCM results, source upgrade and original-acknowledgement recovery. Its provider boundaries are explicit doubles and its evidence states the exact source/migration scope. Never point these runners at a deployment. These checks do not replace an actual device, reverse-proxy, native scheduler-extension or restore rehearsal.
