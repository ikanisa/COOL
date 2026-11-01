# History receipt profiles and maintained test commands

`make test` runs Flutter unit and widget tests with `--exclude-tags=integration`,
matching the maintained unit CI job. It exercises synthetic transport fixtures
and decoders. It does not claim a native database, GoTrue, device, provider or
production qualification.

SQL receipt consumers require the explicit, reviewed define file produced by
their matching native runner. A missing define, wrong format, changed packet or
changed source fails the integration test. There is no automatic skip, generated
replacement fixture or equivalence between historical and current profiles.

| Profile | Producer | Consumer | Evidence scope |
| --- | --- | --- | --- |
| Historical current14 | `current14-member-history.mjs`, orchestrated by `qualify-stopped-admission-native.mjs` | `test/current14_member_history_sql_receipts_test.dart`, `CURRENT14_HISTORY_*` defines | The explicitly named historical schema and its reviewed source. Existing packet format and source remain unchanged. |
| Historical current16 | `current16-integration.mjs` and `current16-runtime.ts` | The native current16 result validator | The original sixteen migrations and its explicitly enumerated runtime, retention and delivery cases. This is not the newer history migration. |
| Retained 2026-11-01 additive history evidence | The earlier `self-hosted-backend-runtime.ts` capture retained under `docs/implementation/self-hosted-20261101/history/` | Its recorded six-test Flutter result | Original sixteen migrations plus the named admission archive and history pagination migrations. Its v1 packet and source hashes are preserved; it is not a complete-current-chain result. |
| Current self-hosted history | `self-hosted-backend-runtime.ts` with `self-hosted-member-history.mjs`, invoked by `current-self-hosted-native.mjs` | `test/self_hosted_member_history_sql_receipts_test.dart`, `SELFHOST_HISTORY_*` defines | The complete, independently reviewed migration inventory in the deployment lock and additive manifest, real local PostgreSQL 17, and actual shipping v2 history SQL/domain results. |

## Unit and historical commands

```sh
make test FLUTTER=/absolute/path/to/flutter
make test-history-current14 FLUTTER=/absolute/path/to/flutter DEFINES=/absolute/path/to/reviewed-current14-defines.json
make supabase-current16-integration-native
```

Historical native fixture requirements, exact dependency pins and private
loopback invocation contracts remain in `current16-integration.md` and their
existing producers. A downloaded historical packet needs its three path define
values rebased to the downloaded physical files, while retaining their original
digests. Running it against newer changed source is not evidence that its old
database profile qualifies the new source.

Automatic pull-request CI runs `current-source-contracts`,
`current-self-hosted-native`, and `current-self-hosted-history-dart`. Historical
CI requires an explicit `workflow_dispatch` profile and a reviewed forty-digit
commit SHA. Historical jobs check out that SHA before running their original
producers and consumers. A historical selection is never counted as current
qualification.

`make supabase-source-test` runs the maintained source/configuration contracts.
`make supabase-test` additionally requires the current native fixture invocation;
absent fixture inputs fail. Source-only tests do not replace native database
checks. `make supabase-historical-schema-test` is the separately named legacy
schema entrypoint for an explicitly reviewed historical checkout.

## Current additive capture

The preferred command runs the whole current native harness on an explicitly
owned fresh PostgreSQL 17 cluster, retaining installation, control concurrency,
runtime, Auth, retention, notifications, gateway and scheduler results alongside
the history packet. The CI cluster is the pinned, isolated loopback
`127.0.0.1:55439` fixture with the reviewed 60/3/0 connection limits. The local
adapter accepts only its dedicated private loopback descriptor on port 55446.
It refuses an already initialized or reused cluster, allocates a distinct
database for each harness, and never resets a database. Output is exclusive and
private fixture descriptors are not uploaded as evidence.

```sh
export COLLECT_CI_SYNTHETIC=true
export COLLECT_DENO=/absolute/path/to/deno
export COLLECT_SELFHOST_LOCAL_CLUSTER_DESCRIPTOR=/absolute/path/to/collect-current-native-pg.private.json
export COLLECT_SELFHOST_OUTPUT_DIR=/absolute/path/to/new-current-native-result
make supabase-current-native

node scripts/supabase/testing/admit-self-hosted-history.mjs \
  "$COLLECT_SELFHOST_OUTPUT_DIR/history" /absolute/path/to/new-history-defines.json
make test-history-selfhost FLUTTER=/absolute/path/to/flutter \
  DEFINES=/absolute/path/to/new-history-defines.json
```

For a separately scoped history-only capture, provision a fresh disposable
original16 OPEN fixture with the maintained
`prepareSelfHostedFixture` helper and `purpose: 'backend'`. The helper never
resets an existing database. Retain its private descriptor outside deliverable
artifacts. The runtime accepts only an explicitly synthetic local PostgreSQL
17 fixture with the normal non-superuser owner. It creates synthetic financial
facts with the real schema triggers enabled, installs every reviewed current
addition, and blocks all outbound fetches. That capture cannot stand in for the
other native harnesses.

Run the pinned Deno executable with the frozen repository lock and allow only
the fixture's actual loopback port. The output directory must not exist and its
parent must be a physical directory. For a fixture on port 55445:

```sh
export COLLECT_CI_SYNTHETIC=true
export COLLECT_SELFHOST_BACKEND_FIXTURE_DESCRIPTOR=/absolute/path/to/backend-fixture.private.json
export COLLECT_SELFHOST_HISTORY_OUTPUT_DIR=/absolute/path/to/new-history-receipt

/absolute/path/to/deno run --frozen --config=supabase/functions/deno.json \
  --lock=supabase/functions/deno.lock --allow-env --allow-read \
  --allow-write="$COLLECT_SELFHOST_HISTORY_OUTPUT_DIR" --allow-net=127.0.0.1:55445 \
  scripts/supabase/testing/self-hosted-backend-runtime.ts

node scripts/supabase/testing/admit-self-hosted-history.mjs \
  "$COLLECT_SELFHOST_HISTORY_OUTPUT_DIR" /absolute/path/to/new-history-defines.json
make test-history-selfhost FLUTTER=/absolute/path/to/flutter \
  DEFINES=/absolute/path/to/new-history-defines.json
```

The runner produces `INPUTS.json`, `ACTUAL-HISTORY-PACKET.json`,
`ACTUAL-SQL-STATEMENTS.json`, `DEFINES.json`, and `RESULT.json`. The packet format
is `collect.selfhost.actual-member-history-sql.v3`; its profile is
`reviewed_current_chain_member_history_v3`. The source hash binds the
exact shipping JS, applied SQL files, native producer, frozen dependency inputs
and financial Dart decoder/consumer files. The current migration count and
every migration name/hash are verified against both the deployment lock and the
independent reviewed additive manifest. The original16 controller source
hash is recorded separately and is not presented as the current release hash.
Every successful page is associated with its original request and captured
actual SQL result. The capture refuses a source change during execution.

The packet's `DEFINES.json` contains only three relative artifact filenames and
their original hashes. The admission command verifies all five physical files,
the complete source inventory and exact receipt format, then writes a new
exclusive define file with those three paths rebased. It does not rewrite any
packet, statement, source hash or result. A missing file, wrong version,
unreviewed migration or changed source fails admission. The retained v1
evidence is not silently upgraded to v3.

The Dart consumer verifies source and packet hashes, all four sort continuations
over more than 10,000 rows, exact aggregates, a complete half-open date range,
empty/foreign scopes, privacy fields, invalid-range refusals, stale cursors and
revoked-session denial. Statements contain only disposable synthetic data;
there are no tokens or database credentials in these artifacts. This capture
does not test managed GoTrue sign-in, financial posting, provider settlement,
hosted service behavior or production acceptance. Its history fixture does not
claim deployment-identity acceptance; that is tested separately by the native
installer/runtime harness. It is not a current14 or current16 historical result.

Contract guard checks, which do not access PostgreSQL, run with:

```sh
node --test scripts/supabase/testing/self-hosted-member-history.test.mjs
node --test scripts/supabase/testing/current-self-hosted-native.test.mjs
```
