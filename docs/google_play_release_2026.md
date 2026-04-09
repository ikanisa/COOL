# Google Play Release Checklist

Updated: March 13, 2026

This checklist captures the current release state of the Cool Android app and
the remaining Google Play and Firebase work.

## Current App State

- Android package ID is now `app.cool.mobile`.
- Release signing is configured with an upload key in `android/key.properties`.
- The Android app is registered in Firebase for project
  `gen-lang-client-0172279957`, and Android config is checked in at
  `android/app/google-services.json`.
- The production Android source manifest targets Android API 36 and declares:
  - location
  - camera
  - NFC
  - `READ_SMS`
  - `RECEIVE_SMS`
  - `POST_NOTIFICATIONS`
  - Google/Firebase-added `AD_ID`
- Android M-Money SMS verification remains enabled for production builds.
- The build flag `ENABLE_ANDROID_MOMO_SMS_AUTOREAD` defaults to `true`, and
  `scripts/build_play_release.sh` also forces it on for release builds.
- The current on-disk AAB predates this restoration of release SMS permissions,
  so a fresh signed AAB must be rebuilt before upload.
- Reviewer OTP auth no longer depends on hosted phone login. `verify-otp` now
  mints sessions through the app's deterministic internal email identity path.
- OTP abuse controls are now enforced server-side with per-phone and per-IP
  rate limits plus deterministic auth-user lookup.
- Cool is implemented as a USSD/SMS reconciliation bridge for community-group
  collections, bank-managed custody flows, and BioPay-adjacent settlement
  verification.
- Community-group collections already route to recipient data stored on
  `public.groups`:
  - `receiving_momo_code`
  - `receiving_momo_route_type`
  - `momo_number`
- Active mobile flows no longer depend on a hardcoded Rayon-specific MoMo code.
- Bank workspace allocations and service routing are administered from
  Supabase-backed config instead of app-side brand-specific constants.

## Official Requirement Summary

### Google Play

- Target API policy:
  - Google Play requires apps to target recent Android API levels.
  - The current Cool release manifest targets API 36, which is ahead of the
    policy floor as of March 11, 2026.
- Bundle format:
  - New Play releases should be uploaded as Android App Bundles (`.aab`).
  - Play App Signing should be enabled for ongoing key management.
- Privacy policy:
  - Apps that handle personal or sensitive user data must provide a valid
    privacy policy in the Play Console and inside the store listing flow.
- Account deletion:
  - Apps that allow account creation must provide an in-app path to request or
    trigger account deletion, and a public web resource for deletion guidance.
- Sensitive permissions:
  - `READ_SMS` and `RECEIVE_SMS` are restricted permissions.
  - Google Play documents a limited exception path for SMS-based financial
    transactions, but review and approval are required.
- Data safety:
  - The Play Console Data safety form must match actual data collection and all
    included SDK behavior.
- Ad ID:
  - The release manifest currently contains `com.google.android.gms.permission.AD_ID`.
  - The Play Console Ad ID declaration must be consistent with that manifest.

### Firebase App Distribution

- Android app distribution requires a Firebase Android app registered to the
  final package name.
- Test release distribution can be done from CLI using:
  - `firebase appdistribution:group:create`
  - `firebase appdistribution:testers:add --group-alias`
  - `firebase appdistribution:distribute <aab-or-apk> --app <app_id> --groups <alias>`
- Firebase sends tester invitations and release notifications when testers or
  groups are included in distribution commands.

## High-Risk Release Blockers

1. A fresh signed AAB still needs to be rebuilt after restoring production SMS
   permissions.
   - The manifest and release script are now back on the restricted-SMS path.
   - The last built AAB on disk was created during the SMS-free pass.
   - Result: do not upload the current AAB until it is rebuilt on the restored
     manifest path.

2. Play policy review risk remains around the SMS capability itself.
   - The app intentionally ships `READ_SMS` and `RECEIVE_SMS` because M-Money
     payment-confirmation verification is a core function.
   - Submission now depends on a strong restricted-permissions declaration,
     matching disclosure copy, and reviewer evidence.
   - The repo-backed declaration notes live in
     `docs/google_play_sms_declaration.md`.

3. Reviewer access still needs signed-build validation, but the backend auth
   blocker is closed.
   - OTP input validation is fixed and no longer returns `500` for bad phone
     input.
   - `OTP_TEST_PHONE` and `OTP_TEST_CODE` are now stored on the linked
     Supabase project, so the review-number bypass itself is active.
   - `verify-otp` no longer depends on hosted phone login and now resolves
     existing auth users through a deterministic service-role lookup instead of
     paging through `listUsers()`.
   - Result: the remaining task is connected-device validation on the linked
     project and a signed build, not Supabase Auth reconfiguration.

4. Data safety and Ads declarations remain open.
   - The release manifest includes `POST_NOTIFICATIONS` plus Firebase/Google
     analytics and ad-services permissions.
   - Result: the Play Console Data safety form and Ads / Ad ID declaration
     still need to be completed against the actual release artifact.

5. Dynamic recipient-routing still needs production verification across all
   managed bank workspaces.
   - Community groups already store their own recipient route in Supabase.
   - Active mobile clients no longer hardcode a Rayon-specific route, but
     historical migrations still carry legacy partner assumptions.
   - Result: validate that every production bank workspace is backed by the
     intended Supabase recipient config before the next Play upload.

6. Store listing assets are still incomplete.
   - App icon and in-app branding assets are implemented.
   - Play listing screenshots, feature graphic, and final store copy are still
     not checked in.

## Completed Work In This Session

- Replaced the placeholder Android package identifier with `app.cool.mobile`.
- Preserved release signing configuration and verified the upload keystore is
  present.
- Added concrete legal URL configuration:
  - `COOL_PRIVACY_POLICY_URL`
  - `COOL_TERMS_OF_SERVICE_URL`
  - `COOL_ACCOUNT_DELETION_URL`
- Made the OTP legal text open the configured terms and privacy URLs.
- Hardened OTP edge-function validation so bad phone input returns `400` from
  both `send-otp` and `verify-otp` instead of surfacing as generic `500`
  errors.
- Added an in-app delete-account flow in Profile and a matching authenticated
  `delete-account` Supabase Edge Function.
- Deployed `send-otp`, `verify-otp`, and `delete-account` to the linked
  Supabase project `lhbowpbcpwoiparwnwgt`.
- Published live legal pages on Firebase Hosting:
  - `https://cool.ikanisa.com/privacy`
  - `https://cool.ikanisa.com/terms`
  - `https://cool.ikanisa.com/account-deletion`
- Added an optional Play review OTP bypass in `send-otp`, controlled by the
  `OTP_TEST_PHONE` and `OTP_TEST_CODE` Supabase secrets.
- Added server-side OTP abuse protections:
  - per-phone send limits
  - per-IP send limits
  - per-IP verify-attempt limits
- Replaced `verify-otp` auth-user repair via `listUsers()` pagination with the
  deterministic RPC `public.find_auth_user_by_phone_or_email(...)`.
- Restored `READ_SMS` and `RECEIVE_SMS` to the production Android manifest for
  M-Money financial transaction verification.
- Restored `ENABLE_ANDROID_MOMO_SMS_AUTOREAD` to the production-on path and
  updated the release script accordingly.
- Added a repo-backed restricted-permission declaration guide in
  `docs/google_play_sms_declaration.md`.
- Replaced the placeholder launcher and splash assets with the provided Cool
  brand mark and generated Android/iOS app icon assets.
- Cleared the current Dart analyzer warnings that were failing the release
  readiness script.
- Verified targeted hardening checks pass locally:
  - OTP/auth edge functions type-check
  - OTP abuse helper tests pass
  - SMS boundary tests pass
- The full repo test suite should be rerun on the stabilized remediation
  branch before upload.
- Added `scripts/build_play_release.sh` to build a Play-ready AAB with required
  `--dart-define` values.

## Required Next Actions

### Google Play Console

1. Rebuild a fresh release AAB on the restored restricted-SMS manifest path.
2. Upload that fresh release AAB.
3. Complete:
   - App access
   - Ads / Ad ID declaration
   - Data safety
   - Content rating
   - Privacy policy
   - Financial features / permissions declarations
4. Submit the restricted SMS-permission declaration using the repo-backed
   evidence in `docs/google_play_sms_declaration.md`.

### Product / UX Compliance

1. Verify the in-app deletion flow end to end on a signed Android build using a
   disposable test account.
2. Decide whether partner bank/Rayon recipient routing must be fully dynamic
   from Supabase before release, then implement the required schema/client
   changes if yes.
3. Validate the review bypass end to end on a signed Android build against the
   linked Supabase project.
4. Once that signed-build auth path is validated, use the configured `OTP_TEST_PHONE` and
   `OTP_TEST_CODE` in the Play Console app-access form.
5. Prepare Play listing screenshots, feature graphic, and final store copy.

## Local Build Command

> **⛔ CRITICAL BLOCKER — production Supabase config MUST be set.**
> `SUPABASE_PRODUCTION_URL` and `SUPABASE_PRODUCTION_ANON_KEY` are the
> preferred release inputs. Legacy `SUPABASE_URL` and `SUPABASE_ANON_KEY`
> still work as a fallback, but should not be the primary production path.
> Without a valid production backend contract the APK/AAB will crash at
> startup or show a config error screen, and the build script will abort.

```bash
SUPABASE_PRODUCTION_URL="https://your-project.supabase.co" \
SUPABASE_PRODUCTION_ANON_KEY="your-anon-key" \
bash scripts/build_play_release.sh
```

Mobility subscription recipient codes are configured in Admin > App Config,
not via build-time `--dart-define`.

## Official Sources

- Google Play target API policy:
  https://support.google.com/googleplay/android-developer/answer/11926878
- Restricted permissions policy:
  https://support.google.com/googleplay/android-developer/answer/9888170
- SMS and Call Log exceptions:
  https://support.google.com/googleplay/android-developer/answer/10208820
- Privacy policy requirement:
  https://support.google.com/googleplay/android-developer/answer/10144311
- Account deletion requirement:
  https://support.google.com/googleplay/android-developer/answer/13327111
- Android App Bundles:
  https://developer.android.com/guide/app-bundle
- Firebase App Distribution CLI:
  https://firebase.google.com/docs/app-distribution/android/distribute-cli
- Firebase Play data disclosure guidance:
  https://firebase.google.com/docs/android/play-data-disclosure
