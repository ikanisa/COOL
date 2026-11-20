# HTTP admission: explicit native PostgreSQL qualification

The normal Edge Node source suite runs
`supabase/functions/_shared/tests/http-admission-postgres.test.mjs`. That test
checks the qualification contract and prints that **native PostgreSQL was not
run**. It neither starts a database nor silently skips a native test.

The six cancellation, late/lost registration acknowledgement, lost close
acknowledgement, duplicate registration and bounded-cleanup cases live in
`native.test.mjs`. They require an explicit synthetic opt-in and an absolute,
physical PostgreSQL 17 binary directory. Missing prerequisites make that test
fail; it cannot select an existing database, URL, Docker socket or receipt.

```sh
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  COLLECT_HTTP_ADMISSION_PG_QUALIFY=true \
  COLLECT_HTTP_ADMISSION_PG_BIN_DIR='/absolute/physical/postgresql-17/bin' \
  COLLECT_HTTP_ADMISSION_PG_TMP_ROOT='/physical/writable/temp/root' \
  node scripts/supabase/testing/http-admission-pg/qualify.mjs
```

The optional temp-root setting may be omitted if the physical OS temporary
directory has a short Unix-socket path. The executing OS user must be non-root;
the temporary parent must be writable and outside both checkout roots and their
ancestors. The fixture creates a fresh 0700 owned directory and a private Unix
socket, disables TCP listening, ignores inherited PostgreSQL connection
variables, and confirms the server's data directory, socket, role and PG17
identity before loading SQL. It executes the exact SHA-256-pinned repository
fence migration with 110 empty synthetic predecessor tables and no provider
calls. Those tables model only the migration's scope prerequisite, not the full
application schema. PostgreSQL commits and row readback are real; delayed and
lost acknowledgements are simulated in the client adapter. The fixture stops
its own server and confirms it is stopped before deleting only its own directory.
On unconfirmed stop or cleanup it preserves the directory and reports its path.

## CI wiring

The source-suite pass is not evidence of the native qualification. The current
Supabase native CI job now declares a separate required PG17 step, with Node and
the checked-out sources readable by a non-root user. Its container command is
equivalent to the following; the workflow has not been run remotely by this
local change:

```sh
set -eu
pg_bin_dir="$(dirname "$(realpath "$(command -v postgres)")")"
node_bin="$(command -v node)"
gosu postgres env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  COLLECT_HTTP_ADMISSION_PG_QUALIFY=true \
  COLLECT_HTTP_ADMISSION_PG_BIN_DIR="$pg_bin_dir" \
  COLLECT_HTTP_ADMISSION_PG_TMP_ROOT=/tmp \
  "$node_bin" scripts/supabase/testing/http-admission-pg/qualify.mjs
```

The CI job uses `qualify.mjs` to run the six admission and nine lifecycle cases directly, requiring each exact named TAP case to pass with no skips. It forwards TERM/INT to the active fixture and waits for its cleanup; a hard kill or host failure can still leave retained evidence. The CI job fails if the step fails or its prerequisites are unavailable;
it has no skipped-test fallback. A passing local fixture does
not establish managed deployment, real network acknowledgement loss, or the
full application migration chain.
