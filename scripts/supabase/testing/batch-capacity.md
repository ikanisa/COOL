# Local adapter contention measurement

`measure-batch-capacity.mjs` measures the repository's actual
`PostgresDatabase.batch` implementation on a new, owned, loopback PostgreSQL 17
database. It keeps the global `pg_advisory_xact_lock(734636924058501)` unchanged.
Its output is a portable JSON observation, with explicit
`hosted_capacity_acceptance: false` and `financial_workflow_acceptance: false`.
There is no production latency or throughput pass threshold.

## What runs

The default workload has three phases with 1, 2 and 4 concurrent workers. Each
worker calls 12 batches: three read-only batches and nine write batches. Every
batch contains two statements against its own pair of synthetic
`app.admin_rate_limits` rows. Row keys are disjoint between workers, so the
workload does not deliberately add a shared row lock on top of the existing
global adapter lock. Both rows start at 1 and must finish at 10 for the default
workload. Each returned read/write pair and all final persisted values are
checked exactly.

The actual application-fence registration, lease, assertion, statement triggers,
runtime role, read-committed transaction, pool reservation, commit and cleanup
paths execute. Each worker has a separate real admission for its phase; it does
not share another worker's serialized work-assertion queue. Admission setup and
initial row seeding are outside measured latency. The default 84 measured batches
are separate from seven setup batches, which are explicitly counted in the
result. A long-lived admission per
worker is a deliberate measurement simplification, not a simulation of the
arrival rate or authorization cost of real HTTP requests.

Latency runs from the call to `batch` through its completion and includes pool,
fence, global-lock, SQL and commit time. It does not isolate lock-wait duration.
The production business pool stays at 4 connections. Output includes sample
counts, min/p50/p95/p99/max, successful batches per second, bounded error codes,
exact planned and observed final rows, runtime versions and source hashes.
Percentiles use nearest rank. Small samples are useful correctness and local
contention observations; their tail percentiles are not a statistically reliable
estimate of production tails.

## Local prerequisites

Use the repository-pinned Deno 2.9.6 and cached `postgres@3.4.7` dependency. The
tool does not install software or fetch packages. Run it with `--cached-only`,
`--frozen` and an exact loopback network grant as shown below. It refuses broad
network permission. The maintained curated fixture loader checks the complete
reviewed migration inventory on disk, then applies exactly the SQL11 fixture
prefix, with its reviewed local realtime interface. Later additive migrations
being admitted on disk do not turn this SQL11 measurement into a qualification
of their feature behavior.

Create a new empty database named exactly `collect_batch_capacity_test`, owned
by `collect_test`, in a disposable local PostgreSQL 17 cluster. The existing
synthetic fixture requires `collect_test` to be the explicitly local superuser
and bypass role and requires the managed `postgres` stand-in to remain
restricted. This tool never creates, drops or resets the database. Do not aim it
at a database with previous measurement history: before setup it refuses user
relations, functions, types, nonstandard schemas/extensions, event triggers,
foreign servers/wrappers and any other connection. Only built-in namespaces,
the empty public schema and the standard plpgsql extension are admitted. This
connection check is an initial observation; it does not exclude later access by
another process or establish exclusive control over the host for the full run.

Example invocation from the repository root. Supply the local fixture URL
through `COLLECT_BATCH_CAPACITY_DATABASE_URL` in the invoking environment. It
must target `127.0.0.1:55441`, role `collect_test`, and database
`collect_batch_capacity_test`, using the operator-supplied password. The
command refuses an unset or empty value:

```sh
COLLECT_CI_SYNTHETIC=true \
COLLECT_BATCH_CAPACITY_DATABASE_URL="${COLLECT_BATCH_CAPACITY_DATABASE_URL:?Set the admitted local test database URL}" \
DENO_DIR=/absolute/path/to/prepared-deno-cache \
/absolute/path/to/deno-2.9.6 run --cached-only --frozen \
  --config supabase/functions/deno.json --lock supabase/functions/deno.lock \
  --allow-env --allow-read="$PWD" --allow-net=127.0.0.1:55441 \
  scripts/supabase/testing/measure-batch-capacity.mjs > batch-capacity.json
```

Optional `--allow-sys=cpus,systemMemoryInfo` adds logical CPU count and physical
memory to the runtime metadata. Without it, those fields are explicitly null
and `host_resources_verified` is false; the measurement still runs with the
same bounded database workload.

The only connection variable is the exact local target above. `localhost`, IPv6,
remote hosts, alternate users/databases, query parameters, URL fragments and
ambient `PG*`/general database credentials are refused. The URL/password never
appears in the JSON or error projection. No command-line arguments or custom
SQL are accepted. Existing source hashes for the actual adapter, application
fence and frozen dependency lock must match. The tool records its own/helper
and migration file identities and rechecks them after setup and measurement;
it cannot silently accept a source change during a run. Updating an adapter pin
requires code review, not a command-line override.

Two optional environment values select bounded workloads:

| Variable | Default | Accepted scope |
| --- | --- | --- |
| `COLLECT_BATCH_CAPACITY_CONCURRENCY` | `1,2,4` | 1–4 strictly increasing unique phases; each value 1–8 |
| `COLLECT_BATCH_CAPACITY_OPERATIONS_PER_WORKER` | `12` | 4–32, divisible by 4 |

Total planned measured batches cannot exceed 384. Setup adds at most 26 batches
(the maximum sum of four distinct worker counts from 1–8), plus bounded fence
registration and finish operations. The workload start budget is 60 seconds
and the entire process is capped at 120 seconds. Actual adapter SQL/reservation
timeouts also remain unchanged. There is no retry of an unknown or failed
batch. Budget exhaustion, source drift, any operation error, final value
mismatch, unsettled admission or unconfirmed cleanup produces `UNCONFIRMED`
and a nonzero exit code. A successful observation is `MEASURED`; that status
means the declared local run completed correctly, not that capacity is adequate
for production.

## Cleanup and evidence

Normal cleanup finishes the exact real admissions and ends only pools created
by this process. It never invokes `pg_terminate_backend`, changes the production
lock, fabricates admission close results or deletes histories. On hard process
timeout, only the process and its sockets stop, and cleanup is marked
unconfirmed. The database and synthetic rows remain available for inspection.
Further runs need a separately prepared fresh instance of the same fixed local
database; erasing an earlier result is an explicit operator action outside this
tool.

Run the network-free refusal/contract tests with:

```sh
node scripts/supabase/testing/batch-capacity.test.mjs
```

This is a single-host synthetic adapter benchmark. It does not exercise real
collections, ledger/receipt correctness, financial contention patterns, payment
or push providers, pooled hosted Postgres, deployed Edge scaling, regional
latency, sustained soak behavior, failover or actual traffic. Production
capacity acceptance still needs an approved workload, traffic mix, targets and
measurements in the intended environment. This implementation supplies a
maintained reproducible local measurement and closes the absence of that tool;
it does not close the hosted-capacity evidence gap.
