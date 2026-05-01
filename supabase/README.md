# Supabase

Supabase owns database schema, RLS, policies, Edge Functions, backend tests, and
local project configuration.

## Current layout

- `migrations/` — ordered SQL migrations plus `migration_manifest.yaml`.
- `functions/` — Deno Edge Functions and shared helpers in `_shared`.
- `config.toml` — local Supabase project configuration.
- `seed/cool_status.sql` — local seed data for Cool status/config.

## Target additions

- `policies/` — policy documentation or generated policy inventories, not a
  replacement for migrations.
- `seed/` — seed files split by environment and intent.
- `tests/` — database/RLS tests that cannot live next to Edge Function code.
- `docs/` — backend-specific runbooks and schema notes.

Every client-exposed table must have least-privilege RLS. Every sensitive RPC
or Edge Function must authenticate, authorize, validate input, and audit safely.
