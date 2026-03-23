# BioPay Supabase Implementation Plan

## Decisions

- BioPay is `Supabase-first`. Product data, consent, audit, revocation, and match telemetry live in Supabase.
- Firebase does not participate in BioPay.
- Phone OTP is not part of BioPay enrollment. The signed-in Cool session is the trust anchor.
- BioPay enrollment derives the payout route from the signed-in Cool user profile on the server. The client does not get to override route ownership.
- BioPay is mounted under the existing MoMo hub, not as a new shell tab.
- Rwanda is the only supported BioPay market in this codebase for v1.

## Frontend shape

- Entry route: `/momo/biopay`
- New module: `lib/features/biopay/`
- Main screens:
  - `BiopayHomeScreen`
  - `BiopayRegisterScreen`
  - `BiopayScanScreen`
  - `BiopayConfirmScreen`
- Shared services:
  - `BiopayRepository`
  - `BiopayDialerService`
  - `BiopayCacheService`
- Current scanner implementation is a secure camera shell. The on-device face pipeline plugs into this screen next.

## Backend shape

- Migration: `20260322190000_biopay_supabase_foundation.sql`
- Core tables:
  - `biopay_profiles`
  - `biopay_embeddings`
  - `biopay_match_events`
  - `biopay_enrollment_audits`
  - `biopay_revocations`
- RPCs:
  - `biopay_upsert_enrollment`
  - `match_biopay_profile`
  - `biopay_revoke_profile`
- Edge Functions:
  - `biopay-enroll`
  - `biopay-match`
  - `biopay-revoke`

## BioPay app config

- `feature_biopay_enabled`
- `biopay_match_threshold`
- `biopay_cache_ttl_hours`
- `biopay_stable_frames`

These keys live in `app_config`, not Firebase Remote Config.

## Rollout order

1. Apply the BioPay migration.
2. Deploy the three BioPay Edge Functions.
3. Turn on `feature_biopay_enabled` for internal testing.
4. Plug the ML Kit + TFLite face pipeline into `BiopayScanScreen`.
5. Calibrate threshold and cache behavior with real device testing.

## Immediate follow-up work

- Wire `google_mlkit_face_detection` into the scanner shell.
- Add affine alignment + embedding generation on-device.
- Replace the debug preview path with real match and enroll calls.
- Add device-level QA for Android and iOS dialer behavior.
