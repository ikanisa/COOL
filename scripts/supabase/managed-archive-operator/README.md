# Managed admission-archive operator candidate

This candidate prepares the next archive migration,
`20261101012309_collect_admission_archive.sql`, whose exact source SHA-256 is
`82b09d4d2abd5994429a978ccf80daa796fd83e5dc5d29bc54076f2b7565ad84`.
It records that exact complete source in `supabase_migrations.schema_migrations`
in the same transaction as the migration body. It does not include, invent or
record any later migration. The SQL path does not intentionally migrate or
change the user-selected existing cloud account; real account preservation
still requires a separately bound identity check and control of indirect
trigger or privileged-actor effects.

**Managed apply and managed reconciliation are hard refused in these bytes.**
`MANAGED_REVIEWED_APPLY_PLAN_SHA256` is `null`; the refusal happens before a
credential or connection is used. Synthetic execution is a model only. The
latest retained cloud observation had fourteen recorded versions, an open
fence and unresolved admissions; it was not the required fresh post-sixteen,
fenced preimage. Do not infer closure of any historical admission or external
effect from a successful synthetic test. The four migrations between this
archive migration and the later deployment-identity migration remain separate
work and are not represented as applied here.

`captureManagedArchive` and the private-pipe supervisor contain a **live-capable
read-only capture path**, but this revision has not been independently
qualified for a real call, and none of its tests uses real credentials or
contacts Supabase. A future use requires independent review of the exact frozen
revision, trusted execution environment and protected channels. The fixed
direct endpoint is `db.rrlduytparvsjfmegalh.supabase.co:5432`, database and
session/current role `postgres`; the existing provider CA and peer verifier are
used. A dedicated `pg` client is created by the worker and the backend PID,
PostgreSQL 17, database and role are checked. These checks depend on trusted
Node/`pg`, DNS, operating system and TLS implementation; they are not host
attestation, and the tests do not establish a real managed TLS handshake.

The capture starts `BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY`, obtains
the migration, WORK and WRITE advisory locks and the relevant history/fence
table locks before inspecting the preimage, and rolls back. These locks can
block application or migration work even though the capture does not write
database rows. It requires the exact sixteen predecessor history names, source
hashes and statement cardinality, a fenced project control record, readable
ordinary non-inherited tables with no active RLS filtering, and absence of the
new archive objects. It collects bounded history, selected schema/catalogue,
role/default-ACL/event-trigger metadata, fence records and a digest/count of
all admitted rows. PostgreSQL JSON text is retained verbatim so large numbers
are not rounded by JavaScript. Catalogue and fence JSON are each limited to
8 MiB; admissions are limited to 10,000 rows, 8 MiB total and 32 KiB per row.
The overall preimage is capped at approximately 16 MiB. This bounds the
returned data, not every intermediate server allocation.

Before reading private input, the supervisor starts a bounded verifier for the
fixed `SOURCE-PINS.json` and requires a separately supplied SHA-256 of that
manifest. The manifest binds the listed source and executable bytes, including
the fixed migration and Node executable. The worker verifies the same manifest
again before reading its input. Changing, removing, replacing or symlinking a
listed file fails closed. The manifest digest is also recorded in the capture
receipt and bound into the reviewed plan and durable journal. The externally supplied digest must be the independently
reviewed value; a digest generated from unreviewed files proves only
consistency. These checks cannot retroactively attest the code, runtime,
libraries, loader or environment already loaded before verification, and they
cannot exclude a same-user change after a check. Trusted launch and independent
source custody remain required.

The returned preimage contains **private operational metadata**, including
fence and admission-related identifiers. A supervisor must provide a trusted
private pipe on stdin and a trusted private pipe or socket on stdout, and
secure the received preimage. Do not put passwords or the envelope in
arguments, environment variables, shell history or logs. The entrypoint takes
one non-secret argument: the independently reviewed source-manifest SHA-256.
Stdin is compact JSON with exactly `format`, `action`, `password`
and `timeoutMs`, for example using the format
`collect.managed-archive-operator.v1` and action `capture`. The full output is
not appropriate for public logs. Input is capped at 32 KiB and five seconds;
the worker output is capped at 18 MiB. The worker has a connection timeout and
an overall query deadline; its supervisor attempts process-group termination
and reports an unconfirmed stop rather than claiming success. A missing,
partial or undelivered response is unknown. SIGKILL, host failure, escaped
descendants, event-loop/filesystem stalls and delayed server-side disconnects
remain outside the local termination proof. JavaScript strings, same-user
inspection, swap and crash dumps limit credential custody.

The selected preimage is not a complete catalogue or production recovery
proof. Captured metadata is an inventory for independent review, not automatic
approval of arbitrary event triggers, default ACLs, roles or function
dependencies. The relation and advisory locks cannot exclude all privileged
DDL, non-cooperating applications, other machines, providers or external actors.
An independently verified exclusion/fence boundary and recovery plan are
required throughout a future real attempt. An exclusion-evidence digest in a
plan binds a reference; it does **not** establish that those actors are stopped.

## Atomic path and journal model

For the synthetic fixture, the executor repeats the locked preimage checks,
compares both the reviewed digest and the separately bound admission count and
digest, runs the exact pinned archive body, verifies selected postconditions,
inserts the exact source history row, and rechecks those postconditions before
COMMIT. The PostgreSQL command tag must actually be `COMMIT`; a `ROLLBACK` tag
or lost COMMIT acknowledgement is unconfirmed and never converted into a
retry. Original admission rows, including an uncertain obligation, are checked
unchanged; the migration does not establish whether provider effects occurred.

A protected owner-only journal root reserves one version-specific directory
before a managed connection or dispatch, with exclusive creation and fsync of
intent, backend and outcome records. Its intent binds the source, preimage,
admission digest, reviewed plan digest, source-manifest digest and
external-exclusion evidence digest.
A crash or missing/failed outcome remains unconfirmed; an existing directory
blocks a second attempt under that root. Read-only reconciliation requires a
matching journal, a different backend and absence of the recorded backend PID;
it verifies exact history and selected postconditions or reports unknown. A
`not_recorded_do_not_retry` observation is point-in-time evidence, not retry
authorization. Records and permissions assume a trusted local filesystem and
owner: another root or host, same-user changes, power loss and non-cooperating
actors require independent control.

Before managed apply can be considered, the two predecessor migrations must
be actually installed and verified, a fresh managed preimage captured and
reviewed, an exact plan and exclusion evidence independently bound, and the
real actor/fence/recovery prerequisites resolved. The null gate must then be
replaced only in a separately reviewed successor. The synthetic socket and
cluster names are accidental-use guards, not OS-enforced proof that a caller's
socket cannot be proxied. Exported fixture/library functions and supplied
clients are trusted test interfaces, not a production security boundary.

## Synthetic test

From the physical checkout, using the pinned macOS PostgreSQL 17 fixture tools:

```sh
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
  /Volumes/PRO-G40/Development/Node/bin/node --test --test-concurrency=1 \
  scripts/supabase/managed-archive-operator/*.test.mjs
```

The tests use invented records and owned disposable socket-only clusters. They
exercise source/history/fence preimage checks, forced-RLS refusal, exact
large numeric capture, a blocked concurrent writer, rollback after SQL and
history, uncertain-admission preservation, a lost COMMIT acknowledgement,
single-use journal and point-in-time reconciliation, private-input refusal and
the closed managed gate. The fixture substitutes the reviewed synthetic
Realtime predecessor and records the bytes actually executed; this is not the
managed predecessor history. No live project, password, provider, Storage or
production state is accessed by those tests. The preserved `frozen-v1/`
directory contains the earlier reviewed candidate and its original manifest;
it is historical evidence, not the active execution path.
