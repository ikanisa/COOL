# Synthetic managed admission recovery model

This directory is a **synthetic-only research candidate**, not a migration,
production script, managed Supabase client, or authority to change the live
fence. It creates a fresh local PostgreSQL 17 cluster with a private Unix
socket and no TCP listener, runs only generated synthetic identifiers and
records, and removes its own cluster after confirmed shutdown. The SQL's first
statement refuses installation outside a specifically named test database,
test cluster, test bootstrap role and socket-only PG17 context. The fixture
accepts no connection target and refuses managed/external database settings;
`executeManagedAdmissionRecovery()` always refuses. Do not adapt or run this
model in a real database. No historical admission, v3 history, counters,
provider journal, live function or application migration is changed.

The original evidence is
`/Volumes/T7/01 Projects/COLLECT/outputs/cloud-supabase-assessment-2026-11-14/MANAGED_STOPPED_ADMISSION_EVIDENCE_20261114.md`.
It does not identify the old executor or establish whether an external effect
occurred. In particular, active zero counters are not evidence of no dispatch.
This model does not read or write the historical row and never invents an
executor identity or marks an unknown effect settled.

The modeled path is deliberately conservative:

1. A synthetic operator records quiescence while holding the synthetic WORK
   lock before WRITE; the quiescence transaction must commit before recovery.
2. The recovery operation validates the original admission's exact preimage,
   retains that admission unchanged, and atomically inserts an append-only
   tombstone and an `unknown` obligation covering all external effects.
3. Newly modeled assertions fail after quiescence or tombstoning. A prepared
   effect remains unknown; any further modeled effect preparation is globally
   blocked while an intent or obligation remains unresolved, including when a
   caller chooses a new logical operation ID. This intentionally over-blocks
   because no narrower real effect scope is established.
4. IDs are unique across modeled admission, quiescence, recovery and effect
   operations. Replays, stale epoch/source or preimage, null values, duplicate
   actions and capacity overflow fail without consuming an ID. A rolled-back
   database transaction rolls back its model writes.
5. Unknown-effect resolution, actor closure, close/release and source upgrade
   are not implemented. Status always refuses to claim actor closure, provider
   settlement, release or cutover. Tests include shared runtime actors,
   concurrent preparations, tombstone races and lock ordering.

All lifecycle calls in the model require `READ COMMITTED`. An independent
synthetic counterexample showed that a transaction with an older `REPEATABLE
READ` snapshot could otherwise observe an open admission after a tombstone was
committed. Refusing that isolation mode is a model-specific fail-closed guard,
not a qualification of existing production callers. PostgreSQL's
[transaction isolation documentation](https://www.postgresql.org/docs/17/transaction-iso.html)
describes the snapshot distinction. Transaction-level advisory locks release
at transaction end and only protect participants that use them; see
[PostgreSQL advisory locks](https://www.postgresql.org/docs/17/explicit-locking.html).
The synthetic committed-quiescence check uses
[`pg_xact_status`](https://www.postgresql.org/docs/17/functions-info.html); an
old transaction's status may become unavailable and the model then refuses.

`READ COMMITTED` alone is insufficient for a statement that starts before an
advisory-lock wait. The state-reading model functions are explicitly
`VOLATILE`, and they acquire the relevant lock before reading the control or
admission state. PostgreSQL's
[function volatility rules](https://www.postgresql.org/docs/17/xfunc-volatility.html)
distinguish the fresh per-query snapshots of volatile procedural functions
from the calling statement's snapshot used by stable functions. The fixture
checks the twelve function declarations in `pg_proc` after installation. A
deterministic test uses `pg_blocking_pids` to prove that an assertion waits
behind both quiescence and tombstoning: its outer statement still sees `open`,
while the volatile assertion rechecks and refuses. A separate synthetic
negative control changes the assertion to `STABLE`; the catalog check rejects
the change and the intentionally invoked altered function can then accept
stale work. These checks do not monitor a privileged owner continuously, and
they do not revoke any previously acknowledged assertion.

Two negative demonstrations are essential. First, an old process that already
received an assertion acknowledgement can run a deliberately scheduled
in-memory callback after the tombstone. The model has no provider client and
cannot stop that actor. Second, a callback can happen before a database
transaction rolls back: the absence of an intent row after rollback does not
prove that the external effect did not happen. New modeled callers would need
an independently qualified post-commit dispatch contract; even that does not
establish provider cancellation or settlement. No callback in these tests
contacts a provider.

The append-only triggers and role grants protect ordinary synthetic roles; a
privileged database owner can bypass or disable them. The old production
assertion, shared/privileged role paths, existing schedulers, old workers,
provider effects, function/ACL integration, policy migration, crash and
recovery behavior, and a real actor-closure basis remain unqualified. The
model cannot prove those actors stopped, cannot prevent bypass by a caller that
does not use its API, and does not permit a real cutover. Its cardinality
bounds apply to model state, not arbitrary incoming protocol message size.
The owned-fixture helper preserves its temporary cluster when it cannot confirm
safe shutdown; inspect its diagnostic rather than deleting an uncertain root.
Source and binary hash checks do not fence a malicious same-user replacement or
attest the operating system. The fixture checks both the PostgreSQL launcher
scripts and their actual `.NAME-wrapped` executables; their shared libraries,
the dynamic loader and operating-system components are not pinned.

Synthetic verification from the physical checkout:

```sh
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
  /Volumes/PRO-G40/Development/Node/bin/node --test --test-concurrency=1 \
  scripts/supabase/managed-admission-recovery/synthetic-model.test.mjs
```

`SYNTHETIC-SOURCE-PINS.json` is a review manifest for the candidate, test
support, selected Node dependencies, the Node executable, and both PostgreSQL
launchers and their wrapped executables. It does not attest live project state
or authorize any action. The SQL fixture pins its own bytes before and after
installation and checks the PostgreSQL binary pairs before use and after
confirmed cleanup.
