# Managed migration source history

`source-migrations.lock.json` is a byte-for-byte preservation of the source
migration lock used to qualify the managed Supabase Cloud transition. Its
historical format identifier is retained as provenance; it does not authorize
or configure a local production deployment. The migration SQL, the recorded
Cloud migration history, and the separate managed convergence candidates must
still be compared by the release tooling.

The earlier deployment location remains temporarily available to historical
synthetic fixture consumers until those consumers are migrated without changing
their recorded evidence or dropping coverage.

The retained lock, original lifecycle migration and its deployed managed
variant are exact qualification inputs. Both lifecycle bodies live under
`retained/`. The managed variant binds the fence and catalog observed when
the release ran.

The [20 November managed history at epoch 44](cloud-history-20261120-epoch44.json)
records all 89 migration bodies through `20261120104500`. A separate database
connection verified the seven new migrations, their catalog and grant checks,
and the payment and ledger totals recorded before the release. The receipt
includes the observed scheduler and Edge deployment identities.

The [earlier 82-migration readback](cloud-history-20261120.json) ends at
`20261118090305`. Run
`node --test scripts/supabase/cloud-release/recorded-history.test.mjs` to
compare both readbacks with their SQL sources and check that the first 82
entries are identical.

`fixtures/` contains only the schema and provider migration-history shapes
used by the synthetic chain test. Release tooling checks the retained lock,
individual migration bytes and fixture hashes before use.

The nonsecret managed lifecycle candidate generator is in
`scripts/supabase/cloud-release/managed-lifecycle-candidate.mjs`; its input
and generated SQL remain subject to the original preimage checks. These files
are migration evidence and test inputs, not a production service launcher.
