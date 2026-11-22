# Synthetic ordered deployment-identity qualification

This owned PostgreSQL 17 experiment starts from the sixteen original predecessor
positions, executes `20261101012309_collect_admission_archive`, then executes
`20261101013157_collect_deployment_identity` and the separately reviewed
managed binder compiler's generated SQL. It does not connect to Supabase or the
active local source, accept a supplied connection or credential, or dispatch
production changes. Its database is named `postgres` only inside its own new,
private-socket cluster because the reviewed binder requires that exact name.

The fixture executes the actual predecessor SQL in order. The hosted Realtime
migration is first observed to reject the fixture's different metadata; the
reviewed synthetic Realtime variant is then executed and its actual bytes are
recorded in the synthetic history. The other fifteen original predecessors use
their pinned original SQL. That disposable initial history is created after
successful fixture setup; it is not a production migration procedure.

The archive action executes its exact original body and records the exact
original source in one transaction. The identity action similarly checks a
selected catalogue/data/history digest under locks, executes the exact identity
body and records its exact complete original SQL in the same transaction. It
checks the resulting empty identity table, owner and table ACLs, column and
constraint digests, immutable trigger, selected predecessor function hashes,
complete ordered history and catalogue stability after the history insert.
The synthetic fixture refuses any event trigger. Failure after DDL or after the
history insert rolls back both; a changed predecessor history and a catalogue
change committed while a control-table lock was awaited are refused. This is
not a complete hosted catalogue or privilege attestation.

The original identity migration installs a **self-hosted** binding function;
it does not bind a profile. The test confirms it refuses a managed profile.
After both original migrations have actually run and appear in the 18-position
fixture history, the existing separate managed compiler consumes a fresh
fixture preimage and produces its real-capable SQL. In one scenario, a
synthetic unresolved external obligation makes that SQL reject and roll back
the managed binder installation and identity insert. In another, clean
synthetic scenario, it installs the separate managed binder and binds a managed
profile, preserving the synthetic primary Auth/application link and leaving
migration history at 18 rows. The binder is a separate unversioned candidate;
no history entry is fabricated for it. These outcomes do not prove real
identity, absence of a real external effect, or live binding.

The fixture emulates selected provider roles and role grants in a local
cluster. Their names, privileges, OIDs and TLS are not provider observations.
Realtime/Auth/Storage and scheduling interfaces are synthetic. Earlier cloud
observations showed only 14 migrations and outstanding historical work; they
cannot stand in for the fresh post-18 preimage and exclusion required by a
managed operator. The live predecessor history, fence and external effects
must be resolved without changing the confirmed cloud-primary account.

The tested managed SQL remains an offline compiler output. This directory adds
no authenticated production dispatcher, secure one-use journal, unknown-commit
reconciliation or automatic retry. The independently reviewed binder README
sets out its provider-administrator trust, scheduler pin and active-work gates.
Selected advisory/table locks do not exclude privileged actors that ignore the
protocol. Backups, actor closure and cross-service recovery remain separate
requirements. Source, snapshot and test results do not authorize installation.

## Test

```sh
cd '/Volumes/COLLECT-STAGING-20261109/main-source'
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
  /Volumes/PRO-G40/Development/Node/bin/node --test --test-concurrency=1 \
  scripts/supabase/managed-identity-history-next/synthetic-identity-chain.test.mjs
```

Four PostgreSQL launchers and their four wrapped executables are pinned before
and after both owned-cluster fixtures. The OS, shared libraries, Node runtime,
module tree and pre-start code remain trusted. The evidence manifest pins the
specific source/test inputs; it is not a hermetic environment or production
qualification. A fixture whose shutdown cannot be confirmed is retained.
