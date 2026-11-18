# OpenSMS on managed Supabase Cloud

This is the PostgreSQL and Supabase Edge port of the owner's OpenSMS v0.3 source. It retains the inspected application, device, staff, OTP, campaign, template, schedule, callback, metrics, history and content-redaction APIs. It contains no D1 database, Cloudflare deployment binding or second business backend.

## Source and scope

The Drive archive is `1j5Xg6iMIYilauzBkIaFCIUc9v07UnInn`, SHA-256 `fbb65c024d8b1c1340245ea0014d525f7b1e2009910598e34de56c2ca0eb4909`. `upstream/provenance.json` records each original TypeScript and migration digest. Original migrations are retained under `upstream/migrations`; `tools/port_schema.py` deterministically generates `supabase/migrations/20261101012503_collect_sms_gateway.sql`. The original license is retained.

The port changes imports, storage, SQL compatibility and runtime hosting. Device identity, assignment versions, payload digests, event IDs, idempotency keys, public response fields and Android handoff semantics are preserved. The Android sender remains the phone/radio endpoint. Supabase holds every durable gateway record.

## Database contract

The private `collect_sms` schema contains 29 tables and the `attempt_evidence` view. All 25 distinct upstream trigger definitions are preserved, including multipart evidence, no suppression after handoff/unknown, OTP limits, callback outbox generation, immutable source facts and no content rehydration. The evidence view uses `security_invoker=true` so forced RLS does not silently hide delivery evidence.

`collect_sms_runtime` is a non-login, non-superuser role without RLS bypass. REST roles and `collect_runtime` receive no schema access. The Edge function connects as `collect_sms_edge_login`, which can explicitly set the runtime role and has no inherited runtime privileges. No HTTP route accepts SQL or database credentials. The adapter bounds queued transactions, parameters, statement size and timeouts. It acquires one PostgreSQL advisory transaction lock before its first query, preserving the source's serial write ordering for limits, device assignment, campaign budgets and multi-statement guards. Statement triggers also serialize direct internal writes.

The dedicated DSN accepts the production project's exact direct database host or its pinned session-pooler host on port 5432. The pooler username carries the project reference. The PostgreSQL driver verifies the TLS certificate and server name. `COLLECT_SMS_DATABASE_CA_PEM` accepts the gateway's pinned CA. When unset, the gateway can use the shared `COLLECT_DB_CA_PEM` or the driver's trusted roots.

## Source, epoch and work admission

`20261101030502_collect_sms_application_fence.sql` adds narrow gateway-only work functions and the immutable `private.collect_sms_fence_admissions` ownership map. Each HTTP request and maintenance invocation registers against the actual deployment profile, current Collect source and epoch. It holds the existing shared WORK lease while local work remains active. Every database batch, including reads, checks that original admission; every gateway mutation trigger also checks the original tuple under the shared WRITE lock. A cached profile check or the gateway's serial writer lock cannot authorize a new request during quiesce or after a source change.

The gateway login receives no general application/runtime/owner privilege. Its functions cannot inspect or close another lane's admission. Original admitted work may finish in quiescing mode; new health, API and maintenance work is refused. Callback/FCM fetches and deferred work remain attached to the original admission, and uncertain outcomes retain their counters. Lost registration or close acknowledgements do not cause a replacement registration or blind close replay.

These controls establish application and database admission. A phone can still hold an acknowledged job, and callbacks or FCM can have an unknown result. During cutover or recovery, pause new dispatch and reconcile the original phone and provider evidence. The gateway never replays a message to resolve an uncertain outcome.

## Runtime and dormant defaults

`supabase/functions/collect-sms/index.ts` starts the dedicated Supabase Edge handler. The function accepts its exact project authority and routes under `/functions/v1/collect-sms/` or `/collect-sms/`. Supabase JWT verification is disabled for this function so the gateway can verify its own scoped application, device and operator credentials. Browser calls also undergo the gateway's configured origin check.

The default settings keep the gateway disabled and device dispatch paused. FCM and automatic content purging default to off. Enabling the gateway requires the canonical managed profile, reviewed core and gateway release digests, explicit approval and dedicated PostgreSQL and gateway credentials.

| Setting | Purpose |
| --- | --- |
| `COLLECT_SMS_DATABASE_URL`, `COLLECT_SMS_DATABASE_CA_PEM` | Gateway-only PostgreSQL login and trusted TLS CA |
| `COLLECT_SMS_ENABLED`, `COLLECT_SMS_APPROVAL_SHA256` | Explicit enablement and separate release approval digest |
| `BUILD_SOURCE_ID`, `COLLECT_SMS_CORE_SOURCE_SHA256`, `COLLECT_SMS_RELEASE_SHA256` | Active core source, its required exact match and reviewed gateway release |
| `SUPABASE_URL`, `APP_ENVIRONMENT`, `COLLECT_DEPLOYMENT_PROFILE`, `COLLECT_DEPLOYMENT_PROFILE_SHA256` | Canonical managed project and environment |
| `COLLECT_SMS_ROOT_ADMIN_TOKEN`, `COLLECT_SMS_OTP_HMAC_KEY` | Distinct high-entropy bootstrap and OTP verifier secrets |
| `COLLECT_SMS_DISPATCH_PAUSED`, `OTP_REQUIRE_READY_GATEWAY`, `OTP_SEGMENT_INTERVAL_MS`, `REQUIRE_ACTUAL_PARTS` | Dispatch admission and device evidence requirements |
| `COLLECT_SMS_FCM_ENABLED`, `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY` | Optional payload-free Android wake transport |
| `CALLBACK_ENCRYPTION_KEY`, `CALLBACK_ALLOWED_HOSTS` | Dedicated **64-hex-character** encryption key and explicit HTTPS callback hosts |
| `MESSAGE_RETENTION_DAYS`, `COLLECT_SMS_RETENTION_AUTO_PURGE` | Optional bounded content minimization with retained identity and evidence |
| `COLLECT_SMS_MAINTENANCE_TOKEN` | Separate protected maintenance admission |

Once enabled, `GET /health` exposes basic liveness. Operators can use the bootstrap bearer token with `GET /internal/readiness` to verify the active profile/source admission, restricted role, relation grants and transport settings without reading gateway records or contacting a device. `POST /internal/maintenance` requires the separate maintenance token and is optional. Readiness leaves dispatch settings as configured.

The browser never receives these secrets. OTP and contribution receipts require separate application identities, allowed kinds and tokens. OTP accepts only `otp`; the receipt application accepts only `receipt`. Both need `messages:write` and `messages:read` for immutable submission and readback. Permission to administer applications does not establish recipient consent or authorize a Collect receipt.

## Collect receipt adapter

`supabase/functions/_shared/opensms-receipts.js` implements the actual OpenSMS HTTP contract, including the UTF-8 length-prefixed payload digest. It issues one POST with the retained deterministic message ID and a key below 128 characters, then reads that original ID. A lost result is unknown. Reconciliation only issues GET and never creates a replacement message.

The Admin gateway adapter uses a short-lived one-use grant returned only with the first acknowledged send start. The database stores its hash, original attempt, exact application/message identity and expiry. Final dispatch rechecks the live policy, consent, payment/ledger source, hashes, privacy barrier and exact recent-email proof. An accepted gateway job is not a confirmed phone send, provider settlement or verified recipient delivery.

## Privacy, backups and restore

`external:collect_sms` is an explicit blocked copy class in the Collect retention inventory. There is no approved principal-to-gateway erasure selector. Raw bodies/recipients, OTP verifier and replay records, staff/app credentials, schedules, source snapshots, callbacks and device evidence remain covered by that unresolved inventory. Android queues, the Android system SMS store, carrier records and FCM infrastructure are additional copies. A zero subject count in `app` or `private` cannot establish absence in this schema.

Encrypted backups and restore rehearsals must include `collect_sms` tables, the invoker view, indexes, trigger functions, RLS policies, least-privilege grants and the private gateway work-ownership map. That map is an explicit blocked shared operational copy. Content minimization preserves uncertain jobs and immutable replay identities. A redacted body cannot be silently recreated or sent to a new recipient through an old source event.

## Verification

Run the frozen Deno Edge tests from the repository root.

```sh
deno test --cached-only --frozen --allow-env --config=supabase/functions/deno.json --lock=supabase/functions/deno.lock deploy/collect-sms/test/edge.test.ts
```

The suite exercises routed HTTP admission, scoped authentication, paused dispatch and readiness using synthetic database and fence responses. Run the receipt-guard regression with `node --experimental-transform-types --test --test-isolation=none deploy/collect-sms/test/ledger_snapshot_receipt_guard.test.mjs` to verify replay conflicts and rejection of new zero-valued contribution receipts.

The retained original API and Android parity evidence covers 34 historical isolated PostgreSQL tests, including schema grants, staff rotation, retention, scheduling and callback transitions. Live commissioning additionally requires the deployed readiness check and separately authorized phone and provider verification.
