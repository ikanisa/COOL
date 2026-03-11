# Google Play SMS Declaration Notes

Updated: March 11, 2026

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
- driver subscriptions
- Rayon Sports tickets
- Rayon Sports shop orders
- Rayon Sports support / initiative contributions

Without Android SMS access, the app cannot automatically confirm whether the
payment actually completed after the USSD handoff.

## Scope Controls In The App

### Sender filtering

The parser only accepts approved Mobile Money sender aliases, currently:

- `M-Money`
- `MobileMoney`

Source: [momo_sms_parser.dart](/Volumes/PRO-G40/COOL/lib/core/services/momo_sms_parser.dart#L13)

### Processing behavior

- Incoming messages are ignored unless the sender matches the approved list and
  the message matches a registered Mobile Money confirmation pattern.
- Inbox scans are filtered by approved sender IDs before parsing.
- Matching M-Money confirmations are then uploaded to Supabase for
  reconciliation.

Sources:

- [momo_sms_listener.dart](/Volumes/PRO-G40/COOL/lib/core/services/momo_sms_listener.dart#L99)
- [momo_sms_listener.dart](/Volumes/PRO-G40/COOL/lib/core/services/momo_sms_listener.dart#L153)
- [momo_sms_ingestion_repository.dart](/Volumes/PRO-G40/COOL/lib/features/momo/repositories/momo_sms_ingestion_repository.dart#L42)

### User consent and disclosure

The app already includes explicit in-app disclosure before SMS sync is enabled:

- consent prompt in [app.dart](/Volumes/PRO-G40/COOL/lib/app.dart#L268)
- status / explanation screen in [momo_sms_history_screen.dart](/Volumes/PRO-G40/COOL/lib/features/momo/screens/momo_sms_history_screen.dart#L159)
- privacy policy disclosure at [privacy page](https://gen-lang-client-0172279957.web.app/privacy)

### Build and manifest

Production Android builds currently include `READ_SMS` and `RECEIVE_SMS` in
the main manifest:

- [AndroidManifest.xml](/Volumes/PRO-G40/COOL/android/app/src/main/AndroidManifest.xml#L19)

## Suggested Declaration Narrative

Use this position in the Play Console restricted-permissions form:

`Cool uses READ_SMS and RECEIVE_SMS only to detect and verify Mobile Money payment-confirmation SMS that complete user-initiated financial transactions after a USSD handoff. The app filters to approved Mobile Money sender IDs and uses the resulting confirmation data to reconcile group contributions, mobility subscription payments, and partner transactions. Cool does not use SMS access for personal messaging, contact discovery, marketing, or general inbox reading.`

## Reviewer Evidence To Attach

Capture and provide:

1. The consent prompt that explains only approved M-Money sender IDs are processed.
2. The M-Money verification status/history screen.
3. A short video showing:
   - user initiates a USSD payment
   - M-Money confirmation SMS arrives
   - Cool detects it
   - transaction status changes to confirmed
4. Privacy policy URL:
   - `https://gen-lang-client-0172279957.web.app/privacy`
5. Test account / review-access details from [play_review_access.md](/Volumes/PRO-G40/COOL/docs/play_review_access.md#L1)

## Remaining Requirement

The SMS declaration is only one part of approval. Review access still depends
on fixing the hosted Supabase Auth configuration so the OTP test account can
actually create a session.

## Official Sources

- Google Play restricted permissions policy:
  https://support.google.com/googleplay/android-developer/answer/9888170
- Google Play SMS / Call Log exceptions:
  https://support.google.com/googleplay/android-developer/answer/10208820
