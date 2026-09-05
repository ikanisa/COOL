# Collect monitor session renewal

Date: 4 September 2026, Kigali (3 September UTC).

Status: **LOCAL RENEWAL QA PASS; FRESH OTP PROVISIONING AND LIVE ROTATION OPEN**.
Queue access is currently blocked by the expired earlier access-only session.
No receipt was sent and no queue, ledger, approval, feature flag or legacy
service was changed by this continuation.

## Current evidence

- MCP health returned `OPERATOR_SESSION_REAUTHENTICATION_REQUIRED` at
  approximately 22:42 UTC. Earlier empty-queue results are historical, not a
  current queue readback.
- The connected Pixel still has Collect 1.2.4+23 and RECEIVE_SMS granted.
  READ_SMS and SEND_SMS remain absent. Receiving-line identity and actual receipt
  capture remain unproven.
- The existing minute monitor remains read-only/no-send. Its two-tool allowlist
  is unchanged; the configured timeout is now 45 seconds to accommodate bounded
  renewal plus the requested queue read.

## Implemented

The earlier client deliberately discarded refresh credentials and therefore
stopped at access expiry. The new opt-in host setting is
`COLLECT_OPERATOR_SESSION_RENEWAL=keychain`. A normal fresh approved-Admin OTP
login can now provision a versioned renewable session in the same private,
device-local macOS Keychain item. No existing refresh token was recovered from
browser storage or another app, and no token is written to Git/config/output.

- Refresh only near expiry, or through the explicit normal `renew` verification
  command; no altered token/clock is used for live testing.
- Keep the same project, user and session. Reject privileged keys and malformed
  or stale replacement tokens. Local JWT decoding is not authorization.
- Serialize Keychain reads, renewal and login writes using an atomic private
  directory lock. An orphan lock fails closed; it is never stolen by age.
- Persist a non-secret pending marker before consuming the refresh token.
  Network failure, revoked session, process crash or failed save leaves normal
  reauthentication required rather than replaying a potentially consumed token.
- Recheck current Admin permission through the bounded health endpoint before
  saving the replacement. Every subsequent queue call retains server-side
  authentication and current Admin permission checks.
- Keep offline preflight network-free. Keep queue commands free of automatic
  retry and leave all sending tools excluded from this host profile.

The implementation follows the provider's
[session and refresh-token semantics](https://supabase.com/docs/guides/auth/sessions)
and [Auth endpoint contract](https://github.com/supabase/auth/blob/master/openapi.yaml).
Current changelog review found no relevant hosted refresh-endpoint breaking
change. Provider revocation/session lifetime policies remain unchanged; this
work does not claim immediate invalidation of every already-issued JWT.

## Verification and remaining acceptance

TypeScript check and 30 MCP tests pass, including token/session/project binding,
opt-in and legacy compatibility, actual cross-process lock exclusion, interrupted
refresh and failed persistence, denied Admin access, sanitized errors, no retry,
offline no-network behavior and actual stdio tool inventory.

Still required: fresh OTP provisioning; actual production rotation and
independent MCP health/list readback; a later scheduled refresh observed through
normal expiry. Only then can persistent monitoring be called operationally
verified. A successful local test is not a successful production login.

The normal OTP request returned `OTP_REQUESTED` for the existing approved
number ending 7816 (`creates_user=false`). This proves request acceptance, not
WhatsApp delivery or login. The code is awaited; no OTP was retained. A fresh
offline preflight still correctly reports reauthentication required with zero
queue mutations, zero provider sends and no credentials printed. The existing
automation was updated through the Codex tool, not duplicated; its return
confirms ACTIVE status and its prompt preserves the no-send boundary.

Independent release check: `make mobile-design-gate` currently **BLOCKED** on
mobile approval, stale/absent acceptance hashes/version, open findings and
missing/mismatched APK/AAB build evidence. No mobile design file, baseline or
acceptance was changed to hide this result.

The physical gates remain: confirm which handset receives merchant 41258
M-Money receipts, obtain a real feature-phone member's complete identity, verify
fresh capture/allocation/balances, hand over legacy sender ownership, then obtain
the exact action-time send confirmation and inspect actual handset receipt.
No fake member, test payment, legacy-history replay or delivery claim was made.
