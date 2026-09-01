# Supabase Edge Functions

The production inventory is intentionally limited to nine functions:

- `auth-send-whatsapp-otp`: WhatsApp OTP hook sender with rate limiting.
- `ingest-bank-email`: timestamped HMAC-authenticated bank email evidence.
- `ingest-bank-sms`: authenticated internal receiver or timestamped
  HMAC-authenticated external relay evidence.
- `ingest-bank-statement`: administrator-only CSV, JSON, MT940, or CAMT.053
  statement import followed by the governed reconciliation RPC.
- `ingest-payment-sms`: authenticated Rwanda member ingestion of consented
  Android MoMo receipts with bounded input, hashing, and idempotency.
- `parse-payment-sms`: internally authenticated deterministic MoMo parsing and
  server-only allocation.
- `verify-play-integrity`: authenticated server verification for Android-only
  private group creation.
- `send-notification`: internal preference-gated notification enqueue.
- `dispatch-notifications`: internal APNs/FCM delivery with bounded retries,
  token retirement, and attempt evidence.

Deploy with `scripts/supabase_deploy.sh`; it deploys this exact allowlist and
removes retired Stripe functions.

## Financial boundary

Rwanda MoMo ingestion can post only after an exact receiver, payer, RWF amount,
transaction ID, and time-window match to one pending intent. Incomplete or
ambiguous evidence stays in admin review. Diaspora bank SMS/email functions normalize an
event deterministically, de-duplicate it, and may exact-match its Collect
reference to an open request. They leave the request and canonical transaction
unconfirmed. Only a statement line reconciled by the database can mark a
transaction final, create its balanced journal, update member/group reporting,
and enqueue the contribution notification.

Raw evidence is service-only. An administrator needs the explicit evidence
capability and must provide an audit reason to reveal it. Members never receive
raw SMS/email, statement payloads, payer identifiers, or allocation notes.

## Authentication and secrets

- Member JWT authentication is required for Rwanda MoMo receipt upload.
- Email and external SMS relays use an HMAC over the timestamp and unmodified
  request bytes; stale or replayed evidence is rejected/de-duplicated.
- Statement import requires an authenticated admin capability.
- `send-notification` and `dispatch-notifications` require
  `INTERNAL_FUNCTION_SECRET`.
- `parse-payment-sms` requires `INTERNAL_FUNCTION_SECRET`; Play Integrity
  decoding requires `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`.
- Android push requires `FCM_SERVICE_ACCOUNT_JSON`; Apple push requires the
  governed APNs secret set described in `docs/ENVIRONMENT.md`.
- Flutter never receives service-role, bank HMAC, WhatsApp, FCM, or APNs
  credentials.

The repository and production inventory contain no payment-provider Edge
Function. MoMo remains a native USSD hand-off and receipt-evidence workflow;
there is no client secret, card, direct-debit, bank-account tokenization, or
Revolut API integration.
