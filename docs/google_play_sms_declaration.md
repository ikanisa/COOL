# Google Play SMS Declaration Notes

Updated: March 13, 2026

This document prepares the restricted SMS-permission declaration for the Cool
Android app.

## Requested Permissions

- `android.permission.READ_SMS`
- `android.permission.RECEIVE_SMS`

These permissions are required for Android M-Money payment-confirmation
verification, which is a core part of the app's transaction reconciliation
flow.

## Core Use Case

Cool launches payer-owned Mobile Money USSD flows, then verifies successful
payment completion by processing incoming Mobile Money confirmation SMS on the
same Android device.

That verification is used to reconcile:

- community group contributions
- saving-group related payments
- Rayon Sports tickets
- Rayon Sports shop orders
- Rayon Sports support / initiative contributions

Without Android SMS access, the app cannot automatically confirm whether the
payment actually completed after the USSD handoff.

## Scope Controls In The App

### Sender filtering

The Android SMS ingest path only accepts approved Mobile Money sender aliases,
currently including:

- `M-Money`
- `MobileMoney`
- `Mobile Money`
- `MoMo`
- `MTN MoMo`

Sources:

- [momo_sms_ingestion_repository.dart](/Volumes/PRO-G40/COOL/lib/features/momo/repositories/momo_sms_ingestion_repository.dart#L58)
- [momo_sms_ingestion_repository.dart](/Volumes/PRO-G40/COOL/lib/features/momo/repositories/momo_sms_ingestion_repository.dart#L105)

### Processing behavior

- Incoming messages are ignored unless the sender matches the approved list.
- Inbox recovery scans are filtered by approved sender IDs only.
- Inbox recovery is limited to a recent operational window and capped volume.
- Approved-sender messages are uploaded to Supabase, where server-side parsing
  determines whether they are valid M-Money confirmations for reconciliation.

Sources:

- [momo_sms_autoread_service.dart](/Volumes/PRO-G40/COOL/lib/features/momo/services/momo_sms_autoread_service.dart#L165)
- [momo_sms_autoread_service.dart](/Volumes/PRO-G40/COOL/lib/features/momo/services/momo_sms_autoread_service.dart#L281)
- [momo_sms_ingestion_repository.dart](/Volumes/PRO-G40/COOL/lib/features/momo/repositories/momo_sms_ingestion_repository.dart#L115)

### User consent and disclosure

The app already includes explicit in-app disclosure before SMS sync is enabled:

- SMS access disclosure in [profile_app_access_sheet.dart](/Volumes/PRO-G40/COOL/lib/features/profile/widgets/profile_app_access_sheet.dart#L712)
- Mobile Money hub in [momo_screen.dart](/Volumes/PRO-G40/COOL/lib/features/momo/screens/momo_screen.dart#L1)
- privacy policy disclosure at [privacy page](https://cool.ikanisa.com/privacy)

### Build and manifest

Production Android builds currently include `READ_SMS` and `RECEIVE_SMS` in
the main manifest:

- [AndroidManifest.xml](/Volumes/PRO-G40/COOL/android/app/src/main/AndroidManifest.xml#L19)

## Suggested Declaration Narrative

Use this position in the Play Console restricted-permissions form:

`Cool uses READ_SMS and RECEIVE_SMS only to process SMS from approved Mobile Money sender IDs after user-initiated USSD payment flows. The app filters inbox access to approved sender IDs, limits recovery to a recent operational window, and sends matching sender messages to Supabase where server-side parsing determines whether they complete group or partner transactions. Cool does not use SMS access for personal messaging, contact discovery, marketing, or general inbox reading.`

## Reviewer Evidence To Attach

Capture and provide:

1. The in-app SMS disclosure that explains only approved M-Money sender IDs are processed.
2. The Mobile Money hub / payment verification surface.
3. A short video showing:
   - user initiates a USSD payment
   - M-Money confirmation SMS arrives
   - Cool detects it
   - transaction status changes to confirmed
4. Privacy policy URL:
   - `https://cool.ikanisa.com/privacy`
5. Test account / review-access details from [play_review_access.md](/Volumes/PRO-G40/COOL/docs/play_review_access.md#L1)

## AI-Powered Transaction Parsing Disclosure

Cool transmits the **full SMS body** of approved Mobile Money sender messages
to server-side AI APIs (Google Gemini and/or OpenAI) for structured transaction
parsing. This is a **core functional requirement** — the AI parser must see the
complete message to accurately extract:

- Transaction type (sent, received, payment, deposit, withdrawal)
- Amount and currency
- Payer/payee name
- Transaction ID
- Date/time
- Account balance

### Why redaction is not applied before AI transmission

Redacting PII (phone numbers, transaction IDs, balances) before sending to AI
would destroy the data the parser needs to extract. For example:
- Transaction IDs become `[REF_REDACTED]` → no reconciliation possible
- Phone numbers become `[PHONE_REDACTED]` → no payer identification
- Balances become `[HIDDEN]` → no ledger verification

### Data handling

- Only messages from **approved M-Money sender IDs** are transmitted
- AI parsing happens on Supabase Edge Functions (server-to-server)
- Parsed structured data is stored; raw bodies are retained for audit
- Users can delete their SMS records via in-app controls (DELETE RLS enabled)
- Privacy policy at `https://cool.ikanisa.com/privacy` must disclose:
  1. That M-Money SMS content is processed by AI services
  2. That Google Gemini and OpenAI are used as processing providers
  3. That raw message bodies are retained for transaction audit purposes
  4. That users can request deletion of their SMS data

### Privacy policy update checklist

- [ ] Add "SMS Data Processing" section to privacy policy page
- [ ] List Gemini and OpenAI as sub-processors
- [ ] State data retention period for raw SMS bodies
- [ ] Document user's right to delete SMS data

## Remaining Requirement

The SMS declaration is only one part of approval. Review access still depends
on fixing the hosted Supabase Auth configuration so the OTP test account can
actually create a session.

## Official Sources

- Google Play restricted permissions policy:
  https://support.google.com/googleplay/android-developer/answer/9888170
- Google Play SMS / Call Log exceptions:
  https://support.google.com/googleplay/android-developer/answer/10208820
