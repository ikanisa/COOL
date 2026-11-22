#!/bin/sh
# Run the real Edge handler suites against two independently owned local fixtures.
set -eu

if [ "${COLLECT_CI_SYNTHETIC:-}" != true ]; then
  echo 'Set COLLECT_CI_SYNTHETIC=true for the disposable PostgreSQL handler suites.' >&2
  exit 2
fi
: "${COLLECT_TEST_DATABASE_URL:?Supply the owned Collect Edge fixture database.}"
: "${COLLECT_ADMIN_HISTORY_TEST_DATABASE_URL:?Supply the owned Admin history fixture database.}"

deno="${COLLECT_DENO:-deno}"
repo=$(CDPATH='' cd -- "$(dirname "$0")/../../.." && pwd -P)
cd "$repo"
output=$(mktemp "${TMPDIR:-/tmp}/collect-pg-handlers.XXXXXXXX")
trap 'rm -f -- "$output"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

status=0
"$deno" test --frozen --config=supabase/functions/deno.json --lock=supabase/functions/deno.lock \
  --allow-env --allow-net=127.0.0.1 --allow-read=. --reporter=tap \
  supabase/functions/_shared/tests/postgres.integration.test.ts \
  supabase/functions/_shared/tests/admin_history.integration.test.ts > "$output" 2>&1 || status=$?
cat "$output"
test "$status" -eq 0 || exit "$status"

if grep -q '# SKIP' "$output"; then
  echo 'The PostgreSQL handler suites require both fixtures and cannot skip a case.' >&2
  exit 1
fi
grep -Eq '^ok [0-9]+ - actual Edge handlers on PostgreSQL:' "$output"
grep -Eq '^ok [0-9]+ - Admin request history: both authenticated GET aliases during an exclusive financial transaction$' "$output"
grep -Eq '^ok [0-9]+ - Admin history on local PostgreSQL: own receipts, committed lost reply and current authority fences$' "$output"
