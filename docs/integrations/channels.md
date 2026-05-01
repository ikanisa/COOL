# Channel Integrations

Channel adapters must be backend-authorized, auditable, rate limited where needed, and safe to disable. Active code currently lives in runtime-owned locations rather than shared `integrations/` packages.

## Inventory

| Channel | Current source | Status | Notes |
| --- | --- | --- | --- |
| WhatsApp OTP | `supabase/functions/_shared/whatsapp.ts`, `lib/core/services/whatsapp_otp_service.dart` | Active OTP helper/client path | Secrets must stay server-side; rate limits and OTP hashing apply. |
| Android SMS / MoMo evidence | `lib/features/momo/services`, `supabase/functions/sms-ingest`, `supabase/functions/parse-momo-sms` | Active evidence ingestion and parsing | SMS is evidence only, not payment confirmation. |
| Push notifications | Flutter FCM services, notification tables/functions | Active readiness path | Respect notification preferences and campaign approvals. |
| Google Workspace | `supabase/functions/_shared/google_workspace.ts` | Fail-closed unless configured | Tests cover safe failure when config is missing. |
| Email | Not active as shared adapter | Future | Requires consent, templates, bounces, unsubscribe, and audit. |
| Telegram | Not active | Future | Requires channel identity, auth mapping, opt-in, and abuse controls. |
| Google Chat | Not active | Future | Requires workspace auth and scoped admin approval. |
| Teams | Not active | Future | Requires tenant/app registration and audit. |
| Voice | Not active | Future | Requires consent, recording/transcription policy, retention, and escalation. |

## Environment variable names

Values must not be committed. Names may vary by provider, but active/future channel config should include:

- Supabase URL, anon key, and server-side service credentials in secure stores only.
- OTP hashing/phone password secrets.
- WhatsApp provider token, sender id, webhook secret, and template ids.
- FCM/Firebase/App Check configuration.
- Google service account email, private key, and target sheet/document ids where used.
- Provider-specific webhook secrets for future email, Telegram, Chat, Teams, or voice channels.

## Channel safety rules

- Authenticate inbound requests and verify provider signatures where supported.
- Authorize any privileged action after channel identity is mapped to a user/role.
- Rate limit OTP, public inbound messages, and campaign/outbound sends.
- Log safely without OTPs, tokens, full private messages, or unnecessary raw SMS content.
- Respect opt-out, quiet hours, consent, and campaign approval where relevant.
- Provide a kill switch for outbound campaigns and privileged agent/tool paths.

## Tests

```bash
deno test --allow-env=SUPABASE_SERVICE_ROLE_KEY,AUTH_PHONE_PASSWORD_SECRET,OTP_CODE_HASH_SECRET,OTP_TEST_PHONE,OTP_TEST_CODE,GOOGLE_SERVICE_ACCOUNT_EMAIL,GOOGLE_PRIVATE_KEY,AI_AUDIT_SHEET_ID $(find supabase/functions -type f -name '*_test.ts' | sort)
scripts/dev/flutterw test test/features/momo/momo_sms_autoread_service_test.dart
```
