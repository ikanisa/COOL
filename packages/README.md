# Packages

This folder is reserved for reusable code that is genuinely shared across
multiple production surfaces.

## Target packages

- `design-system/` — cross-surface tokens and components once Flutter and web
  token contracts are extracted from their current app-local implementations.
- `shared-types/` — generated or hand-maintained API/domain contracts shared by
  Flutter, admin web, Edge Functions, and tests.
- `shared-utils/` — small runtime-agnostic helpers with no app dependencies.
- `domain/` — business rules that are not UI, persistence, or transport code.
- `api-clients/` — typed API wrappers around Supabase RPCs, Edge Functions, and
  future service endpoints.
- `auth/` — shared auth/session/role model helpers.
- `payments/` — shared payment state, MoMo/USSD route, ledger, and allocation
  contracts.
- `agent-ui/` — reusable UI for future agent consoles.
- `analytics/` — event taxonomy, client helpers, and reporting contracts.

## Current source of truth

- Shared PostgREST/admin search utilities: `shared-utils/src/admin-search.ts`.
- Flutter shared UI/tokens: `lib/core/theme` and `lib/shared/widgets`.
- Flutter domain/config models: `lib/core/models`, `lib/core/config`, and
  feature `models/` directories.
- Admin web API types and clients: `apps/admin/src/lib/api`.
- Edge Function shared helpers: `supabase/functions/_shared`.

Do not create runtime packages here until at least two surfaces consume the
code and the dependency direction is clear.
