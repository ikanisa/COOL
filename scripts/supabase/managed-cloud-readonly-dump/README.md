# Collect managed PostgreSQL read-only dump candidate

This directory is an independently reviewable candidate. **No managed dump has
been run by its author.** The managed path can connect read-only to the fixed
project `rrlduytparvsjfmegalh`, host `db.rrlduytparvsjfmegalh.supabase.co`,
port 5432, database and role `postgres`; a caller cannot override these values or
the provider CA. It uses the existing provider-CA validation and pinned TLS peer
checks. There is no write to the database. The snapshot, catalogue queries and
dump can nevertheless consume resources, retain old row versions, take locks and
delay conflicting DDL.

The output is an encrypted **raw PostgreSQL custom-format dump**, plus an
encrypted inventory sidecar and a local one-use journal. It is not a full
Supabase recovery. It excludes Storage object bytes, global roles, provider
configuration, API secrets, Edge Functions and WAL/PITR. A plain dump can
include managed internals and cannot be assumed restorable on managed Supabase;
Supabase's [backup and restore guidance](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
describes its separate handling of roles, schema, data and provider-managed
objects. `pg_restore --list` is an archive inspection, not a restore test.

## Coverage and snapshot limits

The worker exports a repeatable-read, read-only snapshot and keeps its backend
alive while `pg_dump --snapshot` executes. This ties the connections to the same
snapshot only if both connections reach the same PostgreSQL cluster: exported
tokens are not globally unique. The optional exporter cluster-identifier digest
does not attest the separate `pg_dump` connection, so cluster continuity remains
an endpoint-routing assumption. A count-only catalogue inventory and
privilege check use that same snapshot and role for existing `app`, `private`,
`collect_sms`, `auth`, `storage`, `public` and `supabase_migrations` schemas. Within those
schemas it refuses absent schema USAGE, absent SELECT on ordinary, partitioned
or materialized tables or sequences, active row security, and any foreign
table. This conservative check does not examine every possible permission,
function, extension, catalogue object or other schema and does not prove that
all required schemas exist. In particular it does not enumerate or match each
table, data item or sequence against the dump's table of contents. It cannot
guarantee visibility of rows hidden by mechanisms outside the tested RLS state,
or reconcile any row counts.

The list check only requires a schema entry for each existing inventoried
`app`, `private`, `collect_sms`, `auth`, `storage` or `supabase_migrations`
schema. The TOC output is parsed incrementally, with an 8 MiB total cap and
16 KiB per-line cap; only required-schema flags are retained. It does not assert
table or data coverage. `pg_dump` errors, warnings, failed authentication, malformed or
oversized inspection output, missing required schema entries and failed
readback fail the attempt. Concurrent catalogue or privilege changes may cause
failure or leave coverage uncertain; this code does not enforce DDL exclusion.
Sequence state is not MVCC snapshot data and may change while the dump runs;
the exported snapshot does not establish a single transactional time for
sequence values. The PostgreSQL snapshot token is passed in `pg_dump`'s command
line and may be visible to local process inspection or server logging.

## Capacity, secrets and trust

Dump payload is capped at **1 GiB**, independent of database allocation. Before
the attempt is recorded, and again before `pg_dump`, the artifact filesystem
must report at least the full payload cap plus a **1 GiB reserve and 32 MiB
overhead**. During streaming the remaining budget is rechecked at intervals of
about 4 MiB, and insufficient headroom aborts. The cap can reject a valid larger
dump. Filesystem accounting, delayed allocation or simultaneous writers can
still exhaust space between checks; this is not a reservation. The supervisor
also has a hard deadline of 1 second to 4 hours.

The password file must be an owner-owned, single-link, real-path regular file
mode 0600 in an owner-owned directory inaccessible to group and others. The
password is 1–4096 bytes. One final LF or CRLF is removed; all other bytes,
including spaces, are preserved, while embedded or multiple line endings and
NUL are rejected. The key file
has the same requirements and must contain exactly 32 random bytes. Credentials
are read by a separately supervised child, with post-read path, inode, size,
timestamp and extra-byte checks to detect ordinary concurrent edits, and passed
through private pipes; no
password or key is put in arguments, environment or diagnostics. `pg_dump`
receives an owner-only temporary passfile through an immediately unlinked file
descriptor. Its blocks may remain on scratch storage or in backups or swap;
unlinking does not prove secure erasure. The archive's authenticated header
contains project binding, operation ID, creation time and snapshot/inventory
digests in plaintext, but not the database dump. Retain the key independently
and securely: the archive cannot be recovered without it.
The code does not require the key path to be outside the artifact root or prove
separate key custody; an operator must arrange that separation.

These controls assume a trusted user account, machine, Node runtime, OS,
dependencies, toolchain and private directories. They do not defend against an
actor with the same user privileges. The launcher must start with a clean
environment: environment checks inside Node cannot undo a preload that has
already executed. The resolver can execute `postgres --version` and possibly
`pg_config` before checking `pg_dump`/`pg_restore` hashes, so the resolver and
toolchain location are part of that trust boundary. Pins cover the selected dump
and restore wrappers and their wrapped executables, not their dynamic libraries.
Production tests have not verified this trust boundary.

GCM authenticates the entire ciphertext before any plaintext is sent to the
TOC parser. A second pass hashes each ciphertext block against the authenticated
first pass, then rechecks GCM. Following promotion to final private names, both
artifacts are reopened and authenticated and their bundle digest is journaled.
Results are point-in-time observations: a same-user writer can change an
artifact after readback, and custody outside this process is not established.
Protect artifacts, key and journal and independently verify the completed
bundle before relying on it. The journal's hash chain detects some corruption;
it is not protection from a same-user attacker.

The journal uses exclusive local files and fsync to allow one dispatch for one
trusted root. It is not global exclusion: another host or another root can act,
and power-loss durability has not been established for every filesystem. The
active record remains after completion or uncertainty; no automatic retry or
reset exists. Missing acknowledgement, a deadline, failed inspection, an
uncertain process stop or a retained partial output require status inspection
and reconciliation rather than another dispatch. Private partial or promoted
encrypted files are deliberately retained on uncertainty. Process-group stop
checks cannot prove cleanup of descendants that escape the group. The CLI
forwards SIGTERM and SIGINT to its owned group and reports interruption as an
unknown outcome; the worker keeps its group leader alive for bounded escalation.
An unexpectedly lost leader is not followed by a signal to a potentially reused
group ID. SIGKILL, host failure or another failure that kills the supervisor
without a handled signal can leave the detached group running; journal state
alone does not establish that it stopped.

## Interface for a reviewed operator

After independent review, an operator can prepare an owner-only JSON plan
containing only paths and hashes, never password or key bytes:
`executeReadOnlyDump` is also exported for fixture testing and does not itself
enforce use of the supervisor. Production use depends on the trusted operator
selecting the reviewed `supervisor.mjs` entry point.

```json
{
  "deadlineMs": 14400000,
  "request": {
    "mode": "managed",
    "operationId": "<new lowercase UUID>",
    "journalRoot": "<absolute existing private 0700 directory>",
    "artifactRoot": "<absolute separate existing private 0700 directory>",
    "passwordPath": "<absolute private password file>",
    "keyPath": "<absolute private 32-byte key file>",
    "dumpToolSha256": "<reviewed pg_dump wrapper or binary SHA-256>",
    "dumpExecutableSha256": "<reviewed actual pg_dump executable SHA-256>",
    "restoreToolSha256": "<reviewed pg_restore wrapper or binary SHA-256>",
    "restoreExecutableSha256": "<reviewed actual pg_restore executable SHA-256>",
    "fixture": null
  }
}
```

The journal and artifact roots must be distinct and non-overlapping. The
`planDigest(plan)` export computes the canonical JSON SHA-256 that the operator
must independently compare with the reviewed plan. The command below shows the
interface; it has not been executed against the managed project:

```sh
env -i PATH=/usr/bin:/bin LC_ALL=C /absolute/path/to/trusted/node \
  /absolute/path/to/managed-cloud-readonly-dump/supervisor.mjs REVIEWED_PLAN_SHA256 \
  < /absolute/path/to/private-plan.json
```

`readReviewedDumpStatus` reads the local journal in an independently supervised
child. `verifyReviewedDump` reopens and authenticates the completed bundle in a
separate child and compares its digest to the completed journal. Both are
exported by `supervisor.mjs` and require `expectedPlanSha256`; that hash is
bound into the durable journal and authenticated archive. They make no database
connection and do not
authorize another attempt. A result ending in `unconfirmed`, `unknown`,
`unavailable` or `do_not_retry` is not a successful backup receipt. Even
`completed_point_in_time` and `bundle_verified_point_in_time` are limited to
the observed bytes and the scope above. The CLI exits zero only for
`completed_point_in_time`; every other returned status exits nonzero. Exit
status is not a substitute for inspecting the bound receipt and journal.
On an unconfirmed dump outcome the launcher may include a bounded diagnostic
array containing only fixed phase labels, child exit/signal and stderr byte
counts. No raw stderr, TOC lines, paths, SQL, credentials or data are included.
The diagnostic channel is best effort and is not durable; an interrupted or
missing event does not prove which later steps ran, and it cannot explain a
previous attempt whose worker did not emit these events. The authoritative
unknown/no-retry journal state remains unchanged.

## Synthetic checks

From the repository root, the following starts owned local PostgreSQL 17
fixtures only, with synthetic passwords and test data:

```sh
node --test --test-concurrency=1 scripts/supabase/managed-cloud-readonly-dump/*.test.mjs
```

The checked-in tests currently assume the macOS fixture paths and wrapped
PostgreSQL binaries used here; they are not a Linux portability claim. Synthetic
socket and TLS boundaries are accidental-use safeguards, not proof of ultimate
database ownership. The direct managed path must not be run until this exact
candidate and its dependencies have been independently reviewed.
