# Play Review Access

Updated: March 13, 2026

This document describes the safest review-access path currently prepared in the
Cool repo.

## Current State

- Public legal pages are live on Firebase Hosting:
  - `https://cool.ikanisa.com/privacy`
  - `https://cool.ikanisa.com/terms`
  - `https://cool.ikanisa.com/account-deletion`
- The app is still primarily auth-gated behind WhatsApp OTP.
- `send-otp` now supports an optional review bypass driven by Supabase Edge
  Function secrets:
  - `OTP_TEST_PHONE`
  - `OTP_TEST_CODE`
- Those secrets are now set on the linked project for:
  - test phone `+250788767816`
  - test code `123456`
- `verify-otp` now mints sessions through a deterministic internal email
  identity derived from the WhatsApp number, so hosted phone auth is no longer
  required.
- OTP abuse controls are now enforced server-side:
  - per-phone send limits
  - per-IP send limits
  - per-phone verify-attempt limits
  - per-IP verify-attempt limits
- Auth-user repair and lookup no longer page through `listUsers()`. The backend
  now resolves users through the service-role RPC
  `public.find_auth_user_by_phone_or_email(...)`.
- Reviewers should also be told that Android SMS permission is part of payment
  confirmation verification and may need to be granted during the test flow.

## How the Review Bypass Works

- The bypass is disabled unless both secrets are set.
- If a submitted phone number matches `OTP_TEST_PHONE`, `send-otp` stores the
  configured `OTP_TEST_CODE` and skips WhatsApp delivery.
- `verify-otp` then accepts that code through the normal OTP verification path.
- This keeps the app review flow close to production behavior without requiring
  live WhatsApp delivery for reviewers.

## Recommended Play Console App Access Entry

Use this structure in the Play Console once connected-device validation is
complete on the Supabase project:

1. Login method: WhatsApp OTP
2. Test phone number: the configured `OTP_TEST_PHONE`
3. Test code: the configured `OTP_TEST_CODE`
4. Notes:
   - OTP delivery is bypassed only for the review number.
   - All other numbers continue to use the normal WhatsApp OTP path.

## Review Bypass Setup

The secrets are already set on the active Supabase project:

```bash
supabase secrets set \
  OTP_TEST_PHONE=+250788767816 \
  OTP_TEST_CODE=123456 \
  --project-ref mmpbzcdhfvplxplnfucy
```

`send-otp` and `verify-otp` are already deployed with the review-bypass code
path.

## Auth Strategy

- OTP delivery remains WhatsApp Cloud API only.
- After OTP verification, the backend signs the user into Supabase with a
  deterministic internal email identity derived from the WhatsApp number.
- Hosted email auth must remain enabled, but hosted phone auth is no longer a
  dependency for this flow.
- Abuse controls are logged in `public.otp_rate_events` so review and support
  troubleshooting can distinguish invalid-code churn from delivery failures
  across both phone-scoped and IP-scoped limits.

## Important Constraint

- Do not share the review phone/code with Google Play reviewers until the full
  login flow has been validated on a connected test device.
- When validating the review account repeatedly, use a fresh test window. The
  review flow now rate-limits repeated sends and verify attempts by phone and
  by IP.
