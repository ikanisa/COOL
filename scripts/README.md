# Scripts

Operational scripts are grouped by intent. The repository root of `scripts/`
keeps compatibility wrappers for existing CI, release docs, and operator muscle
memory.

## Target folders

- `dev/` — local setup and development helpers.
- `qa/` — verification, device tests, smoke tests, and release-candidate gates.
- `deploy/` — hosted deployment and secret-sync entrypoints.
- `migrations/` — database migration validation and application helpers.

## Compatibility

Root-level compatibility wrappers remain around the grouped implementations.
New automation should prefer the grouped paths.

Scripts that consume secrets must prefer environment variables or ignored env
files over positional CLI arguments.

Migration application must use `scripts/migrations/apply_supabase_migrations.sh`
with an explicit `DATABASE_URL` or `SUPABASE_DB_URL`; do not rely on the
currently linked Supabase project for production pushes.
