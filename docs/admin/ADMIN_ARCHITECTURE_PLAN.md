# Collect Admin Architecture

Date: 2026-05-23

## Runtime

- Entrypoint: `lib/main_admin.dart`
- App: `lib/admin/admin_app.dart`
- Router: `lib/admin/admin_router.dart`
- Shell: `lib/admin/admin_shell.dart`
- Runtime repository/pages: `lib/admin/core/admin_runtime.dart`
- Models: `lib/admin/core/admin_models.dart`
- Shared components: `lib/admin/shared/components/`

The main Collect app does not register `/admin`. The admin surface is a
separate Flutter web entrypoint that authenticates with Supabase Auth and reads
or mutates admin data only through server-authorized RPCs.

## Capabilities

- WhatsApp OTP admin login.
- Admin identity and permission loading.
- Overview metrics from `admin_overview`.
- Collection, user, payment, payment-event, receiver, SMS, audit-log, settings,
  feature-flag, and admin-user list/detail pages.
- Public collection request review.
- Collection moderation actions.
- Payment-event reparse and manual allocation flows.
- Audited raw-SMS reveal through a sensitive-data gate.

## Route Map

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

## Security Rules

- Client guards are not authoritative.
- Admin data access must stay behind RLS, security-definer RPCs, and
  role/permission checks.
- Flutter must never ship service-role, OpenAI, WhatsApp, or SMS hook secrets.
- Raw SMS reveal requires permission, reason, and audit.
- Payment allocation and ledger-affecting actions must be deterministic,
  idempotent, and audited server-side.

## Remaining Work

- Live role-by-role UAT against the linked project.
- Operational runbooks for admin escalation, SMS support, and payment review.
- Optional cleanup of disconnected legacy admin feature-folder files after route
  coverage is verified.
