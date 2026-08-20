# Collect bank-transfer QA report

Date: 20 August 2026

## Scope

The review covers the Flutter member/public/Admin clients, Supabase schema and
RPCs, the six Edge Functions, Android permission boundaries, deterministic bank
evidence parsing, daily reconciliation, maker-checker and balanced ledger.

## Local result

- Flutter static analysis: pass.
- Focused bank/admin/member/privacy/release contract suite: pass.
- Edge Function type checks and unit tests: pass.
- Local Supabase reset, lint and rollback UAT: pass.
- Updated member/public/Admin goldens: visually reviewed; manifest refreshed.

## Open production evidence

- Complete Google authentication for the existing May2026 project.
- Install the generated Firebase Android configuration.
- Create a least-privilege FCM sender identity only after action-time approval,
  store it directly as a Supabase secret and validate delivery.
- Deploy and verify the migration/functions/web in production.
- Run a real bank receipt through evidence, statement, reconciliation, journal
  and notification delivery.

No provider, bank, real-device or store success is inferred from local QA.
