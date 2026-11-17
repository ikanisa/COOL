# Managed stopped-work evidence preparation

**Review-only and not deployable.** This directory contains no SQL migration,
database client, network client, fence control, stopped-work writer, or retry
command. It cannot alter an admission or resolve an unknown external effect.
Every result explicitly sets the write, fence-change, stopped-record and
replay authorization fields to `false`.

The current production predecessor has a `collect_fence_stopped_admissions`
protocol that requires the *actual* former `collect_cf_preserve_########`
role name and OID, together with proof of the role, session and dependency
absence. The current historical managed HTTP admission does not contain an
authenticated connection to the nearby logged Edge execution or its database
login/OID. A nearby 503, a shutdown message, zero active-row counters, and the
current documented worker limit do not establish that linkage, settle
provider effects, or justify inventing the absent role evidence. The existing
local VM stopped-admission migration has different executor assumptions and
must not be used as a managed-Edge proof.

`evidence.mjs` is a bounded pure library for preparing a later review of an
actual managed evidence package. It binds a selected project, admission, fence
epoch/source/operation, exact snapshot digest, separately reviewed policy digest,
and a pinned Ed25519 public key to a narrowly shaped signed assertion. The
assertion names an invocation and binds digests of the separately retained
admission-to-execution evidence, executor-stop evidence, deployment and
committed-quiesce receipt. UTC timestamps are compared at microsecond precision;
policy caps and freshness, worker interval, matching snapshot, source and
operation are checked. The original admission remains active/unresolved in the
model; external effects must be `unknown`.

`parseCanonicalEvidence` accepts only one canonical JSON representation,
rejecting duplicate keys, added whitespace and reordering. Before recursive
serialization, an iterative guard limits nesting to 12 levels, total nodes to
1,024, each object/array to 128 entries, object keys to 128 UTF-8 bytes, and
the encoded document to 16 KiB. Cycles, shared object references, sparse arrays,
accessors and symbol keys are refused. `evidenceDigest`
returns SHA-256 of that canonical UTF-8 representation. The caller must obtain
and independently review the policy and its exact digest; computing a digest
from an untrusted policy and immediately passing it back as its own pin is not
review. A missing assertion is reported as blocked. The current observed open
fence and unlinked historical execution must therefore remain blocked.

`signed_claims_consistent` means **only** that the separately pinned key signed
the exact claims and that their values satisfy the local shape and chronology.
It does not establish that the key belongs to Supabase or a trusted reviewer,
that the provider artifacts exist or are authentic, that the signed linkage is
true, that the quiesce commit really occurred, that an executor is stopped, or
that an unknown-effect obligation has actually been preserved. The caller's
clock and the policy's worker limit are assumptions to be independently
established; the tool never infers termination merely from elapsed time. A
fresh database snapshot alone is not a lock or a guarantee that the underlying
controller is unchanged. No provider signer or trusted production policy is
supplied here.

Before any future state-changing recovery, implement and independently review
a genuine managed-Edge evidence/authority and retained-unknown-obligation
protocol. It must bind the original admission to an authenticated provider
execution or another equally reliable origin, establish committed quiescence
and executor/session termination, pin exact preimages and privileges, protect
against concurrent schema actors, retain original records and unknown effects,
and integrate with the current retention inventory and recovery plan. If that
proof cannot be obtained, the admission remains unresolved. The exact method
and its supported hosted role, clock, logging and evidence custody remain open.

The cloud currently records 14 migration versions. The local-only stopped
admission migration is later in the source chain and depends on other later
predecessors. This directory creates no history entry and does not solve the
ordering problem for an early managed recovery migration. If a future managed
schema change becomes justified, generate its filename using the repository's
pinned Supabase CLI, review exact live predecessor and version-preserving
history, and test the complete dependency/order and recovery behavior before
any deployment.

## Read-only actor inventory

`actor-inventory.sql` is one read-only PostgreSQL 17 query. It reports every
LOGIN role, roles reachable through membership paths with `SET TRUE`, effective
schema/function/table grants, reachable superuser, role-administration and
control-owner capabilities, password-expiry metadata, and observed client
backend counts. Effective inherited grants are considered even where a role
cannot be selected with `SET ROLE`. The result always reports that project
identity, provider credential issuance, executor termination, complete session
coverage, security-definer coverage and cutover authorization are unverified.

This is a point-in-time inventory, not a closed actor list. A connection pooler
can obscure the origin of a backend; role grants, sessions and temporary access
can change immediately after the query. A table `SELECT` grant does not prove
row visibility under RLS, and static role/function grants do not enumerate
security-definer, dynamic SQL, provider or other external execution paths.
An expired password is not an expired role: PostgreSQL explicitly limits
[`VALID UNTIL`](https://www.postgresql.org/docs/17/sql-createrole.html) to
password authentication. [Role membership](https://www.postgresql.org/docs/17/sql-grant.html)
requires a `SET TRUE` chain for indirect `SET ROLE`; this query follows that
chain, while also checking inherited privileges. No credential, user row,
admission identifier, connection address or SQL statement text is returned.

The separate synthetic test creates a socket-only PG17 instance, verifies
direct, transitive and inherited role paths, confirms RLS can still filter a
granted table, connects through synthetic trust authentication after password
expiry, and observes that temporary-credential renewal or a role grant changes
the next snapshot. It also verifies that a missing fence function is reported
as an incomplete catalogue. It removes the owned fixture afterward:

```sh
COLLECT_SYNTHETIC_PG_BIN=/absolute/physical/postgresql-17/bin \
  node --test --test-concurrency=1 supabase/managed-cloud-stopped-recovery/actor-inventory.test.mjs
```

## Synthetic PostgreSQL qualification

From the checkout root, with the existing pinned Node/`pg` and a physical
PostgreSQL 17 binary path:

```sh
COLLECT_SYNTHETIC_PG_BIN=/absolute/physical/postgresql-17/bin \
  node --test --test-concurrency=1 supabase/managed-cloud-stopped-recovery/evidence.test.mjs
```

The test creates and removes its own socket-only PostgreSQL fixture, with only
synthetic rows and generated signing keys. It checks missing linkage, open or
stale fence snapshots, signature/policy tampering, cross-admission mismatch,
unknown outcomes, exact time bounds and immutable original evidence. Its
fixture schema is intentionally a minimal model, not the production schema;
the tests do not connect to the live project or establish managed PostgreSQL,
Supabase logging, network, identity, recovery or deployment readiness.
