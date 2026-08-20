# Architecture

Collect uses Flutter for the mobile app/Admin PWA and Supabase for Auth,
Postgres, RLS, RPCs, Realtime, and Edge Functions.

Core boundaries:

- Supabase Auth owns sessions. WhatsApp OTP is app-facing and supports valid
  international WhatsApp numbers.
- Flutter never stores service role, OpenAI, WhatsApp Cloud API, or SMS gateway
  secrets.
- Users are anonymous in product flows. The stable public identifier is the
  generated 6-digit Collect ID.
- Contributions start as Supabase payment intents, not as app-entered payment
  confirmations.
- Receiver MoMo SMS is ingested automatically and parsed by OpenAI. The locked
  Postgres allocator posts only a complete, high-confidence result that matches
  exactly one pending payer request and active receiver route.
- Posting is one atomic database transition: payment, allocation, collection
  credit, payer credit, intent state, audit record, and notification event.
- Raw SMS is protected data and is never exposed in member-facing surfaces.

Flutter structure:

- `app/router.dart`: mobile route map for Home, Groups, Settings.
- `app/theme`: Collect UI theme implementation.
- `core/security`: phone normalization, hashing, public ID helpers, Android SMS
  receiver channel.
- `features/auth`: WhatsApp OTP.
- `features/profile`: Collect ID and MoMo number.
- `features/collections`: Groups list/create/detail/manage/share/invite.
- `features/payments`: amount entry, payment intent creation, MoMo dialer launch.
- `features/ledger`: automatically allocated, immutable ledger entries.
- `admin`: separate Flutter web Admin PWA from `lib/main_admin.dart`.

Mobile workflow:

1. User signs in and receives a 6-digit Collect ID.
2. User stores a MoMo number in profile.
3. Android group creator creates a group; profile MoMo is prefilled as receiver.
4. iPhone group creation stays unavailable with the exact product warning.
5. Group is shared by link, QR code, chat app, SMS, or deep link.
6. Contributor enters amount and taps `Contribute`.
7. Supabase creates a payment intent linked to group, amount, receiver MoMo,
   contributor user id, and contributor Collect ID.
8. App opens the MoMo dialer through `tel:`.
9. MoMo SMS is uploaded to Supabase.
10. `parse-payment-sms` extracts structured facts with OpenAI.
11. `parse-payment-sms` calls the locked Postgres allocator.
12. Exactly one complete match atomically creates the posted payment,
    allocation, group credit, payer credit, audit record, and notification.
13. Duplicate events are idempotent; incomplete, low-confidence, unmatched, or
    ambiguous results remain admin-visible exceptions without a manual member
    fallback.

Admin workflow:

- Admin PWA monitors groups, members, payment intents, posted transactions, raw
  SMS metadata, parser output, allocations, exceptions, receivers, ledger,
  notification delivery, audit logs, settings, feature flags, system health,
  and admin-role assignments.
- Admin routes are operational monitoring routes, not public campaign approval
  routes.
- Raw SMS reveal, when enabled, remains permissioned and audited.
- Role changes and failed-notification retries are reason-gated, audited RPCs;
  the browser never receives notification device tokens or raw message bodies.
