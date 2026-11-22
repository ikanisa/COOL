# Managed deployment identity: provider-compatible candidate v1

**Status: review candidate; not deployed.** The compiler in this directory is
offline and has no provider, network, credential or SQL dispatch. Its generated
SQL is real-capable if an operator later runs it: this is intentionally not the
synthetic-only candidate in `managed-identity-provider-compat`. No production
installation, binding, role change or history write has been made here. The
unchanged original binder remains separately available.

## Observed production state

The aggregate-only, side-effect-free [preimage query](preimage-query.sql) was
run once through the authenticated connector for project
`rrlduytparvsjfmegalh`. Its point-in-time [receipt](LIVE-PREIMAGE-OBSERVATION-20261114.json)
shows 14 migration-history rows, the expected original fence and scheduler,
and the expected selected provider role graph. The archive and deployment
identity predecessors were absent, so this observation is **not** accepted by
the compiler and cannot be reused after the history changes. The query itself
was `SELECT` only; the connector did not attest a read-only transaction mode.

The predecessor's immutable identity table and assertion are required. Do not
manufacture their history records: the complete chain, actual schema, fence,
executor and recovery work must be qualified separately. The existing cloud
account remains primary; neither this binder nor its tests merge real accounts.
In owned PG17, attempting the original preflight without the identity table
raises a missing-relation error while planning its `regclass` constant and
rolls back; it need not emit the named precondition error.

## What v1 changes

The compiler requires the exact original binder SHA-256 and exactly one copy of
its owner-membership guard. It replaces that one guard with these additional
checks; all other original source bytes remain unchanged:

- PostgreSQL major 17 and the exact observed server version, database name,
  and a server-clock preimage interval no longer than 15 minutes.
- The count and SHA-256 of the **entire** ordered migration-history catalogue,
  plus the original binder's three separately pinned predecessor statements.
- Exact observed OIDs and attributes for `postgres`, `supabase_admin`, the CLI
  login, and the single grant row. The grant must have the provider grantor,
  SET true, INHERIT false and ADMIN false. Other non-superuser membership paths
  to the owner, CLI role, or any superuser are refused.
- The original scheduler body and metadata/ACL pin. A different scheduler,
  including the later email-bootstrap variant, is refused pending a separate
  reviewed variant with its actual rendered source and coverage.

The existing migration-history lock protects the full-history recheck. The SQL
does not lock role grants, unrelated function definitions, provider management
operations or non-cooperating actors. A fresh catalogue match is a
point-in-time observation, not a mechanism that excludes those actors.

The compiler appends a single atomic bind to the original install transaction,
using the original migration, work, write and identity lock order. It requires
the identity table to be empty while locked before calling the unchanged binder.
That extra check prevents the original binder's same-operation existing-row
branch from returning before its inactive-controller check. If installation,
scope checks, active/unknown work, scheduler status or binding fails, the
transaction rolls back the new functions and the new identity row together.
The expiry check is made while executing; it does not prove that an in-flight
transaction cannot later commit after the interval. A successfully bound
runtime identity uses the original assertion, not the preimage's expiry.

## Trust and current blockers

`trust-provider-administrators-and-all-owner-actors-v1` is an explicit
operational assumption. The CLI role can `SET ROLE postgres` and change
owner-controlled objects. Provider administrators, management credentials,
their existing sessions, all superusers and all other non-cooperating
owner-capable actors must be trusted and operationally controlled. No expired
password, role name, membership snapshot, advisory lock or time limit proves
that an actor or a pending effect is absent. Ordinary runtime denial in the
fixture is not a full privilege or external-effects audit.

The original migration and binding function also require both `session_user`
and `current_user` to be `postgres`. A CLI login followed by `SET ROLE` fails
that test. The connector's observed read-only SELECT happened to use postgres
for both, but that does not establish a qualified mutating session, transaction
delivery semantics, correct endpoint, or the ability to resolve an ambiguous
commit. The separately investigated historical admission, writer exclusion,
provider and application effects, migration predecessors and scheduler
readiness remain separate blockers.

## Operator plan after those blockers are resolved

1. Independently verify the authenticated provider project and endpoint,
   exact source/dependency hashes, operator access, controlled credential
   custody, and exclusion of non-cooperating privileged changes. This SQL
   cannot by itself authenticate which Supabase project received it. Qualify a
   postgres-session executor with known transaction and error behavior; never
   put credentials into the SQL, environment dumps, logs or receipts.
2. After the actually executed predecessors, capture a new aggregate result
   with [preimage-query.sql](preimage-query.sql). Require the expected database,
   postgres session/current user, all role checks, original scheduler metadata,
   and all three predecessor flags. Obtain a fresh exact whole-history digest;
   the previously observed 14-row digest is no longer valid after any change.
3. Supply that result, the explicitly accepted provider trust assumption, a
   new operation UUID, the **actual** fenced operation/epoch/source SHA and a
   reviewed canonical managed production profile to `preparePreimageV1()` and
   `compileManagedBinderV1()`. Inputs and generated SQL must be kept in a
   private, controlled review artifact with exclusive creation; this directory
   does not implement a production artifact-custody or execution supervisor.
   Inspect the generated SQL and its receipt hashes. The preimage's maximum
   lifetime is 15 minutes, measured against the database clock and rechecked in
   the transaction; generate a new one if it expires before execution.
4. Only after the separate migration, fence and session qualification work is
   complete, a supervised executor can run the entire candidate as **one**
   transaction against the confirmed project. Do not install only its functions
   or split the transaction. Preserve the operation ID, profile SHA, source,
   preimage and compiled-SQL hashes, bounded timing, and acknowledgement state.
5. Use [readback-routines.sql](readback-routines.sql) to compare the two current
   function bodies and metadata/ACL against the receipt, and a separately
   qualified parameterized postgres session with [readback-binding.sql](readback-binding.sql)
   to compare the operation UUID, public profile and SHA without emitting the
   identity row. These are read-only observations; matching objects do not prove
   who installed them or establish whole-system cutover readiness.

For any lost, timed-out or otherwise ambiguous acknowledgement, hold the
operation and do not automatically retry. An owned two-session test shows why:
a readback may report no identity while the original transaction is still
uncommitted, then report a match after it commits. Neither an absent nor a
matching point-in-time readback proves that the prior actor is gone, identifies
the committer, or resolves external effects. Use independently established
actor closure and operation-specific reconciliation before any new attempt.
`assessAcknowledgement()` deliberately returns a hold for every combination of
acknowledgement and readback; it is not a transaction manager.

## Synthetic verification

```sh
cd '/Volumes/COLLECT-STAGING-20261109/main-source'
/usr/bin/env -i PATH=/usr/bin:/bin LANG=C \
  '/Volumes/PRO-G40/Development/Node/bin/node' --test \
  scripts/supabase/managed-identity-managed-v1/provider-bind-v1.test.mjs
```

The tests use a newly owned Unix-socket-only PostgreSQL 17 process and invented
identities, grants and data. They simulate the two later history rows rather
than execute the whole chain. They check exact source preservation, atomic
binding, existing identity refusal, source/history/role/OID/grant drift,
scheduler drift, expiry, runtime denial, active and uncertain work, queued
requests, readback hashes, and the lost-acknowledgement race. Cleanup is
confirmed and the four PostgreSQL launchers and their four wrapped binaries
are checked before and after. The Node executable and module tree are included
in the source manifest; the OS, shared libraries, loader and pre-start code
remain trusted. These tests do not certify provider behavior or production
readiness.
