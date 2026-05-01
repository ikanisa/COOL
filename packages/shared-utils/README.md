# Shared Utils

Runtime-agnostic helpers that are shared by more than one production surface or
verification script.

Current exports:

- `src/admin-search.ts` — safe PostgREST admin search normalization and `or`
  filter construction.

Import path:

- `@cool/shared-utils/admin-search`

Utilities in this package must not import app UI, browser globals, Supabase
clients, secrets, or runtime-specific dependencies.
