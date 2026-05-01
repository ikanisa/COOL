# Integrations

Cross-product channel and provider adapters belong here only after they are
shared across more than one app or runtime.

## Target integration boundaries

- `whatsapp/` — WhatsApp OTP and notification adapters.
- `telegram/` — Telegram channel adapters.
- `google-chat/` — Google Chat channel adapters.
- `teams/` — Microsoft Teams channel adapters.
- `email/` — email delivery and inbound processing.
- `voice/` — voice call and transcription adapters.
- `ussd/` — USSD route generation and validation contracts.
- `payments/` — external payment guidance, references, and provider state
  contracts.

## Current source locations

- WhatsApp OTP server helper: `supabase/functions/_shared/whatsapp.ts`.
- Flutter WhatsApp OTP client: `lib/core/services/whatsapp_otp_service.dart`.
- Android SMS/M-Money sync: `lib/features/momo/services` and
  `supabase/functions/{sms-ingest,parse-momo-sms}`.
- Google Workspace helper: `supabase/functions/_shared/google_workspace.ts`
  and currently fail-closed.

Do not move a single-runtime adapter here until its import graph and release
owner are clear.
