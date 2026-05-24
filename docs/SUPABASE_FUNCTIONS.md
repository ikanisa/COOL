# Supabase Functions

Implemented functions:

- `auth-send-whatsapp-otp`: Supabase SMS hook-compatible WhatsApp OTP sender with rate limiting.
- `ingest-payment-sms`: authenticated receiver/admin raw SMS ingestion, gated
  by `user_can_ingest_receiver_sms` against the collection receiver MOMO hash.
- `parse-payment-sms`: service-only OpenAI structured output parser.
- `allocate-payment`: service-only wrapper around deterministic Postgres allocation.
- `manual-allocate-payment`: authenticated collection admin manual allocation with reason.
- `request-public-collection`: collection admin public listing request.
- `review-public-collection`: platform admin approval/rejection.

Deploy example:

```sh
supabase functions deploy auth-send-whatsapp-otp --no-verify-jwt
supabase functions deploy ingest-payment-sms
supabase functions deploy parse-payment-sms
supabase functions deploy allocate-payment
supabase functions deploy manual-allocate-payment
supabase functions deploy request-public-collection
supabase functions deploy review-public-collection
```

Do not expose `SUPABASE_SERVICE_ROLE_KEY`, `OPENAI_API_KEY`, or WhatsApp Cloud API tokens to Flutter.

Security notes:

- `auth-send-whatsapp-otp` has platform JWT verification disabled because
  Supabase Auth HTTP hooks are webhook-style calls. The function verifies the
  Standard Webhooks signature using `SEND_SMS_HOOK_SECRET`, reads the documented
  `sms.otp` payload field, and also supports an explicit `x-hook-secret` header
  for controlled operational tests.
- `parse-payment-sms` and `allocate-payment` require
  `INTERNAL_FUNCTION_SECRET`; they must not be callable as public endpoints.
- `ingest-payment-sms` calls `parse-payment-sms` with
  `INTERNAL_FUNCTION_SECRET` after receiver authorization succeeds.
