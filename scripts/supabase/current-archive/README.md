# Selected current Collect SQL archive

This Node 24 operator captures the selected `app` / `private` native SQL data and descriptors from Collect project `rrlduytparvsjfmegalh` in organization `ghnjnepwvwknswrwzepn`. It plans from current provider metadata, requires an independently reviewed exact plan SHA, captures once through the fixed read-only Management query, encrypts the response before persistence, and verifies it only in a new inert local database.

The package is an operational archive of selected SQL state. It does not restore managed Auth credentials/MFA/sessions, Storage metadata or object bytes, Edge secrets, provider effects, key custody, operational functions or a production database. Private application identity rows, when selected, are archived as application data; this is not a full managed Auth backup. No RPO/RTO, mutation fence, cutover approval or full recovery acceptance follows from this operation.

## Prerequisites

Use the repository-pinned Node 24.19.0. Planning and capture need only Node built-ins. Local inert restore additionally uses the existing `pg` 8.16.3 dependency from `scripts/supabase/package-lock.json`; no new packages or lifecycle scripts are required.

The operator accepts one explicit Management API access token source: `--token-file /absolute/private/token` (physical current-owner directory 0700, single-link regular file 0600), or `--token-env COLLECT_ARCHIVE_ACCESS_TOKEN`. The latter names an already supplied environment variable; the argument is never a token. The variable is deleted from this process environment after reading. The tool does not discover credentials or reset a database password. Never put token values or a database connection string in arguments, logs or Git. The later local connection uses the same private-file contract.

Run from an environment without HTTP/HTTPS/ALL/NO_PROXY, Node preload/proxy flags or disabled TLS verification. The transport uses verified HTTPS to the fixed `api.supabase.com` endpoint, requires exact project/org/healthy identity, refuses every redirect and does not automatically retry. Source files and all private inputs must remain stable until the operation completes. Keep untrusted processes out of the operator account and private directories. JavaScript immutable strings and transient copies cannot be guaranteed erased from process memory; plaintext business rows are never intentionally written to a file or stdout.

Prepare an existing physical current-owner 0700 parent outside the checkout, and separate existing 0700 parent for keys. Every operation output directory and every capture key directory must be fresh, absolute and normalized. The operator creates 0700 directories and exclusive 0600 files. It refuses source-tree outputs, symlinked parents, reused attempt directories and nested artifact/key directories. Preserve partial files and any newly created inert database after failure; investigate before an explicitly new reviewed attempt.

## Explicit migration source set

Create a private 0600 JSON file in a 0700 directory, independently review its bytes and retain its SHA256. This file declares the already qualified runtime source manifest hash and the *entire expected curated destination migration history*, not the old 210-migration source chain. Its shape is:

```json
{
  "format": "collect.current-archive.sources.v1",
  "project_ref": "rrlduytparvsjfmegalh",
  "runtime_source_sha256": "<64 lowercase hex from the reviewed runtime manifest>",
  "expected_migration_count": 8,
  "migrations": [
    {
      "version": "<14 digits>",
      "name": "<lowercase migration name>",
      "path": "supabase/migrations/<version>_<name>.sql",
      "sha256": "<SHA256 of exact source file bytes>"
    }
  ]
}
```

The abbreviated example is intentionally not executable or admitted. The actual array must contain exactly the declared count, ordered by unique increasing versions, with exact physical source paths and hashes. The default source root is derived from this package location (the checkout root); `--source-root /absolute/physical/root` explicitly selects a separately retained source tree. No provider history or filesystem glob automatically adds a migration.

At an eight-migration epoch use a reviewed count/list of eight. After a ninth or tenth migration has been separately adopted, qualified and applied, create and review the new exact count/list of nine or ten and obtain a new provider candidate and plan review. Reusing an eight- or nine-migration plan against ten records fails closed; changed statements under the current version/name also require a new metadata candidate and independent review. The package has a hard ceiling of 32 explicitly listed destination migrations, not an unbounded history fallback. A source file hash is provenance; `observed_record_sha256` independently hashes exact provider-stored migration-record text. A matching version/name does not establish equal statements. The reviewer must compare the retained metadata records with qualified source before approving the plan.

## Plan, independently review, capture once

Example variables below contain paths or non-secret hashes only. Supply credentials through the private token file, never by editing these commands. Run from the checkout root:

```sh
node scripts/supabase/current-archive/operator.mjs plan \
  --source-set "$SOURCE_SET_PATH" --source-set-sha256 "$SOURCE_SET_SHA" \
  --token-file "$TOKEN_FILE_PATH" --output-dir "$FRESH_PLAN_DIR"
```

Planning makes one exact-project identity GET and one fixed read-only metadata POST. It writes `COMPILED_REQUEST.json`, `INTENT.json`, private `METADATA.private.json`, `CANDIDATE_PLAN.json` and a safe HTTP receipt. Metadata contains catalogue definitions and stored migration records; treat these private files as sensitive operational metadata even though no application/private rows are selected at this phase. Stdout reports the candidate path/hash/counts and `reviewed_plan:false`.

A separate review must check current project/source epoch, all relation/column/type/OID/catalogue/sequence descriptors, exact migration source and observed-record provenance, caps and the compiled read-only SQL. Record that review separately and retain the SHA256 of the exact admitted candidate bytes. Planning does not generate an approval, and the execute flag alone is not review evidence. There is no automatic plan-to-capture transition.

```sh
node scripts/supabase/current-archive/operator.mjs capture \
  --source-set "$SOURCE_SET_PATH" --source-set-sha256 "$SOURCE_SET_SHA" \
  --plan "$REVIEWED_PLAN_PATH" --plan-sha256 "$INDEPENDENT_REVIEWED_PLAN_SHA" \
  --token-file "$TOKEN_FILE_PATH" --output-dir "$FRESH_CAPTURE_DIR" \
  --key-dir "$FRESH_SEPARATE_KEY_DIR" --execute-reviewed-read-only yes
```

Capture regenerates only the fixed bounded SQL from the exact source-bound plan. It makes one project identity GET and one read-only capture POST. Within its requested repeatable-read/read-only transaction it checks the complete planned current metadata, column record hashes, exact observed migration-record hashes and stable sequence values. Native values travel as PostgreSQL text cells with explicit built-in type descriptors; JSON numeric decoding never passes native numeric cells through JavaScript Number. Unsupported built-ins/domains/arrays and any metadata/history/budget drift refuse the capture.

No raw response JSON or business rows are written. The AES-256-GCM envelope authenticates its canonical header, fresh 12-byte IV and 16-byte tag; a fresh 32-byte key is written separately. The package performs authenticated private readback. `RESULT.json` pins the raw receipt bytes, the complete receipt value, safe summary bytes and canonical full snapshot hash. Summary contains context, counts, names and hashes, not record cells. Retain the **returned RESULT SHA independently** for restore; retaining a mutable RESULT and receipt together without an independent hash is insufficient. Separate local directories do not establish independent/offsite key custody.

The transport deadline is 60 seconds, query bound 2 MiB, request bound 4 MiB, wire response bound 8 MiB and server payload bound just under 4 MiB. Catalogue/data limits may be reduced in library plans but never raised above fixed hard caps. Exceeding a cap is an unconfirmed/refused attempt; do not split or silently omit tables. Retain the failure and use a separately reviewed successor if the archive outgrows this bounded design.

A Management HTTP 201 with the final SELECT is not native PostgreSQL `ROLLBACK CommandComplete` evidence. The SQL requests trailing ROLLBACK; archive provenance keeps `native_rollback_command_complete_observed:false`. Two retained historical provider controls are compatibility provenance, not acknowledgement of a later request or a claim that Beta endpoint semantics cannot change.

## Exact bound new inert restore

Independently retain the capture result SHA outside the mutable archive directory. Put only the authorized synthetic/local admin URL for the `postgres` database in an explicit physical private 0600 file. Only literal `127.0.0.1` or `[::1]` PostgreSQL URLs are allowed, with no query/hash. No remote URL, password reset, managed restore or existing application database is accepted.

```sh
node scripts/supabase/current-archive/operator.mjs restore-inert \
  --capture-result "$CAPTURE_RESULT_PATH" \
  --capture-result-sha256 "$INDEPENDENT_CAPTURE_RESULT_SHA" \
  --local-connection-file "$PRIVATE_LOCAL_CONNECTION_FILE" \
  --output-dir "$FRESH_RESTORE_RECEIPT_DIR" --execute-reviewed-inert yes
```

Before opening PostgreSQL the operator verifies exact result, receipt and summary pins, authenticated archive bytes and canonical snapshot hash/project/runtime/non-fixture binding. It then creates a unique new `collect_archive_<UUID>_test` database from template0 on native PostgreSQL 17. It uses only the `archive_data` inert schema, native built-in columns and parameterized values; source schema/catalogue/migration definitions remain inert data. No operational functions, triggers, managed Auth/Storage schemas or application recovery DDL/DML are replayed. It checks empty database identity and native column/cell round trips, revokes PUBLIC on inert objects, preserves the new database and writes only a safe receipt. This supports examination and verification; it grants no production replay authority.

## Qualification

The maintained offline suite uses only mocks, synthetic keys/rows and private filesystem fixtures. No Management/GoTrue/Storage/provider or PostgreSQL calls occur:

```sh
npm run test:current-archive --prefix scripts/supabase
```

Root may additionally run the explicit native fixture for each of its three synthetic epochs, using only its authorized literal-loopback PostgreSQL 17 service and a fresh private artifact parent. It creates new source and inert databases and preserves them; it is deliberately excluded from `*.test.mjs` so unit test discovery cannot silently open PostgreSQL. Supply the synthetic URL through the environment without printing it:

```sh
COLLECT_ARCHIVE_FIXTURE_MIGRATIONS=8 \
  node --test scripts/supabase/current-archive/root-native.fixture.mjs
COLLECT_ARCHIVE_FIXTURE_MIGRATIONS=9 \
  node --test scripts/supabase/current-archive/root-native.fixture.mjs
COLLECT_ARCHIVE_FIXTURE_MIGRATIONS=10 \
  node --test scripts/supabase/current-archive/root-native.fixture.mjs
```

All three commands also require `COLLECT_ARCHIVE_TEST_ADMIN_URL` and an existing absolute physical 0700 `COLLECT_ARCHIVE_FIXTURE_OUTPUT_PARENT`. This remains an explicitly synthetic three-table/five-row fixture. It exercises real generated SQL/native columns and cells, encryption/new inert restore, same-version migration-record tamper refusal and local native rollback tags; the HTTP response envelope/status alone is simulated. Passing this fixture is local native qualification, not current hosted capture, provider rollback acknowledgement, complete managed recovery, production repair or cutover. The maintained successor itself requires Root's native qualification and review before actual use; retained predecessor receipts do not substitute for that check.

## Explicit curated exact-ten fixture

`root-curated.fixture.mjs` is a separate Root-only, non-skipping fixture, deliberately excluded from ordinary `*.test.mjs` discovery. It consumes the physical, unmodified, independently pinned integration source via `COLLECT_ARCHIVE_CURATED_SOURCE_ROOT` and `COLLECT_ARCHIVE_CURATED_INTEGRATION_SHA256`. Root supplies the independently reviewed exact SHA of the selected `INTEGRATION.json`; no input tree or manifest is discovered or automatically admitted. Every role in that exact manifest and the fixture's own bytes must remain unchanged before and after execution. Fixed production archive, immutable Auth, original-nine, hosted SQL10 and reviewed local-helper pins remain mandatory. Source3 SHA `afacc0e47ed330439a42a244b3dbfdb68e2e77ba936ec03ce0d068a094d2e34f` records provenance; a Root-reviewed successor may include the maintained fixture/caller overlays.

Root supplies `COLLECT_ARCHIVE_TEST_ADMIN_URL` through the environment: an explicit password-bearing `collect_test` URL at literal `127.0.0.1`, explicit port and `/postgres`. The fixture requires native PG17, the maintained `collect_test` SUPERUSER/BYPASSRLS local definer-owner profile, and all seven restricted `postgres` role flags false. Supply an existing physical current-owner 0700 audit parent in `COLLECT_ARCHIVE_FIXTURE_OUTPUT_PARENT` and Root's existing physical `pg` 8.16.3 package directory `/Users/jeanbosco/Library/Caches/collect-supabase-implementation-20261020/node_modules/pg` in `COLLECT_ARCHIVE_CURATED_PG_PACKAGE_ROOT`. Its exact version must match the pinned dependency/lock; the fixture does not install or discover packages. Use a clean environment without proxy/preload, `NODE_PATH`, `PG*` or alternate PG-module variables.

```sh
node --test --test-concurrency=1 scripts/supabase/current-archive/root-curated.fixture.mjs
```

The fixture creates one new unique `collect_archive_source_<UUID>_test` from template0 and never resets, drops, cleans or reuses a database. It invokes the maintained reviewed local platform helper with the immutable Auth fixture and exact ten migrations. Hosted SQL10 must genuinely refuse the local managed Auth/Realtime doubles; only the independently reviewed variant changing two metadata literals is then applied. Original hosted SQL10 SHA is separate provenance. Synthetic local migration history stores the exact actually applied SQL body for each migration, so the tenth archived source SHA refers explicitly to the local synthetic SQL, not the different hosted bytes. No production migration-history write or hosted source alias is authorized.

It checks the frozen exact 115 identities (97 `app`, 18 `private`) and all 1,090 column names/order, the inactive SQL10 control and 111 ALWAYS guards, initializes the genuine synthetic fence once, proves the local owner path, and seeds only one synthetic user plus one unknown-state text-JSON receipt. It preserves technical history and confirms no ledger/payment/send queue rows. It exercises the existing production planning/capture compiler on actual native queries, observes native trailing ROLLBACK tags, compares all table columns and native text cells independently, authenticates encrypted readback with a separate private key, and invokes the actual new inert restore. Count-eight/nine requests against ten records and same-version/name tenth-statement tampering must refuse. Ordinary offline tests retain their earlier plan/result/receipt tamper boundaries and add exact-ten missing/extra/duplicate/reordered/mis-mapped identity checks.

Every success or failure artifact and both new databases remain for Root review. Only the Management HTTP201 response envelope/status is simulated. A future hosted capture needs its own current metadata, observed-record hashes, exact physical one-to-one source aliases and independent plan review after actual API migration-history timestamps exist. This fixture establishes no hosted capture, operational managed restore, provider/device behavior, RPO/RTO, SB29 or cutover acceptance. The author has not executed either native fixture or any tests.

## Contract references

[Supabase Management query API](https://supabase.com/docs/reference/api/v1-run-a-query), [Supabase read-only query API](https://supabase.com/docs/reference/api/v1-read-only-query), [PostgreSQL 17 transaction isolation](https://www.postgresql.org/docs/17/transaction-iso.html), [PostgreSQL protocol transaction responses](https://www.postgresql.org/docs/17/protocol-flow.html). These are inherited primary-source references from the qualified v3 compiler; the retained provenance records the exact prior observations and their limits.
