# Supabase Functions

Implemented production functions:

- `auth-send-whatsapp-otp`: WhatsApp OTP hook sender with rate limiting.
- `ingest-payment-sms`: MoMo SMS ingestion into `raw_payment_sms`.
- `parse-payment-sms`: service-only OpenAI parser for MoMo SMS facts.
- `allocate-payment`: service-only wrapper around Postgres allocation.

Legacy/deprecated Edge Functions for public requests and manual allocation are
not part of the deploy set. Older SQL migration history may define legacy RPCs,
but the current SMS-first migration revokes and drops that public surface.

Deploy:

```sh
supabase functions deploy auth-send-whatsapp-otp --no-verify-jwt
supabase functions deploy ingest-payment-sms
supabase functions deploy parse-payment-sms
supabase functions deploy allocate-payment
```

Security notes:

- Flutter never receives `SUPABASE_SERVICE_ROLE_KEY`, `OPENAI_API_KEY`,
  WhatsApp Cloud API tokens, or SMS gateway secrets.
- `parse-payment-sms` and `allocate-payment` require
  `INTERNAL_FUNCTION_SECRET`.
- `ingest-payment-sms` verifies the receiver can ingest for the target receiver
  MoMo hash or group receiver context before queuing parser work.
- Parser output is evidence for deterministic Postgres allocation. Ledger
  posting happens only after allocation finds a valid pending payment intent.
