# Collect periodic jobs on Supabase Cloud

The Cloud scheduler dispatches to
`https://rrlduytparvsjfmegalh.supabase.co/functions/v1/collect-jobs`.
It sends a time-limited HMAC covering the project, source, dispatch ID and
expiry. The Edge Function verifies the signature and claims the exact stored
payload once before processing. Keep the signing key in Supabase Edge secrets
and the corresponding Vault entry. The database stores a digest of the final
reply against the original dispatch.

Start with the managed release tools in `scripts/supabase/cloud-release/`.

| Tool | Purpose |
| --- | --- |
| `managed-jobs-scheduler.mjs` | Render the Cloud scheduler and read back its source hashes without connecting |
| `managed-jobs-key-operator.mjs` | Bind the signing key and reviewed Cloud function source to the scheduler |
| `managed-jobs-operator.mjs` | Inspect, pause, configure, probe, reconcile or activate the reviewed Cloud scheduler |

The source under this directory includes the SQL template used by that
renderer and an isolated PostgreSQL test fixture. The Cloud installation starts
inactive. The active schedule and runtime gates come from the exact deployed
migration and live readback.

## Modes and private server configuration

| `COLLECT_JOBS_MODE` | Readiness file format | Receipt pause | Required request contracts |
| --- | --- | --- | --- |
| `maintenance_only` (default) | `collect.jobs.readiness.v1` | `true` | None |
| `receipt_processing_v1` | `collect.jobs.readiness.v2` | `false` | `processing_admission` |
| `notification_delivery_v1` | `collect.jobs.readiness.v3` | `true` | `notification_admission` |
| `receipt_and_push_v1` | `collect.jobs.readiness.v3` | `false` | Both independent contracts |

Receipt admission additionally requires `BUILD_SOURCE_ID`,
`COLLECT_JOBS_PROCESSING_APPROVAL_SHA256`, `MOMO_AI_MODEL`,
`MOMO_AI_ENABLED=true`, the existing private `OPENAI_API_KEY`, and the actual
extractor adapter. Push admission additionally requires `BUILD_SOURCE_ID`,
`COLLECT_JOBS_PUSH_APPROVAL_SHA256`, `COLLECT_PUSH_ENABLED=true`,
`COLLECT_PUSH_ADMITTED_FROM`, `FCM_PROJECT_ID`, `FCM_ANDROID_PACKAGE`, and private
`FCM_SERVICE_ACCOUNT_JSON`. The source, approval, model/project/package and event
lower bound must match the request exactly. No credential belongs in a readiness
file. Both providers remain inactive until the corresponding current-source
review, deployment, probe and activation have been completed.

The FCM channel covers the existing Android contribution event, using the
current v2 recipient/event contract and generic notification text. FCM acceptance
does not prove device delivery. Contribution email, iOS/APNs and the separate
assisted SMS/native-device lifecycle are not implemented or activated by this
scheduler. Existing auth/Admin SMTP delivery is not contribution-email delivery.

## Dispatch reconciliation

Keep the original dispatch ID for reconciliation. A scheduled SQL call or HTTP
request ID confirms queueing. Confirmation requires the authenticated response
and its matching digest. Pause and reconcile an unresolved outcome before a
new dispatch. The scheduler retains uncertainty while business lanes keep their
own durable receipt, ledger and delivery state.

## Separate receipt email

The [email scheduler](EMAIL.md) is a separately gated Cloud lane for opted-in
contribution receipts.

## Local qualification

```sh
COLLECT_JOBS_TEST_DATABASE_URL=PRIVATE_LOOPBACK_FIXTURE_URL \
COLLECT_PG_MODULE=ABSOLUTE_EXISTING_PG_MODULE \
node --test scripts/supabase/jobs_test.mjs
```

The scheduler test runner permits the existing `127.0.0.1`/`localhost:55439`
fixture or, with explicit `COLLECT_CI_SYNTHETIC=true`, literal `127.0.0.1` on an
owned alternative port with exact `collect_test` user and `collect_jobs_test`
database. It never broadens the production connection validator. The runtime
delivery regression uses its separate exact
`COLLECT_NOTIFICATION_DELIVERY_TEST_DATABASE_URL` loopback database. It is
mandatory when that suite is selected; absence never silently skips it.

The scheduler tests execute real PostgreSQL transactions, ACLs, durable state,
inactive predecessor upgrade, source/approval admission and multiple connections.
**Cron, Vault and pg_net are explicit SQL interface doubles**: no local HTTP
worker, encrypted Vault, native extension or hosted scheduling behavior is
established. Reset fixtures recreate only their synthetic transport objects and
owned sequence. They do not restart a shared server or establish native crash
recovery. The delivery suite executes actual worker/SQL/RLS/source-fence logic
with synthetic OAuth/FCM responses. It covers authority changes during OAuth,
privacy barriers, lease recovery, commit acknowledgement loss, concurrent
claims, bounded retries, terminal uncertainty and retained-copy/health inventory.
Hosted native-extension, credential, Android delivery, endpoint, copy-inventory,
capacity and quota gates remain outstanding.
