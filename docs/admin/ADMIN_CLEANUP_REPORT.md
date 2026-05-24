# Collect Admin Runtime Report

Date: 2026-05-23

## Scope

The admin surface is now a separate Flutter web runtime backed by Supabase Auth,
RLS, and security-definer admin RPCs. It is no longer a title-only placeholder
shell.

## Kept

- Main Collect customer app remains separate and does not register `/admin`.
- Receiver SMS ingestion, parser Edge Functions, deterministic allocation,
  manual allocation, immutable ledger protections, and audit logs remain the
  backend authority.
- Applied Collect baseline migrations are treated as forward-only linked-project
  history.

## Replaced

- `lib/main_admin.dart` starts the isolated admin Flutter app.
- `lib/admin/admin_router.dart` maps authenticated admin routes and detail
  routes.
- `lib/admin/admin_shell.dart` loads admin identity, shows permission-aware
  navigation, and gates denied users.
- `lib/admin/core/admin_runtime.dart` provides Supabase-backed repositories,
  list pages, detail pages, overview metrics, login, denial handling, actions,
  and raw-SMS reveal through an audited sensitive-data gate.
- `lib/admin/shared/components/` contains real metric, table, and sensitive-data
  components used by the runtime.

## Routes

- `/admin/login`
- `/admin/denied`
- `/admin`
- `/admin/collections`
- `/admin/collections/:id`
- `/admin/public-requests`
- `/admin/users`
- `/admin/users/:id`
- `/admin/payments`
- `/admin/payments/:id`
- `/admin/payment-events`
- `/admin/payment-events/:id`
- `/admin/unallocated`
- `/admin/ledger`
- `/admin/receivers`
- `/admin/receivers/:id`
- `/admin/sms`
- `/admin/sms/:id`
- `/admin/audit-logs`
- `/admin/settings`
- `/admin/feature-flags`
- `/admin/system-health`
- `/admin/admin-users`

## Remaining Work

- Live platform-admin, reviewer, and non-admin UAT against the linked Supabase
  project.
- Production admin operational runbook and evidence capture.
- Follow-up cleanup of unused old admin feature-folder files if they remain
  disconnected from the active router.

## Validation

- `flutter analyze --no-pub`
- `flutter test --no-pub --concurrency=1`
- `scripts/migrations/validate_supabase_migrations.sh`
- `supabase db push --linked --dry-run`

## Supabase

Admin behavior is implemented through forward migrations and RPC contracts.
Raw SMS remains protected; reveal requires server permission checks and an audit
reason. No migration should be rewritten after it has been applied to the linked
project.
