# Synthetic Cloud binder qualification

`cloud-binder-fixture.test.mjs` runs PostgreSQL 17.5 in process using the pinned
PGlite package. It opens no network listener and accepts no database connection
or production credentials. From digest-pinned historical SQL it installs the
predecessor identity migration and actual fence initialization, quiesce and
drain functions. It keeps the deployment identity table empty, then installs
the unchanged managed-executor retirement and Cloud-binding migrations and
exercises the actual managed binding against a synthetic project fixture.

The scheduler status and the minimum required predecessor table shapes are
controlled test doubles. Retirement evidence and provider settlement are not
asserted. This check does not replace real PostgreSQL migration-chain testing,
Supabase-hosted qualification, device testing or release approval. In
particular, the older historical SQL harness still requires a separate Cloud
migration before it can qualify the complete current migration chain.

Run from the repository root after installing the exact locked tooling in
`scripts/supabase`:

```sh
node --test --test-concurrency=1 scripts/supabase/testing/cloud-binder-fixture.test.mjs
```

For a separately installed copy of the exact pinned PGlite module, set
`COLLECT_CLOUD_TEST_PGLITE_MODULE` to its absolute local `dist/index.js` path.
All source migration digests are checked before fixture creation. No applied
migration file is rewritten.
