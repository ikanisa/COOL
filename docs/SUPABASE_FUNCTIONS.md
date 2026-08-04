# Supabase Functions

Implemented production functions:

- `auth-send-whatsapp-otp`: WhatsApp OTP hook sender with rate limiting.
- `ingest-payment-sms`: MoMo SMS ingestion into `raw_payment_sms`.
- `parse-payment-sms`: service-only OpenAI parser for MoMo SMS facts.
- `allocate-payment`: service-only wrapper around Postgres allocation.
- `send-notification`: internal, preference-gated notification event enqueue.
- `dispatch-notifications`: internal APNs queue dispatcher with bounded retries,
  invalid-token retirement, and per-attempt evidence.
- `stripe-create-customer`: authenticated Stripe Customer setup for diaspora
  rails.
- `stripe-create-setup-intent`: authenticated saved-bank setup for ACH Direct
  Debit and Canadian Pre-authorized Debit only.
- `stripe-create-diaspora-contribution`: authenticated diaspora contribution
  PaymentIntent creation for ACH Direct Debit in the US, EUR Bank Transfer in
  Europe, GBP Bank Transfer in the United Kingdom, and Canadian Pre-authorized
  Debit in Canada.
- `stripe-webhook`: Stripe signature-verified webhook receiver for idempotent
  diaspora contribution status updates.

Legacy/deprecated Edge Functions for public requests and manual allocation are
not part of the deploy set. Older SQL migration history may define legacy RPCs,
but the current SMS-first migration revokes and drops that public surface.

Deploy:

```sh
supabase functions deploy auth-send-whatsapp-otp --no-verify-jwt
supabase functions deploy ingest-payment-sms
supabase functions deploy parse-payment-sms
supabase functions deploy allocate-payment
supabase functions deploy send-notification
supabase functions deploy dispatch-notifications
supabase functions deploy stripe-create-customer
supabase functions deploy stripe-create-setup-intent
supabase functions deploy stripe-create-diaspora-contribution
supabase functions deploy stripe-webhook --no-verify-jwt
```

Security notes:

- Flutter never receives `SUPABASE_SERVICE_ROLE_KEY`, `OPENAI_API_KEY`,
  WhatsApp Cloud API tokens, or SMS gateway secrets.
- `parse-payment-sms` and `allocate-payment` require
  `INTERNAL_FUNCTION_SECRET`.
- `send-notification` and `dispatch-notifications` require
  `INTERNAL_FUNCTION_SECRET`. APNs delivery additionally requires
  `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, and
  `APNS_PRIVATE_KEY_BASE64` in the Supabase secret store.
- `ingest-payment-sms` verifies the receiver can ingest for the target receiver
  MoMo hash or group receiver context before queuing parser work.
- Parser output is evidence for deterministic Postgres allocation. Ledger
  posting happens only after allocation finds a valid pending payment intent.
- Stripe functions require `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, and
  explicit sandbox/live environment separation. The approved fee-sensitive rails
  are strictly ACH Direct Debit (`us_bank_account`), EUR Bank Transfer
  (`customer_balance` with `eu_bank_transfer`), and GBP Bank Transfer
  (`customer_balance` with `gb_bank_transfer`), plus Canadian Pre-authorized
  Debit (`acss_debit`) for domestic CAD bank debits. Region and currency must
  match: US/USD, EU/EUR, GB/GBP, CA/CAD. ACH and ACSS setup/contribution
  PaymentIntents must force `verification_method=microdeposits`; do not enable
  instant bank account validation, Financial Connections instant verification,
  two-day settlement, currency conversion, cross-border bank-transfer funding,
  live Stripe keys, webhook endpoints, Connect routing, provider submissions,
  extra payment methods, or app release claims without recorded human go-live
  approval.
- Client code receives Stripe client secrets only. Collect servers do not store
  raw bank-account numbers, routing numbers, IBANs, or card PAN data.
