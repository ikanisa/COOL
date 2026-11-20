# Managed nonce PostgreSQL qualification

`qualify.mjs` runs the nonce-ledger, fixture-lifecycle and interrupted-diagnostics cases against fresh,
owned PostgreSQL 17 fixtures. It requires every exact named TAP case to pass,
with zero skips, failures, cancellations or todos. It starts each Node test
file directly and forwards TERM/INT to the active test process, waiting for
that process to finish its own cleanup. A hard kill, lost host or unconfirmed
PostgreSQL start/stop can leave an owned directory for investigation; it is
never treated as confirmed cleanup.

```sh
node --test scripts/supabase/testing/managed-nonce-pg/report.test.mjs
COLLECT_INGRESS_TEST_PG_BIN_DIR=/absolute/physical/postgresql-17/bin \
  node scripts/supabase/testing/managed-nonce-pg/qualify.mjs
```

The fixture uses synthetic data and its own local cluster. It does not install
the candidate ledger in Supabase or establish managed roles, TLS, Edge routing
or production readiness. Hosted CI behavior remains unverified until it runs.
