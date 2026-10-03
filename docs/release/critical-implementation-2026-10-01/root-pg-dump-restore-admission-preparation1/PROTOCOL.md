# Archive adapter input contract

This is a private proposed version 1 contract. It adds no operation to the existing `collect_postgres_admission` or backend release approval schema. All actual examples retained in this packet are synthetic engineering inputs; there is no usable live approval. A protected reviewer must independently verify source semantics, runtime provenance, operation permission, target and compatibility before supplying any real inputs.

## Required environment and transport

| Input | Exact contract |
| --- | --- |
| `COLLECT_POSTGRES_ARCHIVE_PYTHON` | Absolute executable path for the shell helper; no discovery. External runtime provenance gate remains open. |
| `COLLECT_POSTGRES_ARCHIVE_ADMISSION` / `_SHA256` | Absolute regular single-link JSON file and its full lowercase SHA-256. |
| `COLLECT_POSTGRES_ARCHIVE_OPERATION` / `_SHA256` | Absolute regular single-link operation JSON file and full SHA-256. |
| `PSQL_BIN`, `PG_DUMP_BIN`, `PG_RESTORE_BIN` | Optional; if present must exactly equal the corresponding bound path. No PATH/Homebrew fallback. |
| `PGSERVICEFILE` | Explicit owner-only service file with the single bound `collect_readiness` target. URI credentials are converted by the existing helper to private temporary files. |
| `PGPASSFILE` | Explicit regular owner-only file, if needed. `/dev/null` is used otherwise. Passwords and raw service bytes are not recorded in receipts. |
| `SUPABASE_PROJECT_REF` | Existing base guard when the operation target is Supabase. This is not permission or authorization evidence. |

Local probes use the unchanged base `local_environment()`. Only controlled service/password file paths and fixed connection timeout enter the remote client environment. The adapter rejects service options outside host, port, user, dbname, sslmode, sslrootcert, connect_timeout and application_name. Hosted capture requires `verify-full` plus the exact manifest-pinned root certificate. Local rehearsal requires TLS disabled with no root certificate option. No ambient PGPASSWORD, database URI, token, PGOPTIONS, loader or Python-path overrides enter a client.

## Manifest: exact keys, no extras

| Field | Constraint |
| --- | --- |
| `schema_version`, `kind` | Integer 1; `collect_postgres_archive_admission`. |
| `review_reference` | Bounded 1–160 character reference metadata; never proof of reviewer identity. |
| `adapter_sha256` | Full SHA of the exact new adapter file. The adapter also authenticates the unchanged sibling base module to `9af50d207472eb8a69d5f7c712928b17305fcfb705408f42ad652c39b8bdac92`. |
| `base_admission` | `{path, sha256}` for an original v1 base manifest. Its query/migration cohort and target/timeout guards remain unchanged. |
| `clients` | Exactly `pg_dump` and `pg_restore`; each `{path, sha256, version}` with an absolute regular single-link executable and version exactly `17.6`. psql, dump and restore paths must differ. |
| `profiles` | Nonempty unique subset of `public_schema`, `public_data`, `full_custom`, `restore_custom`. |
| `server_version_num` | Integer exactly 170006. Other client/server cohorts cannot be authorized by altering JSON. |
| `artifact_limit_bytes` | Integer 1 KiB–1 GiB; applies to capture and admitted restore input. |
| `tls_rootcert` | Null for local use, or exact `{path, sha256}` bounded regular file reference for hosted capture. |

The archive manifest and operation JSON are each at most 16 KiB; duplicate keys and unknown fields are refused. Client input reads are bounded to 128 MiB, base/adapter to 64 KiB, source binding to 32 MiB and service/password to 8 KiB. The inherited version/server/operation bounds are at most 10/30/600 seconds. Actual fixtures use unchanged one-second probes and operations, with smaller explicit timeout negatives; the outer focused process has 90 seconds and 4 MiB per stream.

## Operation binding: exact keys, no extras

| Field | Constraint |
| --- | --- |
| `schema_version`, `kind` | Integer 1; `collect_postgres_archive_operation_binding`. |
| `review_reference` | Bounded reference metadata. |
| `approved_at_utc`, `expires_at_utc` | UTC timestamps; current time within the interval, positive window at most 24 hours. This time check is not review authentication. |
| `manifest_sha256` | Exact archive manifest whole-byte digest. |
| `operation` | `dump` or `restore`. Hosted restore refuses before local tools because no shipping adapter exists. |
| `profiles` | Nonempty unique subset of manifest profiles; full custom dump cannot mix with partial profiles. Restore requires exactly `[restore_custom]`. |
| `target` | Exact single object from the base target list, including its host, port, user, database, kind and project reference. |
| `source_binding` | Exact `{path, sha256}`; opaque pinned bytes, not validated source-contract semantics. |
| `output_directory` | Absolute path without parent traversal or symlink parents; owned directory must be exactly 0700 at execution. |
| `input` | Null for dump; restore object with `archive: {path, sha256}`, exact integer `bytes` and `capture_receipt: {path, sha256}`. |

Restore input must begin `PGDMP`. Its pinned capture receipt must bind full-custom dump, same manifest/source/archive digest and size, and server 170006. The original inode is held open and passed as stdin; later same-byte path/inode substitution refuses. This receipt is not an approval or a recovery comparator result.

## Exact command profiles

Caller helper input must begin `service=collect_readiness`. These complete arrays are matched exactly before any target read; extra flags, alternate file names, URIs, host/dbname/role/create/clean/snapshot/list/jobs substitutions are refused.

| Profile | Following caller arguments | Actual tool invocation |
| --- | --- | --- |
| `public_schema` | `--schema=public --schema-only --no-owner --no-privileges --file=DIR/public_schema.sql` | Absolute pg_dump, `--dbname=service=collect_readiness -w`, same four profile flags; stdout to exclusive 0600 artifact. |
| `public_data` | `--schema=public --data-only --no-owner --no-privileges --format=plain --file=DIR/public_data.sql` | Absolute pg_dump, same fixed service/no-password prefix and five profile flags. |
| `full_custom` | `--format=custom --lock-wait-timeout=10s --file=DIR/database.dump` | Absolute pg_dump, fixed service/no-password prefix and the two profile flags. |
| `restore_custom` | `--exit-on-error --single-transaction EXACT_ARCHIVE_PATH` | Absolute pg_restore, `--dbname=service=collect_readiness -w --exit-on-error --single-transaction`; archive input through its admitted open fd. |

Every operation rechecks byte and inode identity, reads actual banners without credentials, validates credentials and target, executes the exact target-bound read-only server probe, repeats actual banners immediately before the operation, then rechecks bindings after completion. The probe is `BEGIN READ ONLY; SET LOCAL statement_timeout='15000ms';` plus the unchanged base numeric `server_version_num` query, then `COMMIT`. Exactly one six-digit numeric row is required. Before restore, `pg_restore --list` uses the same admitted input fd with a credential-free environment; only the TOC digest is retained.

Version observation and remote operation use different connections. They cannot prove an atomic database identity/version fence. A remote read is required to observe the server; all mutations follow that read. A local single-transaction restore is still a write and requires separately supplied authorization when used outside fixtures.

## Receipts and failure semantics

Capture emits `ARTIFACT.admission.json`; restore emits `restore.admission.json`, both exclusive 0600 files. The receipt binds target, exact client file digests and observed cohort, operation/manifest/source digests, artifact digest/bytes and profile. Restore also records its capture receipt and offline TOC/output digests. It records `client_completed_artifact_bound`, not a recovered system. Human review authentication, source semantics, encrypted destination, full catalog/ACL/projection recovery and production readiness are explicitly false.

Raw child output is bounded and never emitted on refusal. Stderr warnings, nonzero exits, malformed version/server output, timeout and artifact overflow fail closed. The runner retries only EAGAIN/EWOULDBLOCK read readiness races within its original monotonic deadline and kills/reaps its owned process group on failure. A successful parent with a detached-stdio descendant is refused, and stream closure must complete before terminal success within the same operation deadline. Group cleanup has a separate fixed five-second deadline and requires observed absence. SIGKILL EPERM triggers only bounded reaping and absence verification; a surviving group keeps the original permission error fatal. It deletes only the artifact inode it exclusively created; existing user files are not removed. Success receipts are never generated on these failures.

The API does not install certificates, download clients, open a provider session, find Docker, create a project, apply a migration or grant itself permission. Shell `.env` handling and credential transport retain the original consumers' behavior. Real approved input generation and the missing container/hosted/full-comparator integrations require separate review.
