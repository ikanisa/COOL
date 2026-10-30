# Collect periodic jobs — maintenance by default, inactive installation

This is a separate operator installation, not part of the curated application migration. No hosted extension, Vault secret, schema or job was installed while preparing it. Receipt work reuses the existing PostgreSQL MoMo outbox, row claims, lease tokens and attempt budget. The separately admitted Android FCM lane uses the private delivery obligations added by SQL16. The scheduler journal records wake-ups; each business lane retains its own durable state. No pgmq is installed.

`config.json` pins project `rrlduytparvsjfmegalh`, `POST https://rrlduytparvsjfmegalh.supabase.co/functions/v1/collect-jobs`, the original opaque `dispatch_id`, `Content-Type: application/json`, and `Authorization: Bearer <Vault value named collect_job_token_v1>`. The deployed function uses custom job-token admission with `verify_jwt=false`; member/Admin credentials do not authorize this endpoint. The worker still requires its normal private runtime/database/storage bindings. `config.json` describes the base request with `request.body_template`; SQL substitutes its original durable UUID and includes only the independently admitted processing/notification contracts. The authenticated response must echo the exact UUID and contracts before it can be confirmed.

The handler runs bounded expired Google ciphertext cleanup (`limit=100`) in every admitted mode. Cleanup only terminalizes expired pending/exchanging/ready Google flows and clears their ciphertext; it does not delete Auth accounts, session history, financial evidence, consent or raw receipt records. Diagnostic expiry is a separate bounded maintenance observation; diagnostic failure cannot turn a confirmed business drain into an unconfirmed one.

`maintenance_only` is the default. Receipt processing drains at most one due job per invocation only after exact source/model/approval admission. Android push performs at most one message attempt only after its independent source/project/package/start/approval admission. Flipping `MOMO_PROCESSING_PAUSED` or `COLLECT_PUSH_ENABLED` alone cannot enable either lane. See [PROCESSING_CONTRACTS.md](PROCESSING_CONTRACTS.md) for state transitions, retry/uncertainty semantics, provider protocol and current-source qualification limits.

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

## Provider references recorded 2026-10-20

These are dated research inputs. Reverify current provider versions, limits and
pricing before activation; this repository artifact is not current hosted usage
or quota evidence.

- Supabase documents Cron plus asynchronous `pg_net` for Edge Function invocation and recommends Vault for the credential. The public Cron command here contains only `SELECT collect_ops.tick_jobs();`. [Scheduling Edge Functions](https://supabase.com/docs/guides/functions/schedule-functions)
- Cron uses `pg_cron`. Supabase recommends at most eight concurrent jobs and less than ten minutes per job. This installation has one short SQL dispatcher; it awaits no HTTP inside a database transaction. [Cron](https://supabase.com/docs/guides/cron)
- `pg_net` starts requests after transaction commit. Its queue and responses are unlogged and can disappear after a crash; the queue's owned sequence may reset too. Default response retention is six hours. Its API is beta, so installation verifies the actual signatures rather than assuming compatibility. [pg_net](https://supabase.com/docs/guides/database/extensions/pg_net), [official queue definition](https://github.com/supabase/pg_net/blob/master/sql/pg_net.sql), [unlogged table and sequence behavior](https://www.postgresql.org/docs/17/sql-createtable.html)
- Vault encrypts stored secrets and decrypts them through a privileged view. It does not conceal a live outbound Authorization header from privileged database operators or the HTTP transport queue. [Vault](https://supabase.com/docs/guides/database/vault)
- Free includes 500,000 function invocations; responses with errors also consume invocation usage. Five-minute dispatch is 288 calls/day, at most 8,928 per 31-day month (about 1.8% of that allowance). The independent 10,000 scheduler ceiling includes probes and leaves the application's other calls outside this ceiling. [Invocation usage](https://supabase.com/docs/guides/platform/manage-your-usage/edge-function-invocations)
- Hosted Free function limits are 150 seconds wall time, 2 seconds CPU and 256 MB. The HTTP deadline here is 120 seconds, and missing replies become unconfirmed after 180 seconds. [Function limits](https://supabase.com/docs/guides/functions/limits)
- Free has 500 MB database, shared compute, no uptime SLA, and inactivity pausing. Cron is not a guarantee of availability, an exemption from pausing or a backup strategy. [Pricing](https://supabase.com/pricing)

## Activation procedure

1. Retain independent deployment evidence for the exact function bundle, selected mode and required runtime configuration. Verify the target project is running, the exact adopted schema is applied, wrong-token/method/path requests are denied, and the receipt pause value matches the selected mode. Keep maintenance-only unless the separate receipt/push admission has been reviewed. Before activation, retain proof that the superseded Cloudflare scheduler and backend writers are fenced or disabled under the cutover plan; a new Cron schedule does not retire them. Keep the deployed `COLLECT_JOB_TOKEN` in the owner's existing private custody. This tooling never reads the owner's private token file.
2. Through the authorized Vault UI, provision the **same** credential under `collect_job_token_v1`. Do not put it in SQL literals, saved snippets, Git, shell arguments, generated SQL or logs. This installer neither accepts a token argument nor provisions a Vault secret. Rotation starts by deactivating this schedule, updating the Edge secret and Vault through approved private channels, then repeating the probe.
3. Verify/install `pg_cron`, `pg_net` and `supabase_vault` separately through approved provider operations. This artifact never installs/drops extensions or changes their objects. `pg_net` is non-relocatable; never drop it to fix access while requests/evidence exist. [Cron installation](https://supabase.com/docs/guides/cron/install)
4. Restrict effective Vault and net access for `anon`, `authenticated`, `service_role`, `collect_runtime` and `collect_importer`: no Vault/net schema usage or transport queue/response table privileges. Otherwise a role could read the bearer header, redirect a queued request or forge a response. The installer and every dispatch fail closed on those privileges. Supabase's default pg_net grants require explicit review; a REVOKE by a non-owner may change nothing. Have the provider-supported owner apply and read back the restriction; do not infer success from a silent REVOKE. [pg_net grant ownership](https://supabase.com/docs/guides/troubleshooting/revoking-access-to-pg_net-objects-has-no-effect-0bbc16)
5. Complete the copy-inventory proposal in `COPY_INVENTORY_PROPOSAL.md`, including the selected provider and retained delivery obligations. Its current state is a blocker to activation, not an approved addition to the retention policy. Prepare an owned regular 0600 readiness JSON outside the repository using `readiness.example.json`, `readiness.processing.example.json`, `readiness.notifications.example.json` or `readiness.combined.example.json` for the selected mode. Replace every placeholder with current reviewed evidence and timestamp. Active modes require independent provider evidence and remaining quotas as specified in [PROCESSING_CONTRACTS.md](PROCESSING_CONTRACTS.md). No token belongs in this evidence file.
6. Supply `COLLECT_JOBS_DATABASE_URL` through the authorized private process environment, pointing to the exact project `postgres` database with verified TLS. `COLLECT_PG_MODULE` may identify the existing Node `pg` dependency. The CLI emits only sanitized state; it never emits driver messages or SQL parameters. Generate/check the public-safe SQL without connecting:

   ```sh
   node scripts/supabase/jobs_config.mjs
   node scripts/supabase/jobs_operator.mjs install-inactive
   ```

7. On an empty installation, after review, `node scripts/supabase/jobs_operator.mjs install-inactive --apply` creates only `collect_ops` objects and an **inactive** Cron entry, in one transaction. For the exact existing maintenance predecessor, use the explicit inactive-upgrade flow below. Both configuration and Cron remain disabled. The owner is the trusted database operator; functions run with invoker permissions and pinned `pg_catalog` search path. No application/client/importer role receives access. Do not hand this operator database login to an Edge Function.
8. Run one explicitly reviewed probe for the selected mode with a retained UUID. A processing probe can perform one receipt attempt; a push probe can perform one provider message attempt; combined mode can perform one of each:

   ```sh
   node scripts/supabase/jobs_operator.mjs probe --readiness /ABSOLUTE/PRIVATE/readiness.json --dispatch-id RETAINED-LOWERCASE-UUID --apply
   node scripts/supabase/jobs_operator.mjs reconcile --apply
   node scripts/supabase/jobs_operator.mjs status
   ```

   The UUID is printed before the attempt. HTTP dispatch occurs only after commit. A request ID and a successful Cron SQL statement are not worker success. Reconciliation requires HTTP 200, an exact string echo of that original dispatch UUID, the current native transport instance, confirmed bounded cleanup, exact admission echoes and bounded outcomes for each admitted lane. Unadmitted lanes must remain paused/disabled. It stores a response digest and safe counts. The original response remains subject to pg_net's own protected custody/TTL.
9. Activate with `node scripts/supabase/jobs_operator.mjs activate --readiness /ABSOLUTE/PRIVATE/readiness.json --apply`. The same evidence must be less than one hour old and the confirmed probe less than 15 minutes old. Vault UUID/update time must still match that probe. Configuration and Cron activation commit together. Repeat `status` and retain provider run/readback evidence. These tools have not performed that hosted verification.

## Exact inactive predecessor upgrade

The upgrade accepts only the pinned maintenance predecessor: configuration
`b2cede1f2c0eea79f31fcb7e731ec816320f24a677954bd19ebbeba5781f5169`
and template `590273dc8710e32c46933d03a9f9e7fcce8ebb0269328f51ef97d82e614d6cd4`.
It refuses an active Cron/configuration, changed job identity or any awaiting or
unconfirmed dispatch. Uncertainty must be reconciled using its original
identity and evidence; the upgrade cannot clear it.

```sh
node scripts/supabase/jobs_operator.mjs status
node scripts/supabase/jobs_operator.mjs deactivate --apply
node scripts/supabase/jobs_operator.mjs reconcile --apply
node scripts/supabase/jobs_operator.mjs status
node scripts/supabase/jobs_config.mjs --upgrade-output /ABSOLUTE/PRIVATE/new-inactive-upgrade.sql
node scripts/supabase/jobs_operator.mjs upgrade-inactive
```

After reviewing the exact generated SQL and resolved original work:

```sh
node scripts/supabase/jobs_operator.mjs upgrade-inactive --apply
node scripts/supabase/jobs_operator.mjs status
```

The one transaction adds immutable dispatch-contract snapshots, replaces the
reviewed scheduler functions and updates their pinned identity. It preserves
the Cron job ID and all dispatch history, clears old readiness/probe admission,
and stays inactive. Prepare fresh v1/v2/v3 readiness, probe and activate using
the procedure above. An interrupted upgrade is checked by its exact installed
identity; the tooling does not drop/recreate the scheduler or replay HTTP.

## Reconciliation and operation

The named Cron entry is case-sensitive. Installation refuses another existing job or configuration drift; it does not silently replace a differently configured schedule. The official API supports `cron.alter_job(..., active := false)`, and jobs execute under their creating database user. [pg_cron source/API](https://github.com/citusdata/pg_cron)

A logged dispatch row survives a lost database reply and the loss of pg_net's unlogged queue. Numeric native request IDs are unique only within a native instance: the journal binds a SHA-256 epoch derived from `pg_postmaster_start_time()` and the queue, response and owned-sequence OIDs. A restart changes the postmaster timestamp; native-object recreation changes its object identity. Before consulting a response, reconciliation marks an awaiting dispatch from an earlier epoch unconfirmed and disables scheduling, even if a recycled native number has a valid-looking reply. The SQL does not alter native tables, sequences or managed extension objects. A reply in the current epoch must still echo the exact original dispatch UUID; a missing, null, non-string or contradictory value cannot acknowledge work. Reuse the original probe UUID to reconcile; never automatically resend under a new UUID. An awaiting reply blocks overlap. After 180 seconds without a receipt, an invalid/non-200 reply or a changed runtime gate, the schedule is disabled and the dispatch remains **unconfirmed**. A timeout does not establish rollback. Existing domain source rows, leases and attempt history remain the authority for work effects; this journal is a wake-up record, not a completion queue.

For unresolved work, retain independent runtime/outbox/lease/provider evidence and wait at least five minutes. An authorized operator may then use `review-unknown --dispatch-id UUID --evidence-sha256 REVIEW_DIGEST --apply`. This records `reviewed_unknown`, never a fabricated success. It leaves scheduling disabled and requires a new reviewed successful probe in the current native instance before activation. A previously confirmed probe from another instance cannot activate the schedule or admit a new scheduled dispatch. Old dispatch rows remain attributed to their original epoch; a new epoch can reuse a numeric request ID without replacing that history. No stored HTTP request is replayed by this action.

Use `deactivate --apply` for an emergency pause. `status`, `reconcile`, `review-unknown` and `deactivate` remain available when strict dependency admission fails and for the exact predecessor; they do not read a Vault credential or enqueue HTTP. Pause prevents future dispatches and cannot cancel an already committed request. Independently pause receipt processing/disable push and reconcile any active domain lease if necessary. A recorded terminal push `unknown` never automatically retries; acknowledgement of that retained uncertainty is not a delivery claim. Lost local commit/journal results remain unconfirmed at the scheduler boundary.

The one Cron tick prunes at most 500 terminal dispatch rows older than 30 days and outside the current UTC month, preserving current-month quota counting and the admission probe. It also prunes at most 500 finished history rows belonging to this Cron job older than seven days. Unconfirmed work is never automatically pruned. Native Cron history otherwise grows without automatic cleanup. [Cron history](https://supabase.com/docs/guides/cron/quickstart)

Observe this job's current receipt, cleanup backlog, durable unknown count, native Cron failures, function health, global usage and database size. A paused database or disabled Cron requires an external operator/monitor; a job cannot reliably monitor its own absence. The job's ceiling is not an organization-wide quota cap.

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
