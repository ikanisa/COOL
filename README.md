# Collect

Collect is a Flutter and Supabase platform for SMS-first MoMo group contributions.
Members contribute through payment intents created in the app; MoMo SMS
is ingested, parsed with OpenAI, allocated in Supabase, and posted to the ledger.

## Product Surface

- Mobile app entrypoint: `lib/main.dart`
- Admin PWA entrypoint: `lib/main_admin.dart`
- Mobile router: `lib/app/router.dart`
- Admin router: `lib/admin/admin_router.dart`
- Shared models/repository: `lib/shared/`
- Supabase migrations and Edge Functions: `supabase/`

The mobile bottom navigation is `Home`, `Groups`, and `Settings`.

Mobile app routes:

- `/auth`
- `/auth/success`
- `/auth/failure`
- `/onboarding`
- `/onboarding/legal`
- `/home`
- `/offline`
- `/sync`
- `/notifications`
- `/permissions/sms`
- `/permissions/sms-denied`
- `/permissions/device`
- `/permissions/notifications-denied`
- `/permissions/camera-denied`
- `/platform/iphone-create-unavailable`
- `/groups`
- `/groups/join`
- `/groups/scan`
- `/groups/create`
- `/groups/:collectionId`
- `/groups/:collectionId/created`
- `/groups/:collectionId/joined`
- `/groups/:collectionId/members`
- `/groups/:collectionId/owner`
- `/groups/:collectionId/owner/sms-health`
- `/groups/:collectionId/owner/receiver`
- `/groups/:collectionId/manage`
- `/groups/:collectionId/profile`
- `/groups/:collectionId/contribute`
- `/groups/:collectionId/pay/:intentId/handoff`
- `/groups/:collectionId/pay/:intentId/waiting`
- `/groups/:collectionId/pay/:intentId/state/:state`
- `/groups/:collectionId/pay/:intentId`
- `/groups/:collectionId/support/payment/:intentId`
- `/groups/:collectionId/share`
- `/groups/:collectionId/invite`
- `/groups/:collectionId/ledger`
- `/c/:slug`
- `/share/invalid`
- `/share/expired`
- `/share/expired/request`
- `/settings`
- `/settings/profile`
- `/settings/readiness`
- `/settings/account`
- `/settings/account/delete`
- `/settings/privacy`
- `/settings/help`
- `/settings/legal/terms`
- `/settings/legal/privacy`
- `/share/confirmed`

## Core Workflow

1. User signs in with a WhatsApp number and receives a 6-digit Collect ID.
2. User stores a MoMo number in Settings/Profile.
3. Android group creator creates a group with name, optional description, and
   receiver MoMo number synced from profile.
4. iPhone group creation is blocked with `group creation is available only on Android`.
5. Members join from a link or QR code shared through chat apps, SMS, or deep link.
6. Member taps `Contribute`, enters amount, and Supabase creates a pending
   payment intent linked to group, amount, receiver MoMo, user id, and Collect ID.
7. The app opens the MoMo dialer with `tel:` and payment is completed off app.
8. MoMo SMS is uploaded to Supabase, parsed, matched to the pending intent,
   and posted to the immutable ledger.

There is no manual SMS paste, no reported transaction ID field, no anonymity
picker, no public directory flow, and no campaign target/category/cover workflow.

## Admin Boundary

The admin PWA is a separate entrypoint. It monitors groups, members, payment
intents, MoMo SMS rows, parser output, allocation status, ledger entries,
receivers, audit logs, settings, and exceptions. Client-side admin guards are
convenience only; Supabase RLS, security-definer RPCs, role tables, and audit
logs enforce authorization.

Admin routes:

- `/admin/login`
- `/admin/denied`
- `/admin`
- `/admin/groups`
- `/admin/groups/:id`
- `/admin/members`
- `/admin/members/:id`
- `/admin/payment-intents`
- `/admin/payment-intents/:id`
- `/admin/payment-events`
- `/admin/payment-events/:id`
- `/admin/allocations`
- `/admin/exceptions`
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

## Commands

```sh
make flutter-pub-get
make format
make analyze
make test
./scripts/migrations/validate_supabase_migrations.sh
```

Pinned Flutter toolchain:

```sh
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze
/Volumes/PRO-G40/flutter_3_44/bin/flutter test
```
