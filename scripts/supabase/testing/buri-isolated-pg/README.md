# Isolated BuriMunsi PostgreSQL checks

The normal shared Edge suite discovers six tests that require explicit
PostgreSQL fixtures and skips them without those fixtures. `qualify.mjs` runs
those tests in three fresh PostgreSQL 17 clusters using synthetic records. A
private executable translates only the tests' fixed Docker-shaped commands to
the owned Unix socket; it does not connect to Docker or an existing database.
Every cluster is stopped and its stop is checked before its temporary directory
is removed. An unconfirmed stop preserves the directory for investigation.
TERM and INT cancel the owned test process group and trigger that cleanup;
`interrupt.test.mjs` verifies termination during the active history suite. Run it
directly with `node --test-reporter=tap interrupt.test.mjs`, with the same
environment, so that the process receiving TERM or INT forwards it to the
qualifier and waits for cleanup. A hard kill can still interrupt cleanup.
Startup and stop commands are synchronous with bounded timeouts, so their
signal handling can be delayed until the command returns. The declared CI step
allows a 120-second termination grace; an immediate SIGKILL or host failure can
still leave an owned temporary cluster requiring operator cleanup.

```sh
COLLECT_BURI_TEST_PG_QUALIFY=true \
COLLECT_BURI_TEST_PG_BIN_DIR=/absolute/physical/postgresql-17/bin \
COLLECT_BURI_TEST_TMP_ROOT=/physical/writable/temp/root \
node scripts/supabase/testing/buri-isolated-pg/qualify.mjs
```

The binary directory and temporary root must be physical paths; the temporary
root must be separate from the checkout. Run as a non-root OS user. This checks
the current source queries and migration snippets under a synthetic C-locale
database; it does not test real accounts, a managed Supabase project, provider
connections or the full migration chain. The isolated bootstrap superuser is
not evidence of privileges on the hosted `postgres` role.
