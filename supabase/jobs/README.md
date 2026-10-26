# Collect maintenance Cron — prepared, inactive

This is a separate operator installation, not part of the curated application migration. No hosted extension, Vault secret, schema or job was installed while preparing it. It reuses the existing PostgreSQL MoMo outbox, row claims, lease tokens and attempt budget. It does not install pgmq or create another business queue.

`config.json` pins project `rrlduytparvsjfmegalh`, `POST https://rrlduytparvsjfmegalh.supabase.co/functions/v1/collect-jobs`, JSON `{ "dispatch_id": "original opaque UUID" }`, `Content-Type: application/json`, and `Authorization: Bearer <Vault value named collect_job_token_v1>`. The deployed function uses custom token admission with `verify_jwt=false`; member/Admin credentials do not authorize this endpoint. No service-role or publishable key is needed by the current handler. `config.json` describes this with `request.body_template`; the SQL dispatcher substitutes its original durable UUID, never the literal template value. The exact UUID must be echoed in the authenticated worker response before it can be confirmed.

The existing handler always runs bounded expired Google ciphertext cleanup (`limit=100`), then the existing receipt outbox drain (`limit=5`). `MOMO_PROCESSING_PAUSED=true` stops extraction while cleanup continues. Cleanup only terminalizes expired pending/exchanging/ready Google flows and clears their ciphertext; it does not delete Auth accounts, session history, financial evidence, consent or raw receipt records. The scheduler cannot override the deployed environment. A future processing enablement requires its own qualified runtime and revised scheduler admission.

## Research verified 2026-10-20

- Supabase documents Cron plus asynchronous `pg_net` for Edge Function invocation and recommends Vault for the credential. The public Cron command here contains only `SELECT collect_ops.tick_jobs();`. [Scheduling Edge Functions](https://supabase.com/docs/guides/functions/schedule-functions)
- Cron uses `pg_cron`. Supabase recommends at most eight concurrent jobs and less than ten minutes per job. This installation has one short SQL dispatcher; it awaits no HTTP inside a database transaction. [Cron](https://supabase.com/docs/guides/cron)
- `pg_net` starts requests after transaction commit. Its queue and responses are unlogged and can disappear after a crash; the queue's owned sequence may reset too. Default response retention is six hours. Its API is beta, so installation verifies the actual signatures rather than assuming compatibility. [pg_net](https://supabase.com/docs/guides/database/extensions/pg_net), [official queue definition](https://github.com/supabase/pg_net/blob/master/sql/pg_net.sql), [unlogged table and sequence behavior](https://www.postgresql.org/docs/17/sql-createtable.html)
- Vault encrypts stored secrets and decrypts them through a privileged view. It does not conceal a live outbound Authorization header from privileged database operators or the HTTP transport queue. [Vault](https://supabase.com/docs/guides/database/vault)
- Free includes 500,000 function invocations; responses with errors also consume invocation usage. Five-minute dispatch is 288 calls/day, at most 8,928 per 31-day month (about 1.8% of that allowance). The independent 10,000 scheduler ceiling includes probes and leaves the application's other calls outside this ceiling. [Invocation usage](https://supabase.com/docs/guides/platform/manage-your-usage/edge-function-invocations)
- Hosted Free function limits are 150 seconds wall time, 2 seconds CPU and 256 MB. The HTTP deadline here is 120 seconds, and missing replies become unconfirmed after 180 seconds. [Function limits](https://supabase.com/docs/guides/functions/limits)
- Free has 500 MB database, shared compute, no uptime SLA, and inactivity pausing. Cron is not a guarantee of availability, an exemption from pausing or a backup strategy. [Pricing](https://supabase.com/pricing)

## Activation procedure

1. Retain independent deployment evidence for the exact function bundle and required runtime configuration. Verify the target project is running, the canonical application migration is applied, wrong-token/method/path requests are denied, and `MOMO_PROCESSING_PAUSED=true`. Before activation, retain proof that the superseded Cloudflare scheduler and backend writers are fenced or disabled under the cutover plan; a new Cron schedule does not retire them. Keep the deployed `COLLECT_JOB_TOKEN` in the owner's existing private custody. This tooling never reads the owner's private token file.
2. Through the authorized Vault UI, provision the **same** credential under `collect_job_token_v1`. Do not put it in SQL literals, saved snippets, Git, shell arguments, generated SQL or logs. This installer neither accepts a token argument nor provisions a Vault secret. Rotation starts by deactivating this schedule, updating the Edge secret and Vault through approved private channels, then repeating the probe.
3. Verify/install `pg_cron`, `pg_net` and `supabase_vault` separately through approved provider operations. This artifact never installs/drops extensions or changes their objects. `pg_net` is non-relocatable; never drop it to fix access while requests/evidence exist. [Cron installation](https://supabase.com/docs/guides/cron/install)
4. Restrict effective Vault and net access for `anon`, `authenticated`, `service_role`, `collect_runtime` and `collect_importer`: no Vault/net schema usage or transport queue/response table privileges. Otherwise a role could read the bearer header, redirect a queued request or forge a response. The installer and every dispatch fail closed on those privileges. Supabase's default pg_net grants require explicit review; a REVOKE by a non-owner may change nothing. Have the provider-supported owner apply and read back the restriction; do not infer success from a silent REVOKE. [pg_net grant ownership](https://supabase.com/docs/guides/troubleshooting/revoking-access-to-pg_net-objects-has-no-effect-0bbc16)
5. Complete the copy-inventory proposal in `COPY_INVENTORY_PROPOSAL.md`. Its current state is a blocker to activation, not an approved addition to the retention policy. Prepare an owned regular 0600 readiness JSON outside the repository using `readiness.example.json`; replace every placeholder with current reviewed evidence and timestamp. No token belongs in this evidence file.
6. Supply `COLLECT_JOBS_DATABASE_URL` through the authorized private process environment, pointing to the exact project `postgres` database with verified TLS. `COLLECT_PG_MODULE` may identify the existing Node `pg` dependency. The CLI emits only sanitized state; it never emits driver messages or SQL parameters. Generate/check the public-safe SQL without connecting:

   ```sh
   node scripts/supabase/jobs_config.mjs
   node scripts/supabase/jobs_operator.mjs install-inactive
   ```

7. After review, `node scripts/supabase/jobs_operator.mjs install-inactive --apply` creates only `collect_ops` objects and an **inactive** Cron entry, in one transaction. Both configuration and Cron remain disabled. The owner is the trusted database operator; functions run with invoker permissions and pinned `pg_catalog` search path. No application/client/importer role receives access. Do not hand this operator database login to an Edge Function.
8. Run one explicitly reviewed maintenance probe with a retained UUID:

   ```sh
   node scripts/supabase/jobs_operator.mjs probe --readiness /ABSOLUTE/PRIVATE/readiness.json --dispatch-id RETAINED-LOWERCASE-UUID --apply
   node scripts/supabase/jobs_operator.mjs reconcile --apply
   node scripts/supabase/jobs_operator.mjs status
   ```

   The UUID is printed before the attempt. HTTP dispatch occurs only after commit. A request ID and a successful Cron SQL statement are not worker success. Reconciliation requires HTTP 200, an exact string echo of that original dispatch UUID, the current native transport instance, confirmed bounded cleanup and zero paused receipt work; it stores only a response digest and safe counts. The original response remains subject to pg_net's own protected custody/TTL.
9. Activate with `node scripts/supabase/jobs_operator.mjs activate --readiness /ABSOLUTE/PRIVATE/readiness.json --apply`. The same evidence must be less than one hour old and the confirmed probe less than 15 minutes old. Vault UUID/update time must still match that probe. Configuration and Cron activation commit together. Repeat `status` and retain provider run/readback evidence. These tools have not performed that hosted verification.

## Reconciliation and operation

The named Cron entry is case-sensitive. Installation refuses another existing job or configuration drift; it does not silently replace a differently configured schedule. The official API supports `cron.alter_job(..., active := false)`, and jobs execute under their creating database user. [pg_cron source/API](https://github.com/citusdata/pg_cron)

A logged dispatch row survives a lost database reply and the loss of pg_net's unlogged queue. Numeric native request IDs are unique only within a native instance: the journal binds a SHA-256 epoch derived from `pg_postmaster_start_time()` and the queue, response and owned-sequence OIDs. A restart changes the postmaster timestamp; native-object recreation changes its object identity. Before consulting a response, reconciliation marks an awaiting dispatch from an earlier epoch unconfirmed and disables scheduling, even if a recycled native number has a valid-looking reply. The SQL does not alter native tables, sequences or managed extension objects. A reply in the current epoch must still echo the exact original dispatch UUID; a missing, null, non-string or contradictory value cannot acknowledge work. Reuse the original probe UUID to reconcile; never automatically resend under a new UUID. An awaiting reply blocks overlap. After 180 seconds without a receipt, an invalid/non-200 reply or a changed runtime gate, the schedule is disabled and the dispatch remains **unconfirmed**. A timeout does not establish rollback. Existing domain source rows, leases and attempt history remain the authority for work effects; this journal is a wake-up record, not a completion queue.

For unresolved work, retain independent runtime/outbox/lease/provider evidence and wait at least five minutes. An authorized operator may then use `review-unknown --dispatch-id UUID --evidence-sha256 REVIEW_DIGEST --apply`. This records `reviewed_unknown`, never a fabricated success. It leaves scheduling disabled and requires a new reviewed successful probe in the current native instance before activation. A previously confirmed probe from another instance cannot activate the schedule or admit a new scheduled dispatch. Old dispatch rows remain attributed to their original epoch; a new epoch can reuse a numeric request ID without replacing that history. No stored HTTP request is replayed by this action.

Use `deactivate --apply` for an emergency pause. `status`, `reconcile`, `review-unknown` and `deactivate` remain available when strict dependency admission fails; they do not read a Vault credential or enqueue HTTP. Pause prevents future dispatches and cannot cancel an already committed request. Independently pause receipt processing and reconcile any active domain lease if necessary.

The one Cron tick prunes at most 500 terminal dispatch rows older than 30 days and outside the current UTC month, preserving current-month quota counting and the admission probe. It also prunes at most 500 finished history rows belonging to this Cron job older than seven days. Unconfirmed work is never automatically pruned. Native Cron history otherwise grows without automatic cleanup. [Cron history](https://supabase.com/docs/guides/cron/quickstart)

Observe this job's current receipt, cleanup backlog, durable unknown count, native Cron failures, function health, global usage and database size. A paused database or disabled Cron requires an external operator/monitor; a job cannot reliably monitor its own absence. The job's ceiling is not an organization-wide quota cap.

## Local qualification

```sh
COLLECT_JOBS_TEST_DATABASE_URL=PRIVATE_LOOPBACK_FIXTURE_URL \
COLLECT_PG_MODULE=ABSOLUTE_EXISTING_PG_MODULE \
node --test scripts/supabase/jobs_test.mjs
```

The test runner permits only `127.0.0.1`/`localhost:55439/collect_jobs_test` and owns that new isolated database alone. It tests real PostgreSQL transactions, ACLs, durable state and multiple connections. **Cron, Vault and pg_net are explicit SQL interface doubles**: no local HTTP worker, encrypted Vault, native extension, Free-plan runtime or hosted scheduling behavior is established by these tests. Reset fixtures explicitly recreate only the synthetic unlogged transport tables and their owned sequence; they test durable epoch separation, reused numeric IDs, stale replies, UUID correlation and reviewed recovery. They do not restart the shared server or establish native crash recovery. Hosted native-extension, credential, endpoint, copy-inventory and quota gates remain outstanding.
