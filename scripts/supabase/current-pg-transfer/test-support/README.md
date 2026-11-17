# Owned PostgreSQL 17 test fixtures

The two transfer suites use `owned-pg17.mjs` to initialize a new private,
synthetic PostgreSQL cluster and start its `postgres` process as an owned
child. It opens only a private Unix socket, disables TCP listening and checks
the PG17 readiness response and postmaster PID file before declaring startup.
It does not connect to an existing database or use an existing PGDATA.

The helper targets Linux and macOS, requires a non-root user and four PG17
binaries (`initdb`, `postgres`, `pg_ctl`, `pg_isready`). It uses
`COLLECT_SYNTHETIC_PG_BIN` when supplied, then the local installed toolchain,
`pg_config --bindir` or PATH. It requires the physical `/tmp` on Linux or
`/private/tmp` on macOS to keep Unix-socket paths short and to match the
synthetic endpoint guards. A different or symlinked physical root is refused.
Windows, root-runner containers and environments without these binaries need
their own fixture setup. The Linux branches have path tests but were not run
on a Linux host as part of this change.

On TERM/INT the helper forwards cancellation to a running `initdb` process
group and tracked subprocesses, stops the owned server, and waits. It removes a
fixture only after successful initialization and startup, confirmed server
exit, absence of the PID file, and `pg_ctl status` confirming no server. An
interrupted or unconfirmed initialization, startup, auxiliary process, or
shutdown retains the private directory and prints its location. Do not remove
it until the process and any descendants have independently been shown stopped.
SIGKILL, a crashed host or detached/hostile descendants cannot be guaranteed
cleanup; retained directories may require manual investigation.

The test-only socket-name checks in the libraries and operator are accidental-
use guards, not attestation that a host or database is trustworthy. They do not
change the managed endpoint checks.

From the repository root, run the focused suites with:

```sh
node --test --test-concurrency=1 scripts/supabase/current-pg-transfer/reconcile.test.mjs scripts/supabase/current-pg-transfer/batch-transfer/quarantine.test.mjs scripts/supabase/current-pg-transfer/test-support/lifecycle.test.mjs
```

The lifecycle tests use actual disposable PG17 processes, including signals to
the `node --test` runner and controlled failed/unconfirmed startup and stop.
They never simulate a production cutover or access managed Supabase.
