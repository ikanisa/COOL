# Synthetic admission-archive migration qualification

This experiment covers the next ordered source migration after the existing
operator's two migrations: `20261101012309_collect_admission_archive.sql`,
SHA-256 `82b09d4d2abd5994429a978ccf80daa796fd83e5dc5d29bc54076f2b7565ad84`.
It is a prerequisite for the separately developed managed identity binder. The
original migration file and all recorded history remain unchanged.

**The runner is synthetic only. It cannot accept a database host, connection,
credential, caller-supplied client, or managed-mode option. It opens its own
newly created socket-only PostgreSQL 17 cluster and requires its own cluster
name, generated database, non-superuser `postgres` session and backend PID. It
never contacts the local Collect source, Supabase, or a provider. It is not a
production operator or an authorization to apply the migration.**

The fixture executes the actual sixteen predecessor positions in order, including
the first two pending migration files. The hosted Realtime predecessor is
explicitly tested to refuse the different local metadata, then the established
reviewed synthetic Realtime variant executes instead. The other fifteen use
the original source bytes. After those successful executions, the disposable
fixture history records the bytes actually executed, including the synthetic
Realtime variant; fixture setup is not the history procedure for production.
It seeds a synthetic account/link and synthetic fence/admission states; they do
not represent, settle, or alter any real account or historical provider effect.

In that fixture the action checks the original archive file's exact hash,
separates only its pinned outer transaction framing, takes the migration,
WORK and WRITE advisory locks and table locks, and captures a bounded digest
of the history, selected catalogue, role graph, fence records and admission
rows. It rechecks this preimage after locks, executes the original SQL body and
stores the exact complete original SQL in the history row in one transaction.
Selected postconditions check original admission equality, backfilled working
membership/totals, new table security, trigger enablement, ten function-body
hashes, the complete 16/17 history, and catalogue stability across the history
insert. The fixture refuses event triggers and caps selected synthetic fence
histories at 10,000 rows. It does not establish a complete managed preimage or
prove effects outside these postconditions.

Tests cover predecessor-history drift, changed function security, refusal of
unreviewed event triggers, a deterministically blocked writer committing before
lock acquisition, rollbacks after the body and after the history insert,
malicious synthetic history triggers that alter earlier history or drop the new
index, replay refusal, and preservation of a synthetic primary account/link,
an uncertain settled admission and a separately recorded stopped admission.
Only fully settled, zero-uncertainty synthetic work is archived. All original
admission rows remain present. The stopped-record test uses fabricated fixture
evidence solely to exercise the old database protocol; it is no proof that a
real executor stopped or that external effects are absent or settled.

## Boundaries before a real-capable implementation

The latest retained cloud observation in the migration checkpoint reported 14
history entries, an **open** fence and active historical admissions. That is a
past point-in-time observation, not the post-16 preimage required here. The two
predecessors must actually be installed and verified before a fresh exact
archive preimage can be captured and independently reviewed. The existing
operator does not support this third source file. The synthetic digest cannot
be supplied to it or used as a production preimage.

An independently reviewed managed successor still needs all of the following:

- The authenticated project/session identity, exact predecessor history and
  SQL bytes, source file, relevant object/column/constraint/index/trigger/
  function/ACL/default-ACL/event-trigger definitions and role paths, plus
  bounded admission, stopped-record and fence data under the intended locks.
  This includes a decision on whether the actual provider event triggers and
  administrative role graph are acceptable. Synthetic catalogue capture is
  not an approval of arbitrary captured values.
- A qualified way to stop or exclude independent application, migration,
  provider, privileged DDL and external actors. The cooperative advisory
  locks and relation locks in this experiment do not exclude every privileged
  function/role/DDL or provider action. A prior acknowledged external-work
  assertion can outlive its database lease. The old admission and possible
  effects remain unknown; they must never be presented as absent or settled.
- A dedicated authenticated managed connection with pinned TLS and backend
  identity, bounded cancellation and process/credential handling, a durable
  one-use intent and lost-acknowledgement reconciliation. This experiment has
  none of those interfaces and cannot decide whether an unacknowledged commit
  occurred. It implements no automatic retry.
- A current, independently verified recovery plan and the broader cutover
  prerequisites; database, Auth, Storage objects, Edge functions, external
  systems and devices are not a common snapshot merely because this test
  passes. The cloud-primary decision applies to the specific confirmed person;
  a synthetic unchanged account is not reconciliation of that identity.

The test checks selected archive semantics and atomic rollback against the
fixture, not full app compatibility, performance on real row volumes,
production grants, hosted Realtime metadata, non-cooperating actors, managed
stopped-admission recovery, or subsequent migration order. The two explicitly
unfinished Admin MFA migrations and divergent retention history still require
their separately documented decisions; they are not marked as applied here.

## Test

From the physical repository checkout, on the pinned macOS PostgreSQL 17 toolchain:

```sh
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
  /Volumes/PRO-G40/Development/Node/bin/node --test --test-concurrency=1 \
  scripts/supabase/managed-migration-next/synthetic-archive.test.mjs
```

The launcher checks the eight pinned PostgreSQL wrapper/underlying executables
before and after the fixture. The original sixteen source pins are checked by
the fixture loader and the archive source by this module. The OS, shared
libraries, Node binary, `pg` transitive dependencies and files loaded before
these checks remain trusted; this is not a hermetic attestation. A fixture whose
server shutdown cannot be confirmed is retained and reported rather than
removed. Concurrent same-user or privileged tampering is outside this model.
