# Collect

Collect is a Flutter and Supabase platform for SMS-first MoMo group contributions.
Members contribute through payment intents created in the app; MoMo SMS
is ingested, parsed with OpenAI, allocated in Supabase, and posted to the ledger.

Current product scope is documented in `docs/PRODUCT.md`. Current release
status is documented in `docs/release/RELEASE_STATUS.md`.

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
3. Android group creation is allowed only after the production build confirms
   receive-only MoMo SMS access and the backend confirms the receiver matches
   the creator's linked MoMo number or 4-to-9-digit merchant code.
4. iPhone group creation is blocked with `group creation is available only on Android`.
5. Members join from a revocable high-entropy link or QR code shared through
   the native Android share sheet. Public groups also support reviewed discovery;
   private slugs are never treated as invitation credentials.
6. Member taps `Contribute`, enters amount, and Supabase creates a pending
   payment intent linked to group, amount, receiver MoMo, user id, and Collect ID.
7. On supported Android builds, the allowlisted native `ACTION_CALL` bridge opens
   only the exact Collect merchant USSD request; the member confirms all carrier,
   PIN, and final payment steps.
8. MoMo SMS is atomically uploaded to Supabase, leased to the parser and matched
   to the pending intent as evidence awaiting provider confirmation. SMS alone
   never changes a balance. Only an authenticated service-side provider finality
   event posts exactly one collection credit and one payer credit. Server-owned
   aggregate RPCs expose group and current-payer balances without exposing other
   payers' private payment rows.

The current group-journey hardening is the reviewed migration chain from
`20260815050900_harden_momo_sms_standalone_posting.sql` through
`20260815084500_revoke_non_dml_table_privileges.sql`. It adds server-attested,
request-bound Android creation; owner-derived receiver enforcement; reviewable
visibility; private rotatable share codes; atomic safe joins; member-gated
contribution requests; provider-global payment idempotency; provider-finality
ledger posting; audited notifications; and privacy-preserving balance summaries.

There is no manual SMS paste, no reported transaction ID field, and no anonymity
picker. Category-specific collection context and diaspora rails are allowed only
where explicitly implemented and approval-gated; the default Rwanda MoMo flow
remains non-custodial and Collect-ID-first.

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
/Users/jeanbosco/Developer/flutter/bin/flutter analyze
/Users/jeanbosco/Developer/flutter/bin/flutter test
```
