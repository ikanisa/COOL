# Current PostgreSQL read-only reconciliation

This is a narrowly scoped, real-callable comparison component. It does not
import, update, insert, delete, change DDL, merge principals, alter a fence or
authorize deployment. No real source/target contract or approved credential
producer is supplied here; this directory has only been exercised against a
fresh, disposable synthetic PostgreSQL cluster.

## What it checks

An independently reviewed contract pins the exact source and target identity
descriptors and a source-set digest. For each database the component opens one
`REPEATABLE READ READ ONLY` transaction, checks the same backend, PG17, UTF-8,
database name, session and current role, and the exact fence project, baseline,
source hash, epoch, mode and operation ID. The source additionally has to match
the self-hosted deployment profile's recorded and recomputed hash. The managed
client must use the reviewed Supabase direct endpoint as `postgres`, or the
`aws-0-eu-north-1` session pooler as the project-qualified `postgres` user,
on port 5432. TLS must verify the server hostname and the repository's pinned
Supabase database root certificate (DER SHA-256
`807025ad50d4ed219d2c9c7d299c004f824eb00cf7f65afef607d07b72e6cafa`).
Other roots, hostname overrides and custom verification callbacks are refused;
a provider certificate rotation may therefore require a separately reviewed
pin update. The local source endpoint is an
explicitly pinned Unix socket or `127.0.0.1`; that local transport depends on
the host's integrity. A separate `synthetic` target is limited to fixture-named
databases on the test's private Unix-socket path.

Before anchoring either transaction's snapshot, the component takes ordinary
AccessShare locks on all declared relations for that database. These locks can
delay conflicting DDL; they do not stop ordinary data writers. They close the
gap in which a repeatable-read catalogue snapshot could hide a later schema
change. Every selected relation must be an ordinary, non-inherited table with full
table SELECT privilege and no effective row-security filtering for the reader.
It must have exactly the reviewed set of non-dropped columns, their PostgreSQL
type, nullability, collation, identity/generated flags and default-expression
hash, and the exact reviewed `pg_constraint` names, kinds, flags and definition
hashes. The 16 KiB expression/definition limit and hash method match the
repository's catalogue-capture convention: SHA-256 of the exact UTF-8
`pg_get_expr` / `pg_get_constraintdef` text under `search_path=pg_catalog`.
Check any separately captured catalogue uses the same PostgreSQL/deparser and
search-path settings. Indexes that are not constraints, trigger bodies,
policies, privileges beyond the immediate read, functions, partition bounds,
and provider settings are not covered.

Only explicitly selected columns are read. Supported compared types are
`text`, `character varying` (with or without a bounded length), `uuid`,
`boolean`, `smallint`, `integer`, `bigint`, `numeric` (including declared
precision and scale), `timestamp with time zone` (including declared
precision), `jsonb` and `bytea`. Other column types may appear in the reviewed
catalogue but must have `compare: false`. SQL NULL remains distinct from every
non-NULL value, including JSON null. Comparison uses these representations:

- `numeric` uses PostgreSQL `trim_scale` text: numerically equal values such
  as `1.0` and `1.00` match, without JavaScript floating-point conversion. This
  deliberately does not prove preservation of the stored display scale.
- `timestamp with time zone` uses PostgreSQL's exact numeric epoch extraction,
  preserving the stored instant and microseconds independently of session
  timezone or date style. PostgreSQL does not retain the original input zone.
- `bytea` uses lowercase hexadecimal for the stored bytes, independently of
  the session's `bytea_output` setting. Limits count the encoded text, so a
  value with `n` bytes consumes `2n` bytes of the comparison allowance.
- `jsonb` uses PostgreSQL 17's textual output for its stored value. Input
  whitespace and object key order are already discarded by `jsonb`; its
  output can preserve fractional numeric trailing zeros. Thus two JSONB
  values that PostgreSQL considers equal can be reported as changed, such as
  `1.00` versus `1.0`. That conservative difference is not an automatic
  conflict resolution or a byte-for-byte comparison of the original JSON text.
  JSONB columns are refused as keys or unique-check columns because that
  textual representation does not implement PostgreSQL's JSONB equality.

PostgreSQL documents [numeric scale trimming](https://www.postgresql.org/docs/17/functions-math.html),
[timestamp epoch extraction](https://www.postgresql.org/docs/17/functions-datetime.html),
[JSONB output](https://www.postgresql.org/docs/17/datatype-json.html) and
[binary encoding](https://www.postgresql.org/docs/17/functions-binarystring.html).
The reader checks row, individual rendered-cell and total rendered-byte limits
before returning cells to the application; the checks do not bound the server's
intermediate memory or CPU when rendering an oversized numeric or JSONB cell.
It rejects duplicate or NULL reviewed keys. Its
declared single-column unique checks detect duplicate values within each side,
same value under different keys, same key with different values and NULLs. A
`principal_email` check uses ASCII-only lowercasing and trimming ASCII spaces;
unhandled Unicode or malformed/non-ASCII whitespace causes refusal. An
`principal_link` check uses `exact` normalization. These are conservative
collision signals, **not** a determination that two accounts are the same
person or are authorized to share data. Other unique or partial business keys,
cross-table relationships and nullable uniqueness semantics need separate work.

For each selected `text` or `character varying` key or unique-check column,
the reader verifies the named collation in each actual database is
deterministic. It refuses a nondeterministic or missing collation before row
extraction because byte-distinct strings can compare equal under that
collation. Non-key selected text is still compared by bytes, so it can be
reported changed even when a nondeterministic collation considers it equal.
The reader pins only the collation's schema and name and checks its
deterministic flag; it does **not** pin or compare provider, locale, collation
library/version or index operator class, nor detect collation-specific unique
expression or partial indexes. Matching names therefore do not prove matching
sort order or healthy existing indexes. Those properties and any relevant
unique-index semantics need separate review on both databases before a real
reconciliation. See [PostgreSQL collation support](https://www.postgresql.org/docs/17/collation.html)
and [collation version functions](https://www.postgresql.org/docs/17/functions-admin.html).

Output contains relation names and aggregate counts, never individual cells,
IDs, e-mail addresses, keys, row digests or credentials. `selected_columns_only`
means a match covers only selected fields, not an entire row. Unselected fields,
unlisted tables and NULL principal identities cannot be inferred from a zero
conflict count. All snapshots are independently anchored: neither simultaneity
nor quiescence of the two systems is proven. `source_set_sha256` is an
independently supplied reviewed assertion, not a repository hash computation.
The library checks metadata preimages and TLS but does not independently attest
the physical host or protect against a compromised trusted database/server.

## Contract and operator interface

`reconcile.mjs` exports `identityDigest(value)`, `contractDigest(value)`,
`validateReconciliationInputs(...)`, and `reconcileCurrentPg(...)`. The digest
is SHA-256 of recursively key-sorted, compact UTF-8 JSON; array order is
significant. A reviewer must independently review and retain the full contract,
both identity descriptors, the source-set digest and the resulting contract
digest. The digest must not be computed from an unreviewed input and immediately
treated as an authorization. The public digest helper can be used during
review; comparison takes the separately supplied digest as its pin.

Each identity object has exactly these fields:

```json
{
  "transport": {"kind": "local", "host": "127.0.0.1", "port": 54322},
  "database": "postgres", "session_user": "postgres", "current_user": "postgres",
  "project_ref": "rrlduytparvsjfmegalh", "baseline_manifest_sha256": "<64 lowercase hex>",
  "source_sha256": "<64 lowercase hex>", "epoch": "<positive decimal string>",
  "mode": "<open, quiescing, or fenced>", "operation_id": "<UUID>",
  "profile_sha256": "<64 lowercase hex>"
}
```

The target descriptor sets `transport.kind` to `managed`, gives the reviewed
direct hostname or session-pooler hostname and port, and sets `profile_sha256`
to `null` because the source-only deployment profile is not assumed present
on managed Supabase. Every value above is illustrative and must be independently
established for the actual run. Fence fields are exact preimages; `open` does
not mean that writers are stopped.

The contract has exactly `format`, `source_set_sha256`,
`source_identity_sha256`, `target_identity_sha256`, `limits` and `relations`.
The format is `collect.current-pg-reconciliation.v1`; identity hashes are the
digests of the corresponding exact descriptors. `limits` contains integer
`rows_per_relation` (1–10,000), `bytes_per_cell` (1–4,096), `bytes_total`
(1–16,777,216 across both databases and all relations),
`statement_timeout_ms` (100–30,000), and `total_timeout_ms` (at least the
statement timeout and at most 120,000). The total byte bound counts selected
text values; it is not a bound on all PostgreSQL backend or Node heap use.

Each relation has `schema`, `name`, `columns`, `constraints`, `key` and
`unique_checks`. Schemas are restricted to `app`, `private`, `collect_sms` and
`auth`; no arbitrary SQL or identifiers are accepted. Each column specifies
`name`, PostgreSQL `type`, Boolean `nullable`, Boolean `compare`, `collation`
(`null` or `{ "schema": "...", "name": "..." }`), `default_sha256`
(`null` or a digest), `identity` (`""`, `"a"` or `"d"`) and `generated`
(`""` or `"s"`). Declare all columns even if only some are compared.
`constraints` contains all table constraints, each with `name`, `kind`,
`definition_sha256`, `deferrable`, `initially_deferred`, and `validated`.
`key` is an array of one or more selected column names. A `unique_checks` item
has `column`, `classification` (`principal_email` or `principal_link`) and
`normalization` (`ascii_lower_trim` for email or `exact` for a link). These
declarations are examples of reviewed scope, not automatically complete
business-key checks.

The executable `operator.mjs` takes **one** non-secret argument: the reviewed
contract SHA-256. Its stdin must be a private pipe containing one bounded JSON
object, with this exact outer structure:

```json
{
  "format": "collect.current-pg-operator.v1",
  "contract": {}, "sourceIdentity": {}, "targetIdentity": {},
  "credentials": {
    "source": {"user": "<database user>", "password": "<secret>"},
    "target": {"user": "<database user>", "password": "<secret>"}
  }
}
```

This is a shape example, not an executable reviewed plan. A trusted supervisor
must assemble the complete values and stream them directly into
`node scripts/supabase/current-pg-transfer/operator.mjs <reviewed-contract-sha256>`;
stdin is capped at 1 MiB and ten seconds. Do not put credentials in arguments,
environment variables, shell history, ordinary output files or logs. The
supervisor must use a trusted Node executable, clean environment and private
pipe, and must keep stdout/stderr and PostgreSQL server logging appropriately
restricted. `NODE_OPTIONS`, preloads, a hostile same-user process, custom system
trust roots, process inspection, swap and crash/heap dumps are outside this
component's protection. Input Buffers are overwritten where feasible; Node/pg
and immutable JavaScript strings cannot be reliably erased.

The operator rejects nonempty PostgreSQL, Node, loader, TLS and proxy override
environment variables and Node execution flags before reading its input. This
does not undo code or configuration applied before the check, so the launcher
must still start a trusted Node binary with a clean environment. Connected
library clients with startup options, replication or binary mode are refused.

For library use, pass two already connected, dedicated `pg` 8.16.3 Clients and
the same reviewed inputs. After connection admission the library consumes and
closes both Clients even on failure; on validation errors before admission the
caller retains responsibility for them. Transaction-local configuration,
AccessShare `LOCK TABLE`, and `ROLLBACK` accompany SELECTs. A timeout or read error closes both sockets;
no data writes or retries are attempted.

## Reproduce the isolated tests

From the active repository root:

```sh
node --test --test-concurrency=1 scripts/supabase/current-pg-transfer/reconcile.test.mjs
```

The test creates its own fresh private PostgreSQL 17 cluster and databases,
listens only on a private Unix socket, inserts synthetic data, and stops and
removes that cluster. It never connects to the existing local application or to
Supabase. Set `COLLECT_SYNTHETIC_PG_BIN` to a PostgreSQL 17 binary directory if
the installed test toolchain has moved. The package's existing pinned `pg`
8.16.3 dependency is used without changing its lock or installing packages.

## Remaining work before a real run or any import

Independently capture and review the actual source and managed metadata,
complete per-relation column/constraint contracts and all relevant principal
and business unique checks; bind the exact current source set and fence/profile
preimages; provide an authorized private credential-producing supervisor;
review the deployed database roles, transport and logging; and establish
appropriate fencing, capture, custody and recovery. The `auth` catalogue has
not been qualified by the earlier app/private catalogue exporter. Larger
tables, types other than the explicitly listed numeric/timestamp/JSONB/bytea
forms, arrays, partitions and relations
outside the fixed schemas require separately reviewed support. Neither this
tool nor its synthetic tests supply a current-schema importer, identity
resolution, object transfer, cross-database atomic snapshot, replay-safe write,
full recovery or production acceptance.
