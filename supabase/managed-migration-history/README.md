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

The retained lock and the single original lifecycle migration are exact
qualification inputs. The lifecycle file lives under `retained/`, outside the
active migration directory, so it cannot become a duplicate migration.
`fixtures/` contains only the schema and provider migration-history shapes
used by the synthetic chain test. Release tooling checks the retained lock,
individual migration bytes and fixture hashes before use.

The nonsecret managed lifecycle candidate generator is in
`scripts/supabase/cloud-release/managed-lifecycle-candidate.mjs`; its input
and generated SQL remain subject to the original preimage checks. These files
are migration evidence and test inputs, not a production service launcher.
