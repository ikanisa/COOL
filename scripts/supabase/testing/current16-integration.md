# Complete current16 native integration gate

This maintained gate applies the exact 16-migration candidate to a new local
PostgreSQL 17.10 database and exercises the real runtime adapter, application
fence, new diagnostics and Android delivery tables, shipping Admin retention
wrapper, queue-health SQL and default maintenance handler together. It creates
fresh evidence with the `collect.current16` identity. It does not update or
approve any earlier qualification packet.

## Commands and explicit environment

```sh
node --test scripts/supabase/testing/current16-integration.test.mjs
node scripts/supabase/testing/current16-integration.mjs
```

The native command accepts no arguments. Supply these environment variables
through the owned test runner, without putting credentials on the command line:

| Variable | Required value |
| --- | --- |
| `COLLECT_CI_SYNTHETIC` | Exactly `true`. |
| `COLLECT_CURRENT16_ADMIN_DATABASE_URL` | `postgres://collect_test:<synthetic-password>@127.0.0.1:<port>/postgres`. The only admitted ports are 55439 for the isolated CI job and 55443 for the separately owned local qualification cluster. |
| `COLLECT_CURRENT16_OWNER_DATABASE_URL` | Required only when that exclusive cluster already has the normal `postgres` owner role. Same literal host, port and `/postgres` database, username `postgres`; must authenticate as that actual role. No automatic credential lookup or HBA change occurs. |
| `COLLECT_CURRENT16_OUTPUT_DIR` | Absolute, physically resolved, **new** directory beneath an existing physical parent. Existing files, directories and symlinks are refused. |
| `COLLECT_DENO` | Absolute physical path to pinned Deno 2.9.6. |
| `COLLECT_PG_MODULE` | Optional `pg` or absolute physical module path resolving the maintained locked `pg@8.16.3`. |
| `DENO_DIR` | The independently warmed pinned dependency cache; the child runs with `--cached-only --frozen`. |

Node 24 is required. A missing database, native binary, cached dependency, source
file or matching role is an unconfirmed failure, never a skipped success.

## Safe local preparation

The caller checks actual server address, port, version, database owner and
`collect_test` bootstrap role. It writes and fsyncs a private creation intent,
then creates one database with the exact generated name grammar
`collect_current16_integration_<24 lowercase hex characters>_test`. It never
drops, resets, overwrites or retries an existing database. Failed attempts remain
available for inspection. The normal owner profile has `LOGIN` and `CREATEROLE`,
with `SUPERUSER`, `BYPASSRLS`, `INHERIT`, `CREATEDB` and `REPLICATION` all false.

Two setup paths are explicit:

1. A fresh cluster with no `postgres` role, or the exact restricted fixture role,
   uses the existing reviewed fixture loader through SQL13. The caller withholds
   SQL14, transfers only its newly created database objects, and creates the
   actual normal local owner connection. This role transition is allowed only
   when no unrelated database exists, apart from the standard CI schema fixture.
2. An exclusive prepared cluster with the exact normal owner profile requires
   its explicit owner URL. The new preparer independently applies the same
   exact admitted predecessor bytes, transfers only the new database's objects,
   and uses the existing actual owner connection without altering its login or
   role-flag profile. The original admitted fixture/migration SQL still executes
   its role creation and membership statements; this is not a claim that all
   cluster-role state is unchanged. The old loader's restricted-profile
   assertions and callers remain intact.

Both paths require the real hosted SQL10 metadata refusal and rollback before
applying the separately reviewed local SQL10 binding. Its only changes are the
two previously reviewed metadata hash literals; this is not hosted Realtime
acceptance. Original SQL14 is then executed as the actual non-superuser
`postgres` session, followed by exact SQL15 and SQL16. All original migration
files remain byte-for-byte unchanged.

## What the native result proves

The 16 integration cases cover the following relationships under one complete
candidate schema:

- All 99 application tables, 22 private tables and 115 ALWAYS statement guards
  coexist with the stopped-admission v3 protocol and actual normal owner/runtime
  roles.
- Diagnostics and delivery retain forced RLS, exact client/runtime privileges
  and rejection of mutations without a real application admission.
- Installation enables no Realtime, scheduler or provider and creates no
  delivery obligations. The deployed maintenance handler retains its paused
  receipt and disabled push defaults.
- Actual authenticated diagnostic writes are replay-safe, omit user/session
  identity, reject arbitrary payload fields and reject a revoked managed session.
- Original-email proof, retired mandatory authenticator enrollment, the shipping
  `accountDatabase` wrapper, full app/private retention catalogs and subsequent
  current-session revocation are exercised together. The test does **not** use
  `adminEmailFixtureDatabase` to supply missing production transaction context.
- Actual durable event/device insertion, Android payload serialization and FCM
  adapter parsing accept an event once. Consent changed during synthetic OAuth
  prevents the message call. An ambiguous synthetic response becomes retained
  `unknown`, is never automatically resent, and remains inventoried after the
  original erasable event/device rows are removed.
- Every shipping queue-health SQL projection executes against its real table.
  Financial rows remain unchanged. Committed v3 quiescence and drain prevent a
  fresh runtime admission without pretending that unknown provider obligations
  were settled.

Managed Auth rows, OTP evidence and provider HTTP responses are explicitly
synthetic. Every unhandled external `fetch` is refused, and the child has network
permission only for its literal loopback database port. `synthetic_provider_calls`
counts exercised HTTP interfaces; `external_provider_calls` must be zero.
Acceptance means the local FCM response was parsed and its durable outcome was
recorded. It is not evidence of Firebase/device delivery.

The source manifest binds exact runtime JS files, migration bytes, fixture
sources, the native consumer and locked dependencies. Every parity check
re-enumerates the runtime inventory, rejects added or missing paths and symlinks,
and verifies sizes/hashes with bounded file counts and bytes. A changed source
tree invalidates that attempt. `git HEAD` is recorded as provenance; it does not
substitute for the actual working-tree manifest.

## Retained artifacts and result limits

The caller writes mode0600 source inputs, preparation and creation records,
bounded child stdout/stderr, child exit metadata, and a top-level result. The
native child writes cases, safe observations, actual application-work closure
receipts and its native result. The private URL-bearing run spec is removed at
the end, and a separate filesystem check must confirm its absence before a PASS
is written. An acknowledged unlink with a retained path, or an inspection error,
disqualifies the result. `private_spec_removed:true` records that observation;
the upload allowlist must still exclude `RUN-SPEC.private.json` on every outcome.
Connection credentials are absent from the retained public records.

The gate preserves its database and records failure rather than resetting and
relabeling an attempt. A successful result always keeps
`hosted_acceptance:false`, `legacy_sql_gates_closed:false` and
`financial_posting_acceptance:false`. It does not run the entire stopped-lifecycle
matrix, a provider SLA, full financial posting acceptance, real Auth/device
workflows, a hosted migration rollout or an adopted release.

## The six legacy SQL packet cases

The six guarded Flutter cases are still identifiable in maintained tests. They
consume five different packet inputs; two tests share the SQL142 roster packet.
None accepts the `collect.current16` result as a replacement:

| Maintained test | Required packet/input | Contract still unproved by this gate |
| --- | --- | --- |
| `test/admin_roster_sql_receipts_test.dart` | `ROSTER_SQL_RECEIPTS`; `ROSTER_RECEIPT_FIXTURE_PASS\|2` and exactly two deterministic/AI receipt rows | Original SQL142 upload/source receipt, human revision, commit/replay and read result. |
| `test/admin_roster_import_test.dart` | The same `ROSTER_SQL_RECEIPTS` | Original SQL142 status binds the captured source, reviewed revision and commit. |
| `test/admin_roster_reload_test.dart` | `ROSTER_RELOAD_SQL_RECEIPTS`; two `ROSTER_RELOAD_RECEIPT_JSON` rows | Original SQL144 staged intent and pre/post-commit recovery. |
| `test/admin_roster_fresh_auth_sql_receipts_test.dart` | `ROSTER_FRESH_SQL_RECEIPTS`; one receipt plus all 51 assertions | Original SQL149 interrupted-import ownership transfer and fresh-auth recovery lineage. |
| `test/admin_read_contracts_test.dart` | `ADMIN_READ_SQL_RECEIPTS` and `ADMIN_READ_SQL_ACTOR` | The older public Admin RPC result set, including detail, SLA and WhatsApp-approval contracts. |
| `test/actual_member_history_sql_receipts_test.dart` | `MEMBER_HISTORY_SQL_RECEIPTS_BASE64` from its reviewed source-bound gate | The original captured member-history SQL packet and its decoder windows. |

These legacy producer scripts and original SQL142/144/149/public-RPC migration
chain are not the active curated 16-migration source. Several older roster
fresh-auth recovery RPC names are absent from the current domain dispatcher;
the shipping Admin uses the canonical BFF route set. Reconstructing a historical
database or substituting current JS results would not establish those original
producer claims. The preserved historical snapshots remain historical.

The separately maintained `current14-member-history.mjs` producer and
`test/current14_member_history_sql_receipts_test.dart` provide an explicitly
named current-domain replacement check for history, including both wire
versions. Their source manifest and result must be rerun for a changed candidate;
they deliberately do not close all six legacy gates. Owner disposition of old
contracts and final release acceptance remain separate from executing this
current16 local integration gate.
