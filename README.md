# Collect

Collect is a Flutter app for Rwanda community collections. It keeps the public
member app and the platform admin surface separate.

## Current App Surface

- Flutter app entrypoint: `lib/main.dart`
- Admin entrypoint: `lib/main_admin.dart`
- Main app router: `lib/app/router.dart`
- Admin router: `lib/admin/admin_router.dart`
- Shared Collect models and repository: `lib/shared/`
- Supabase migrations and Edge Functions: `supabase/`

The main app does not register `/admin`. Admin work starts from the isolated
admin entrypoint and uses Supabase-authenticated, server-authorized RPCs for
overview metrics, queues, detail pages, moderation, public-request review,
manual allocation, feature flags, settings, and audited raw-SMS reveal.

## Admin Boundary

Client-side admin guards are convenience only. Real authorization remains in
Supabase RLS, security-definer RPCs, role/permission tables, and audit logs.
Flutter never ships service-role, OpenAI, WhatsApp, or SMS hook secrets.

Admin routes:

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

Admin architecture, security, and cleanup notes live in `docs/admin/`.

## Environment

Copy `.env.example` for local reference. Flutter-visible configuration is
client-safe only. Server-side secrets belong in Supabase or CI secret stores,
not in Flutter env files.

Admin flags:

- `ADMIN_APP_URL=`
- `ENABLE_ADMIN_PANEL=false`
- `ENABLE_ADMIN_DEV_TOOLS=false`

## Commands

The repo is pinned for the local Flutter 3.44 toolchain.

```sh
make flutter-clean
make flutter-pub-get
make format
make analyze
make test
```

Equivalent direct validation:

```sh
/Volumes/PRO-G40/flutter_3_44/bin/flutter clean
/Volumes/PRO-G40/flutter_3_44/bin/flutter pub get
/Volumes/PRO-G40/flutter_3_44/bin/dart format .
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze
/Volumes/PRO-G40/flutter_3_44/bin/flutter test
```

## Supabase

The retained backend surface supports Collect collection membership, public
request submission/review, receiver SMS ingestion/parsing, allocation, manual
allocation, ledger protections, and audit logging. Applied database cleanup is
forward-only unless the linked project is explicitly reset.
