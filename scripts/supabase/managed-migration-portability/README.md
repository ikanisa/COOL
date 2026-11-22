# Managed Supabase migration portability inventory

This read-only inventory uses the retained migration lock in
`supabase/managed-migration-history` and verifies the exact file names, order
and SHA-256 values in that historical prefix. It reports each predecessor,
literal catalog lookups, textual definitions, selected function-body preimages
and markers needing review. It runs entirely offline and prints to stdout.

```sh
python3 scripts/supabase/managed-migration-portability/portability.py
```

The result always has `managed_deployment_decision: "NO_GO"`: a consistent
source inventory cannot qualify an existing cloud database. Exit 0 means only
that an inventory was produced; exit 2 means the inputs were refused. Missing,
extra, reordered, duplicated, changed, nonregular, symlinked or concurrently
changing inputs within the pinned prefix are refused. Later migration versions
fall outside the inventory. Each result records the count and lock hash.

The inventory explicitly identifies the self-hosted-only profile binding in
`20261101013157_collect_deployment_identity.sql`, the local-VM recovery step in
`20261110181002_collect_local_stopped_admission.sql`, function-definition
dependencies, the Realtime metadata pin and source comments marking drafts.
The local stopped-admission step modifies a retention function whose later
preimages are checked by subsequent migrations. A managed implementation must
resolve those relationships; silently omitting or editing an earlier step can
make later checks fail. A source comment alone is historical evidence, not a
determination of present deployment status or approval.

The dependency and preimage extraction is **lexical and incomplete**. It does
not parse the full SQL language, resolve overloads or dynamic SQL, or prove that
the most recent textual definition installed the object. Tuple and inline hash
matches are candidates. For example, an earlier `CREATE` statement can be
conditionally executed or dynamically rewritten. Read each cited migration and
independently compare its full function body, ownership, security-definer flag,
configuration, ACL, trigger, constraint, managed schema and fence conditions.
A missing textual predecessor may be provider-supplied, dynamic or unrecognized;
it is not proof of either success or failure.

For a migration with extracted candidates, this command **prints** a bounded,
read-only PostgreSQL catalog query; it does not connect or execute it:

```sh
python3 scripts/supabase/managed-migration-portability/portability.py \
  --probe-sql 20261110181002_collect_local_stopped_admission.sql
```

The query compares candidate `pg_proc.prosrc` SHA-256 values and displays owner,
security-definer, configuration and ACL metadata. It must be interpreted only
at that migration's exact predecessor checkpoint: comparing against a later
schema is not a valid preimage test. A match does not check every attribute or
constitute managed compatibility. An absent dependent type can make
`to_regprocedure` fail; a failed query is unconfirmed, not a match. No tool in
this folder applies a migration, binds a deployment identity, changes routing,
or initializes/stops a non-fixture service.

## Verification

Offline unit tests use temporary synthetic source trees. To additionally test
the generated query, provide the path to PostgreSQL 17 binaries. The test creates
its own synthetic cluster and Unix socket, disables TCP listeners, creates only
synthetic objects, verifies matching/changed/missing function bodies, stops the
cluster and removes the test files. It does not target the existing local stack
or a hosted project.

```sh
COLLECT_PORTABILITY_PG_BIN=/path/to/postgresql-17/bin \
  PYTHONDONTWRITEBYTECODE=1 \
  python3 scripts/supabase/managed-migration-portability/test_portability.py
```

Without `COLLECT_PORTABILITY_PG_BIN`, the PostgreSQL fixture is skipped and must
not be reported as passed. The synthetic query check does not replay the Collect
chain or prove managed Auth/Realtime compatibility, recovery, data migration,
operational readiness or production acceptance.
