# Collect Admin Architecture

Date: 2026-08-15

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
- Group, member, payment-intent, posted-transaction, SMS parsing, allocation,
  exception, receiver, SMS, notification, audit-log, settings, feature-flag,
  system-health, and admin-user list/detail pages.
- Payment-event reparse and exception investigation flows.
- Audited raw-SMS reveal through a sensitive-data gate.
- Reason-gated notification retry and admin-role grant/revoke workflows.
- Database-backed navigation/queue metadata and realtime invalidation for every
  operational domain, including notification events and deliveries.

## Route Map

- `/admin/login`
- `/admin/denied`
- `/admin`
- `/admin/groups`
- `/admin/groups/:id`
- `/admin/members`
- `/admin/members/:id`
- `/admin/payment-intents`
- `/admin/payment-intents/:id`
- `/admin/transactions`
- `/admin/transactions/:id`
- `/admin/payment-events`
- `/admin/payment-events/:id`
- `/admin/allocations`
- `/admin/exceptions`
- `/admin/ledger`
- `/admin/receivers`
- `/admin/receivers/:id`
- `/admin/sms`
- `/admin/sms/:id`
- `/admin/notifications`
- `/admin/notifications/:id`
- `/admin/audit-logs`
- `/admin/settings`
- `/admin/feature-flags`
- `/admin/system-health`
- `/admin/admin-users`
- `/admin/admin-users/:id`

## Security Rules

- Client guards are not authoritative.
- Admin data access must stay behind RLS, security-definer RPCs, and
  role/permission checks.
- Flutter must never ship service-role, OpenAI, WhatsApp, or SMS hook secrets.
- Raw SMS reveal requires permission, reason, and audit.
- Admin role mutation and notification retry require explicit permissions,
  reasons, audit records, and server-side state validation.
- The final effective platform owner cannot be revoked; self-revocation of the
  platform-owner role is also blocked.
- Public collection helper functions fail closed when a browser caller supplies
  another user's UUID.
- Payment allocation and ledger-affecting actions must be deterministic,
  idempotent, automated from MoMo SMS/payment intents, and audited
  server-side.

## Remaining Work

- Apply the pending migrations through an approved production change, then run
  live role-by-role UAT against the linked project.
- Operational runbooks for admin escalation, SMS support, and payment review.
- Optional cleanup of disconnected legacy admin feature-folder files after route
  coverage is verified.
