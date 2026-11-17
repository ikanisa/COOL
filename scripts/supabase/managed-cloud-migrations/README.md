# Atomic managed migration operator

This operator connects the existing `atomic_cloud_migration.mjs` library to a
real `pg` client. It is limited to the exact source bytes and original history
versions already pinned by that library:

- `20261029120000_collect_client_diagnostics.sql`
- `20261029130000_collect_notification_delivery.sql`

It does not apply the other pending migrations, move data or objects, reconcile
accounts, open a fence, deploy functions, or establish release readiness. It has
not been used against production. A successful synthetic test is not a hosted
connection or migration qualification.

## Preconditions

Use the existing production project `rrlduytparvsjfmegalh`. Independently
establish recovery, stop other migration/schema actors, quiesce and drain the
application, confirm its fence is `fenced`, and review the exact current source,
roles, grants and deployment plan. The library checks the fence and relevant
catalogue under locks, but does not prove that all writers, providers, pending
operations or external actors have stopped. Nonparticipating concurrent DDL can race the locked preimage;
common exclusion or an independently proven equivalent is required before
production execution. A backup and a locked preimage are different things. The owner has selected the existing cloud account as primary;
this operator does not change that account or its data.

For the new tables, postconditions require the expected `postgres` object and
schema owners, the exact direct `collect_runtime` table privilege set, no
column ACLs, and no extra effective runtime TRUNCATE, REFERENCES, TRIGGER or
PostgreSQL 17 MAINTAIN privilege. Object owners retain intrinsic privileges.
These checks do not authorize the captured role graph: roles inheriting the
runtime or predefined data/maintenance roles are excluded from the outsider
scan, and SET-only paths require separate review. The role graph, default ACLs
and privileged schema actors must remain controlled through the transaction.

The target must be `db.rrlduytparvsjfmegalh.supabase.co` on 5432 as `postgres`,
or `aws-0-eu-north-1.pooler.supabase.com` on 5432 as
`postgres.rrlduytparvsjfmegalh`.
It refuses transaction port 6543 and the CLI's separate `cli_login_postgres`
role. TLS uses the public Supabase database root published by the project's
dashboard and stored in `supabase-root-2021.pem`. The operator checks that it
is the single, valid, self-signed CA with DER SHA-256
`807025ad50d4ed219d2c9c7d299c004f824eb00cf7f65afef607d07b72e6cafa`,
before creating an apply journal. Only that root, certificate verification,
the built-in hostname verifier and the expected server name are allowed.
An expired, changed or unavailable root fails closed; a provider rotation
requires independent review of the new trust material and code before use.
The backend must report `session_user=current_user`
`postgres`, database `postgres`, PostgreSQL 17 and the expected project/fence.
These checks require a genuine dedicated connection; the MCP SQL editor session
is not evidence that the operator has one. Supabase's connection modes are
documented at <https://supabase.com/docs/guides/database/connecting-to-postgres>.

## Interface and journal

The command takes one non-secret argument: an absolute physical path to an
existing, owner-only (0700), caller-owned journal directory on an appropriate
protected filesystem. A trusted supervisor must pipe one **compact canonical**
JSON object to stdin. The operator accepts a pipe or socket only, not a TTY or
regular-file stdin. It does not read credentials from arguments or environment;
the JSON password is provided only over the private pipe. Do not print or save that JSON.
A shape example (placeholders are not executable credentials):

```json
{"format":"collect.atomic-cloud-operator.v1","action":"capture","connection":{"host":"db.rrlduytparvsjfmegalh.supabase.co","user":"postgres","password":"<private pipe only>"},"migration":{"version":"20261029120000","sourceSha256":"<64 lowercase hex>","preimageSha256":null}}
```

The producer must serialize via `JSON.stringify` or equivalent compact JSON;
duplicate keys, whitespace changes, extra fields and invalid UTF-8 are refused.
The source hashes are available from `pinnedMigrationIdentities()` in the
library. `capture` requires `preimageSha256: null`; `apply` and `reconcile`
require the previously reviewed 64-hex preimage digest. The intended shape is
identical across actions except for those fields. `capture` outputs the full
catalogue preimage and digest: treat its output as protected operational
metadata and review it independently before applying.

Preimage format v3 includes all enabled and disabled event triggers, their
owners, tag filters and handler identity, security settings and definition
hash. Existing v2 digests cannot authorize this version; capture and review a
fresh preimage. Inventory is not a determination that an event trigger is
safe. The operator checks the two new tables' expected policies and triggers,
the captured fence function and the pinned notification handlers both after
DDL and after recording migration history. It does not verify every other
possible event-trigger effect, and non-cooperating privileged DDL can race the
checks.

`apply` first makes a version-named 0700 directory, writes an exclusive intent,
then connects and writes the backend PID. Files and directories are fsynced
before migration execution. The executor verifies the same backend PID before
starting its transaction, and records a non-secret outcome after it finishes.
A second `apply` using the same trusted journal root and version is always
refused. If the operator crashes or cannot write and fsync an outcome after dispatch, it
reports `unconfirmed` with the version and backend PID when output is available.
Preserve the intent/backend records, treat the result as unconfirmed, and use
the read-only reconciliation path; an outcome file may be missing or partial. The journal contains
no password or SQL body. `fsync` supports process-crash recovery on a suitable
filesystem; it is not a guarantee against power loss, compromised storage,
other journal roots or a same-user attacker. Use one protected root, preserve
it separately, and maintain independent operational exclusion.

The supervisor must require one complete, valid response matching the requested
action and version. If the response is missing, truncated, malformed or cannot
be verified, treat the attempt as **unconfirmed regardless of process exit
status** and use the journal and read-only reconciliation before any retry.
An observed stdout write failure makes the operator exit nonzero, but a
successful local write callback does not prove that the supervisor received the
bytes. In particular, a broken response channel after a commit must never be
interpreted as a refusal or as permission to execute the migration again.

`reconcile` requires the identical version, source/preimage hashes and endpoint
as the journal. It writes a new one-use attempt record, refuses while the
recorded prior backend PID still appears in `pg_stat_activity`, and uses a new
connection with the library's history-table locks. `recorded` means the exact
version/name/stored SQL hash exists; it does not establish all postconditions or
full application compatibility. `not_recorded` is a point-in-time observation,
not permission for an automatic retry. If an intent exists without a backend
record, first establish that the old operator process is stopped and investigate;
the tool does not guess or retry. Preserve incomplete and failed records.

The operator rejects `PG*`, Node preload/custom-CA/TLS override variables and
related dynamic-loader or SSL variables. A trusted supervisor must launch Node with a clean environment from the outset,
using a trusted executable and filesystem. In-process checks
cannot undo dynamic libraries or Node options loaded before the check runs. This cannot
protect against a compromised binary or same-user process, process inspection,
swap, crash dumps or immutable JavaScript strings; a password cannot be
reliably erased from all runtime memory. For local and CI tests no real
credential is needed.

## Local tests

From the repository root, with the pinned Node and `pg` dependency installed:

```sh
node --test scripts/supabase/managed-cloud-migrations/provider-ca.test.mjs scripts/supabase/managed-cloud-migrations/operator.test.mjs
COLLECT_SYNTHETIC_PG_BIN=/absolute/physical/postgresql-17/bin \
  node --test --test-concurrency=1 scripts/supabase/managed-cloud-migrations/operator-pg.test.mjs
```

The native tests create and remove their own Unix-socket PostgreSQL 17 clusters,
seed synthetic baseline history, execute the actual first and second migrations
with a non-superuser `postgres` owner, exercise denied excess table/column and
inherited maintenance privileges, and simulate a
lost COMMIT acknowledgement, outcome-record failures and a closed stdout pipe,
and reconcile the recorded history.
Its local adapter **simulates** TLS metadata; it does not validate managed
credentials, network failures, production privileges or Supavisor. Independent
certificate-only TLS handshakes verified the exact hosted names and rejected a
wrong hostname; they did not authenticate to the database or execute SQL.
The library's existing `atomic_cloud_migration.test.mjs` separately covers both
pinned migrations, postconditions, rollback and two-session locking.
