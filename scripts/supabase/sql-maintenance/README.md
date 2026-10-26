# Direct SQL maintenance Cron — installation and qualification

The migration owner controls integration, PostgreSQL execution and hosted operations. This source package supplies an explicit inactive installation and qualification path; its presence does not establish installation, activation or native scheduling. The earlier HTTP scheduler remains separate and blocked by its native privilege requirements. No extension or managed object is replaced.

## Supported path

Supabase supports scheduling SQL/database functions directly: https://supabase.com/docs/guides/cron/quickstart . This proposal schedules `SELECT collect_ops.cleanup_google_expired();` every five minutes under the stable `postgres` role. Installation and inactive Cron creation share one transaction. The function is owner-only, no-argument, SECURITY INVOKER with search_path=pg_catalog. It checks the exact database/operator identity and has one hard-coded mutation.

That mutation preserves the existing `auth-cleanup.js` semantics: capture the server's whole epoch second, select at most100 expired pending/exchanging/ready `app.auth_google_flows` ordered by expiry/id with FOR UPDATE SKIP LOCKED, recheck expiry/status, clear only provider_verifier to `{}` and set status failed. Flow IDs, principal/contact metadata, immutable private.google_flow_context, consumed/failed/future rows remain. This is expiry of unusable credential ciphertext, not subject erasure or a new retention period. There is no receipt processing, ledger mutation, managed Auth/Storage operation, Vault access, HTTP call or provider call. Edge processing/provider settings remain paused; the SQL contains no processing branch that could enable them.

No new data table/journal is created. The function returns the bounded count. Native Cron history supplies run success/failure; its `return_message` need not preserve the returned JSON/count. Do not claim a durable per-run count from Cron's generic command result. Root retains manual probe output, native run status and independent current source/state readback. DB cleanup is atomic and repeat-safe after an uncertain SQL response; a missing response is not rollback or activation evidence.

## Real hosted pg_net limitation

The supplied hosted prerequisite receipt shows PUBLIC queue/response privileges and supabase_admin ownership. Current official guidance says project `postgres` cannot remove those owner grants; changing schema or function grants does not solve table access, and per-project grant/RLS changes are unsupported. Recreating pg_net reinstates grants. Upgrade/Webhook events may restore schema/function grants. Do not try a silent REVOKE, RLS, extension recreation or preflight relaxation. https://supabase.com/docs/guides/troubleshooting/revoking-access-to-pg_net-objects-has-no-effect-0bbc16

Vault encryption does not protect a bearer once copied into the readable HTTP request headers. No job credential is needed or provisioned by the SQL path. https://supabase.com/docs/guides/troubleshooting/database-roles-can-read-request-headers-queued-by-pg_net-ad6357

Primary source confirms PUBLIC native grants: https://github.com/supabase/pg_net/blob/master/sql/pg_net.sql (final grant statements). Supabase's CREATE EXTENSION trigger grants net usage and applies legacy function grants: https://github.com/supabase/postgres/blob/develop/migrations/schema-17.sql (`extensions.grant_pg_net_access`, `issue_pg_net_access`). Read-only native metadata should determine the hosted versions; develop/master source is supporting current source evidence, not proof of the hosted installed body.

## Inventory and catalog boundaries

- app.auth_google_flows already belongs to application retention coverage. Its retained fields/records remain; only expired ciphertext/status change.
- private.google_flow_context is not changed. No table, view or helper is added in private, auth or storage. Therefore no additional private class is being concealed from privateRetentionCatalogIdentity's exact private relation-name check, and managed Auth/Storage schema identity does not change.
- New collect_ops contains exactly one function and zero data relations; `status()` rejects another function/data relation, wrong source body/owner/search path, or client/PUBLIC access. This separately pins the namespace deliberately excluded by the existing app/private/api catalog helper; that exclusion alone is not operational approval.
- New native cron.job row contains only the fixed function call/cadence/stable role/database. Native cron.job_run_details contains operational success/error metadata. Classify and retain this native operational/log copy under the existing blocked external derivative/backups disposition in the owner inventory; error content may require further attribution. No automatic erasure/pruning of native history is supplied. No claim that the native history or provider backups are fully erased.
- If a later implementation adds ANY private job table, it must add the actual retention class/selector/source checks and policy/source rebinding. This proposal does not do that. The prior HTTP scheduler copy proposal is not automatically accepted by adopting this separate SQL path.

## Root qualification and installation sequence

1. Verify source-pins.json and the source package identity, then execute the test below on its owned fixture DB. The three pins cover the exact baseline, authority and cleanup source actually read by the test. Pin changes require reviewing the changed fixture/cleanup consumers; do not regenerate them merely to bypass drift. A prior private version had an owner-reported11/11 local PostgreSQL pass with synthetic Cron. This portable successor requires its own actual execution and does not carry hosted native acceptance from that result.
2. Through the existing verified-TLS, exact-project wrapper, connect to `postgres` and SET ROLE postgres. Retain project/catalog/source/ACL preimages. Never use the expiring CLI role as Cron job owner. Confirm pg_cron/signatures/timezone, source table ownership and reviewed app/private/api catalog; read only aggregates/definitions, not payloads/secrets.
3. Import `render`, `preflight`, `status`, `operate` from operator.mjs. Production render is fixed to postgres/postgres; fixture render is an explicit local-only alternative checked by test URL. Run `preflight(db, rendered)`, then `operate(db,'install-inactive',{rendered})`. It refuses existing unknown collect_ops/named Cron state; exact inactive reinstall can reconcile without replacing.
4. Verify owner-only collect_ops function, exact definition, no data relations, native Cron command/name/role/database/cadence and inactive state. Record unchanged app/private/api and managed/private catalog identities. Accept the narrowly scoped native metadata inventory before activation.
5. Run one `operate(db,'probe',{rendered})` while inactive on a fresh, dedicated AUTOCOMMIT connection, outside any BEGIN or enclosing transaction. The operator relies on this caller contract: a result returned inside an open transaction is not a committed probe and must never authorize activation. Retain its committed bounded count and independent source/data readback; a thrown/lost reply is not a probe receipt. Code takes a fresh server time for each call. No external-effect ambiguity or bearer is introduced.
6. Once that probe is reviewed, `operate(db,'activate',{rendered,probeEvidence:probe})` requires the same job/function/database/operator and a committed bounded receipt under15minutes old. Keep the returned receipt private. Re-read exact native active state; wait for an actual native Cron run, then read only this job's new history and current aggregate cleanup state. A stub call or manual probe is not native scheduling proof.
7. Emergency pause is `operate(db,'deactivate',{rendered})`, then independent status. Pause affects future schedules, not a currently committed SQL transaction.

Maintenance-only pre-cutover scope is limited to destination Supabase's expired ciphertext. It sends nothing and touches no Cloudflare data or business queue. Document this scoped acceptance instead of claiming full source freeze/cutover. Auth/provider, mobile and broader cutover verification remain separate. Free-paused/unavailable database still requires external observation; Cron cannot prove its own absence.

## Local qualification

From the repository root, use Node24 and the existing `pg` module. The owner supplies COLLECT_SQL_MAINTENANCE_TEST_DATABASE_URL privately as the exact loopback collect_test role, port55439, database collect_sql_maintenance_test; COLLECT_PG_MODULE points to the existing pg module. Then:

`node --test scripts/supabase/sql-maintenance/maintenance-test.mjs`

The test locates the repository with `resolve(import.meta.dirname,'../../..')`. Only for the owner's private qualification copy, COLLECT_SQL_MAINTENANCE_SOURCE_ROOT may provide an explicit absolute repository path; keep this override unset for canonical/CI qualification. Relative overrides fail before database access. No private handoff file or fixed volume path is consumed.

The test requires the URL and will not silently skip. It creates/resets only that explicitly named new local DB's four owned fixture schemas, creates no global roles, and extracts the exact current flow/json_valid/context definitions from the pinned canonical source. The local DB is owned by the preexisting NOSUPERUSER/NOBYPASSRLS postgres fixture role; every application/maintenance connection assumes that role, and source RLS is enabled. collect_test is used only for isolated fixture DB creation and session authentication. It uses real PostgreSQL row locks, commits, rollback, concurrent connections and ACL checks. Cron alone is an explicit synthetic interface, not an extension/worker/restart/native scheduling proof. It exercises inactive install/reconcile, privilege denial,100limit, immutable metadata, terminal/future preservation, lock races, concurrent nonoverlap, rollback, lost committed probe reply, activation evidence, pause and identity drift.

## Read-only hosted prerequisite/readback queries

`hosted-readback.sql` contains no payload/credential query and does not invoke cleanup or change any setting. Root executes only through its qualified project/TLS wrapper. The Cron history query targets this fixed job only; preserve results as current evidence, not a reconstruction of prior runs.
