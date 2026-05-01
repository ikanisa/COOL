# Admin App

React/Vite admin panel for operational workflows, audits, approvals, health,
users, members, groups, loans, transactions, BioPay, and reconciliation.

## Commands

- `npm --prefix apps/admin run dev`
- `npm --prefix apps/admin run lint`
- `npm --prefix apps/admin run build`
- `npm --prefix apps/admin run build:ci`

## Boundaries

- Browser checks are UX guardrails only. Supabase RLS, RPCs, and Edge Function
  authorization remain the source of truth for sensitive actions.
- Shared frontend utilities belong in `packages/*` once used by more than one
  surface or once they encode a cross-surface contract.
- Admin-only components, routes, and layout state stay in `apps/admin/src`.

## Shared Dependencies

- `@cool/shared-utils/admin-search` provides safe PostgREST search filter
  helpers used by admin data clients.
