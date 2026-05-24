# Architecture

Collect uses Flutter for the mobile app and Supabase for auth, database, RLS, RPCs, and Edge Functions.

Core boundaries:

- Supabase Auth owns sessions. WhatsApp OTP delivery is implemented through a Supabase hook/Edge Function.
- Flutter never stores service role, OpenAI, or WhatsApp Cloud API credentials.
- Payment instructions are manual USSD/MOMO instructions only and are rendered from Supabase instruction templates. There is no card, Stripe, Paystack, or payment gateway integration.
- SMS parsing is advisory. Deterministic Postgres logic performs allocation and ledger posting.
- Raw SMS is stored only in protected tables and never appears in public views.

Flutter structure:

- `app/router.dart`: go_router route map.
- `app/theme`: finance-grade theme tokens.
- `core/security`: phone normalization, hashing, public ID helpers.
- `features/auth`: WhatsApp OTP screens.
- `features/profile`: profile/MOMO setup.
- `features/collections`: list, create, detail, manage, share, invite.
- `features/payments`: intent and payment instruction flow.
- `features/receiver_sms`: consent and manual SMS paste.
- `features/ledger`: immutable ledger and unallocated review.
- `features/public_directory`: approved public collections.
- `admin`: separate Flutter web admin app built from `lib/main_admin.dart`.

Admin boundary:

- The customer router does not expose `/admin`.
- The admin entrypoint uses Supabase Auth and admin RPCs for overview metrics,
  queues, detail pages, moderation, public-request review, manual allocation,
  feature flags, settings, and raw-SMS reveal.
- Client-side admin guards are convenience only. Server-side RLS,
  security-definer RPCs, role/permission tables, and audit logs enforce the
  boundary.
- Raw-SMS reveal requires an admin permission, a reason, and an audit record.

Backend flow:

1. User creates a private collection with receiver MOMO number.
2. User requests public listing; platform admin approves or rejects.
3. Members are invited by phone hash or 6-digit Collect public ID through private invite tokens.
4. Contributor creates `payment_intent`, sees receiver number and configurable USSD instructions.
5. Receiver pastes SMS or internal Android receiver ingests SMS after consent.
6. `parse-payment-sms` calls OpenAI structured outputs and stores parsed facts.
7. `allocate-payment` runs deterministic matching and posts payments/ledger entries only for clear matches.
8. Ambiguous or low-confidence events stay in review.
