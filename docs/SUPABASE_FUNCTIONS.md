# Supabase Edge Functions

The production inventory is intentionally limited to six functions:

- `auth-send-whatsapp-otp`: WhatsApp OTP hook sender with rate limiting.
- `ingest-bank-email`: timestamped HMAC-authenticated bank email evidence.
- `ingest-bank-sms`: authenticated internal receiver or timestamped
  HMAC-authenticated external relay evidence.
- `ingest-bank-statement`: administrator-only CSV, JSON, MT940, or CAMT.053
  statement import followed by the governed reconciliation RPC.
- `send-notification`: internal preference-gated notification enqueue.
- `dispatch-notifications`: internal APNs/FCM delivery with bounded retries,
  token retirement, and attempt evidence.

Deploy with `scripts/supabase_deploy.sh`; it deploys this exact allowlist and
removes every retired payment, SMS-parser, Stripe, and Play-Integrity function.

## Financial boundary

Evidence ingestion is not settlement. The bank SMS/email functions normalize an
event deterministically, de-duplicate it, and may exact-match its Collect
reference to an open request. They leave the request and canonical transaction
unconfirmed. Only a statement line reconciled by the database can mark a
transaction final, create its balanced journal, update member/group reporting,
and enqueue the contribution notification.

Raw evidence is service-only. An administrator needs the explicit evidence
capability and must provide an audit reason to reveal it. Members never receive
raw SMS/email, statement payloads, payer identifiers, or allocation notes.

## Authentication and secrets

- Member/operator JWT authentication is required for internal SMS upload.
- Email and external SMS relays use an HMAC over the timestamp and unmodified
  request bytes; stale or replayed evidence is rejected/de-duplicated.
- Statement import requires an authenticated admin capability.
- `send-notification` and `dispatch-notifications` require
  `INTERNAL_FUNCTION_SECRET`.
- Android push requires `FCM_SERVICE_ACCOUNT_JSON`; Apple push requires the
  governed APNs secret set described in `docs/ENVIRONMENT.md`.
- Flutter never receives service-role, bank HMAC, WhatsApp, FCM, or APNs
  credentials.

The repository and production inventory contain no payment-provider Edge
Function. There is no client secret, webhook, card, direct-debit, bank-account
tokenization, or Revolut API integration.
