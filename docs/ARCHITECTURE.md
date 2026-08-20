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
- Receiver MoMo SMS is ingested automatically, parsed by OpenAI, and matched to
  pending payment intents in Postgres as candidate evidence only. It never
  establishes provider settlement or changes a balance.
- A separately trusted, signed provider-finality gateway confirms or rejects
  candidates. Only a confirmed event posts the immutable ledger pair.
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
- `features/ledger`: independently provider-confirmed ledger entries.
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
11. `parse-payment-sms` calls the locked Postgres allocator, which creates an
    awaiting-provider-confirmation candidate without ledger impact.
12. A trusted connector validates provider/bank settlement and sends an exact
    HMAC-signed event to `provider-finality`.
13. The replay-safe gateway confirms or rejects the candidate transactionally.
    Confirmation alone posts one collection credit and one member credit.
14. Ambiguous parser/allocation/provider results stay as admin-visible exceptions, not
    member-entered fallbacks.

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
