# Supabase Functions

Implemented production functions:

- `auth-send-whatsapp-otp`: WhatsApp OTP hook sender with rate limiting.
- `ingest-payment-sms`: MoMo SMS ingestion into `raw_payment_sms`.
- `parse-payment-sms`: service-only OpenAI parser that invokes the locked
  Postgres allocator after successful structured parsing.
- `send-notification`: internal, preference-gated notification event enqueue.
- `dispatch-notifications`: internal APNs/FCM queue dispatcher with bounded
  retries, invalid-token retirement, and per-attempt evidence.
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
- `verify-play-integrity`: authenticated Google Play Integrity decoder and
  verdict recorder for the production Android package.

Legacy/deprecated Edge Functions for public requests and manual allocation are
not part of the deploy set. Older SQL migration history may define legacy RPCs,
but the current SMS-first migration revokes and drops that public surface.

Deploy:

```sh
supabase functions deploy auth-send-whatsapp-otp --no-verify-jwt
supabase functions deploy ingest-payment-sms
supabase functions deploy parse-payment-sms
supabase functions deploy send-notification
supabase functions deploy dispatch-notifications
supabase functions deploy stripe-create-customer
supabase functions deploy stripe-create-setup-intent
supabase functions deploy stripe-create-diaspora-contribution
supabase functions deploy stripe-webhook --no-verify-jwt
supabase functions deploy verify-play-integrity
```

Security notes:

- Flutter never receives `SUPABASE_SERVICE_ROLE_KEY`, `OPENAI_API_KEY`,
  WhatsApp Cloud API tokens, or SMS gateway secrets.
- `parse-payment-sms` requires `INTERNAL_FUNCTION_SECRET`.
- `send-notification` and `dispatch-notifications` require
  `INTERNAL_FUNCTION_SECRET`. APNs delivery additionally requires
  `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, and
  `APNS_PRIVATE_KEY_BASE64`; Android delivery requires
  `FCM_SERVICE_ACCOUNT_JSON` in the Supabase secret store.
- `ingest-payment-sms` verifies current consent and that the authenticated user
  owns an active group receiving route. A supplied receiver hash must match
  exactly; a provider message that omits the receiver can still be captured.
- The OpenAI Responses API parses each opted-in MoMo SMS with a strict JSON
  schema. Postgres posts only after the parsed
  transaction, amount, payer identity, time window, and an active receiver
  owned by the SMS account match exactly one pending payment intent. The model
  never chooses the target group. The locked database transition atomically
  creates both balance credits and all linked transaction evidence.
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
