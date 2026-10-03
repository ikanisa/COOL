# Supabase Edge Functions

The current Rwanda MoMo inventory contains eight functions:

- `auth-send-whatsapp-otp`: WhatsApp OTP hook sender with rate limiting.
- `collect-notification-operator`: authenticated notification operations.
- `ingest-payment-sms`: authenticated ingestion of consented Android MoMo receipts with bounded input, hashing, and idempotency.
- `parse-payment-sms`: internally authenticated deterministic MoMo parsing and server-only allocation.
- `prepare-roster-import`: authenticated group roster preparation.
- `verify-play-integrity`: authenticated server verification for Android-only private group creation.
- `send-notification`: internal preference-gated notification enqueue.
- `dispatch-notifications`: internal APNs/FCM delivery with bounded retries and attempt evidence.

Deploy with `scripts/supabase_deploy.sh`. The deployment inventory also removes retired external payment functions.

## Financial boundary

A MoMo receipt can post only after an exact receiver, payer, whole-RWF amount, transaction ID, and time-window match to one pending intent. Incomplete or ambiguous evidence stays in Admin review. Ledger posting is idempotent. Raw evidence is service-only; audited reveal requires an explicit Admin capability and reason.

## Authentication and secrets

Member JWT authentication is required for MoMo receipt upload. Internal functions require `INTERNAL_FUNCTION_SECRET`. Play Integrity decoding requires `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`. Android push requires `FCM_SERVICE_ACCOUNT_JSON`; Apple push requires the governed APNs secret set in `docs/ENVIRONMENT.md`. Flutter never receives service-role, WhatsApp, FCM, or APNs credentials.

MoMo authorization occurs in the mobile-network USSD prompt. Collect receives confirmation evidence after authorization.
