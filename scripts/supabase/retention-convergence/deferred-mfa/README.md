# Deferred Admin MFA migration candidate

This directory is an analysis-only release option. The synthetic runner starts
an owned socket-only PostgreSQL 17 cluster and executes the exact 65-position
source inventory with the two work-in-progress Admin MFA positions explicitly
deferred. It executes all 63 other positions in order, including a synthetic
realtime binding and the two separately pinned retention branch candidates.
It first confirms the divergent original retention SQL refuses and rolls back,
then applies the additional forward user-ID candidate. The original migration
files are never altered or marked as applied. The fixture verifies that there is
no Supabase migration-history table, and removes its isolated cluster.

The result checks four blocked native retention classes, three Iceberg classes,
six financial runtime functions, the native work assertion and event identity
index/trigger. It checks absence of the WIP MFA functions, session columns,
policy row, trigger and index, and preservation of the previous Admin authority,
factor constraint, enrollment requirement and ungranted generic projector.
The current migration lock, seven added source files, candidates and named
fixture-support files have explicit byte pins. As with the parent fixture, the
synthetic Auth, realtime, Storage and deployment interfaces differ from hosted
services; the binary and all transitive runtime dependencies are not attested.
Passing does not prove all financial or retention behavior, hosted compatibility,
source data equivalence, or that this set is safe to deploy.

`history-proposal.mjs` accepts the same canonical, caller-supplied 14-row history
observation and digest as the existing planner. It outputs an analysis-only list
of 50 pending actions and the two separately deferred, unrecorded originals.
Two conflicting retention originals remain excluded and have distinct proposed
branch versions; the forward candidate has its own proposed version. The input
is an assertion and may be stale. The proposal performs no database access,
creates no migration files and cannot execute or write migration history. A
standard push from the original source directory is not qualified.

Two actions carry explicit managed-portability blockers. The original deployment
identity migration remains the required predecessor; its existing binder only
accepts a self-hosted profile, so it must not be used to claim a managed
binding. An independently qualified managed binder and an explicit decision on
its scheduler-function preimage are needed before binding. The stopped-
admission source implements local-VM executor recovery and contributes to
retention history: its managed applicability, exact predecessor and recovery
semantics require independent review. The manifest does not assume either
question is resolved or fabricate an applied history record.

The proposed latest version is `20261114110400`, after both deferred source
versions. Finishing those features later therefore requires a separately
reviewed forward version and history plan, including a fresh predecessor and
data review; never record either old WIP source as executed without executing
its exact bytes. This proposal does not allocate a future version or show that
either feature can later be enabled without additional work.

## Existing application and data dependencies

Both `COLLECT_ADMIN_TOTP_ENABLED` and `COLLECT_ADMIN_TOTP_RECOVERY_ENABLED` must
be other than the exact string `true` for the current Edge handler to keep the
WIP paths disabled. With the feature flag disabled, the Admin MFA API routes
return 410. Enabling either feature or recovery path can call the omitted
functions or session columns. The Flutter Admin security/authenticator screens
and API client already contain MFA flows; the session response's `mfaAvailable`
value affects which controls and calls are used. Disabling an existing user's
MFA or recovery path is a material compatibility concern even if a synthetic
schema installs successfully. A real browser/session flow, exact deployed flags,
existing managed factors, pending session rotation/recovery data and target
behavior have not been established. The local installation journal records a
different later-migration lane, and its current WIP objects and data cannot be
assumed absent in a transfer.

Existing focused JS tests for disabled routes and mocked persistent refresh pass
with a synthetic fence. They do not prove ordinary Admin login, refresh, legacy
factor interpretation or recovery on this candidate database against the real
provider. Live data, external requests, the production executor, recovery,
concurrent actors, fencing and traffic cutover are outside this experiment.

## Tests

From the repository root:

```sh
node --test --test-concurrency=1 \
  scripts/supabase/retention-convergence/deferred-mfa/history-proposal.test.mjs \
  scripts/supabase/retention-convergence/deferred-mfa/ordered-deferred-fixture.test.mjs
```

The fixture requires the pinned Node/`pg` dependency and owned PostgreSQL 17
binaries. It never connects to the active local source or cloud project. This
directory does not authorize production use.
