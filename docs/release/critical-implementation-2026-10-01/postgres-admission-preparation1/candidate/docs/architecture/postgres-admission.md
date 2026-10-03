# PostgreSQL client and server admission

This control binds a local `psql` executable and a reviewed compatibility
matrix. It does not install a client, select one from PATH, create approval,
authenticate a reviewer or certify a hosted database. No real reviewed
PostgreSQL manifest is supplied by this implementation.

Operators supply `COLLECT_POSTGRES_ADMISSION`, an absolute path to a regular
single-link JSON file, and `COLLECT_POSTGRES_ADMISSION_SHA256`, the whole-file
digest retained through the review process. `PSQL_BIN` may be absent or name
that manifest's exact absolute executable path. A different override, changed
bytes, symlink/parent symlink, hard link, unexpected version output, unbounded
manifest, unknown schema or absent matrix fails before a database request.
An unrelated PATH executable is never considered. Version probes receive a
small environment without database/release credentials or loader overrides.

The manifest has exactly these top-level fields:

| Field | Required contents |
| --- | --- |
| `schema_version`, `kind` | Integer `1`, `collect_postgres_admission` |
| `review_reference` | Nonempty ASCII review reference; metadata alone does not authenticate review |
| `client` | Exact `path`, whole-file `sha256`, exact PostgreSQL `version` |
| `server_matrix` | Bounded rows with that `client_version`, inclusive `server_version_num_min`/`server_version_num_max` in one server major, and applicable `query`, `migration`, `restore` operations |
| `targets` | At most eight exact host, port, user and database tuples; a Supabase target includes its project reference; local rehearsals are limited to explicit loopback targets |
| `timeouts` | Finite positive `version_seconds` (maximum 10), `server_seconds` (maximum 30), `operation_seconds` (maximum 600) |

The code does not supply a default compatibility matrix or infer one from
matching major numbers. A reviewer must bind the exact client and server
range appropriate to the operation. The synthetic tests use `17.6` and
`170006` only to exercise admission; those values are not a live approval or
an observation of the production server.

The first server observation is this exact read-only query against the
already bound target:

```sql
select current_setting('server_version_num')::integer as server_version_num;
```

The server cannot be observed before that first remote read. A single integer
response must match a reviewed matrix row before caller SQL runs. Direct
`psql` calls use the same owner-only service/password files for the read and
the operation, reject connection argument overrides, and recheck files,
manifest and client identity between the two. The service file may retain
existing TLS and keepalive parameters, but connection/session substitutions
such as `hostaddr`, another service or `options` are refused.

Both the version query and subsequent operation use `-X` and `-w`: PostgreSQL
documents that these disable startup files and password prompting. Arguments
otherwise retain the repository's existing SQL/file/variable calling pattern.
The wrapper is a toolchain/target control, not a SQL authorization sandbox.
Its trusted callers still own reviewed SQL, source integrity and operation
authorization. [PostgreSQL 17 psql documentation](https://www.postgresql.org/docs/17/app-psql.html)

`server_version_num` is a PostgreSQL preset parameter intended for a numeric
version comparison. Server names, project listing metadata and a successful
client `--version` do not supply this observation. [PostgreSQL 17 preset options](https://www.postgresql.org/docs/17/runtime-config-preset.html)

## Backend approval compatibility

The existing backend approval schema and its target, source, reviewer/time,
operation, Supabase main/companion and Deno bindings are retained. An
edge-only approval keeps exactly the existing three toolchain members.
Approvals containing `migrations` or `strict_production_readiness` additionally
require this toolchain member:

```json
"postgresql": {"manifest_sha256": "<independently retained whole-file digest>"}
```

That placeholder is deliberately invalid. A pre-existing database approval
without the new binding is refused before remote requests and requires
review through the same existing approval process. The admission module is
included in backend source integrity and is copied into the reviewed export.
The controller checks the matrix before project visibility/migration reads,
again before each mutating controller command, and through the management
transport guard before each database request, including separate migrations
in a management fallback batch. The guard's own exact version observation
uses the same reviewed helper and bounded transport without recursively
calling itself. It never applies SQL or retries an uncertain write.

The delivery receipt records manifest/client digest, exact observed version,
operation and the fact that a target-bound read occurred. It explicitly keeps
human review authentication and release acceptance false. Existing metadata
and mutation/readback guards remain active.

Standalone production readiness admits the client and project before its
first database observation, compares the observed server before its later
checks, and uses the shared direct wrapper when a direct/fallback call is
needed. Other direct scripts using `collect_psql_url_service` inherit the
same client and pre-operation server checks. Consumers using a raw Docker
client, `pg_dump`, or an embedded SQL client are not silently treated as
covered by these helper changes.

## Remaining acceptance

No real manifest/client provenance or compatibility approval has been
provisioned. This proposal's checks use synthetic executable clients and
transports; they do not observe a hosted or local PostgreSQL server, run a
migration/restore, invoke Docker, or establish installed tool provenance.
Local migration and restore rehearsals still need their immutable container
identity and exact client/server observation bound to a reviewed matrix.
`pg_dump` and restore archive compatibility need their own reviewed tool
bindings. Source/test equality alone cannot close that ARC-08 acceptance.

An observation preceding a write cannot eliminate a subsequent remote
upgrade/connection race. TLS, endpoint authentication, approved topology,
server change controls and transaction-level requirements remain separate
operational controls. A digest binding cannot prove that an untrusted
reviewer chose a genuine PostgreSQL binary or an appropriate matrix.
