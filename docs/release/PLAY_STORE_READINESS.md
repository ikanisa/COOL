# Play Store Readiness

Status date: 2026-09-01

Use this file as the concise Play readiness index. Store metadata lives under
`fastlane/metadata/android/en-US/`, and structured Play Console evidence lives
in `docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json` while
scripts still consume that packet.

Current boundaries:

- Android Play approval metadata is recorded in
  `docs/release/RELEASE_APPROVALS.json`.
- Android release signing review is recorded there without exposing signing
  keys.
- Store listing, Data safety, app access, testing track, vitals, and reporting
  evidence must be refreshed from Play Console before any new external claim.
- Do not submit Play Console changes without explicit recorded owner approval.

## Play Integrity

The current production implementation contains the complete local Play
Integrity request and verification chain:

- the Android app requests a token through the Play Integrity native API;
- Flutter passes the token only to the authenticated verification boundary;
- `supabase/functions/verify-play-integrity/index.ts` performs server-side
  verification and does not embed or log private key material;
- security contracts keep tokens, service-account JSON, and private keys out
  of repository logs and artifacts.

Live control-plane readback on 2026-09-01 confirms that Collect package
`app.cool.mobile` is linked in Play Console to Google Cloud project `easymoai`
(project number `423260854848`), the Play Integrity API is enabled, and the
core app-licensing, application-integrity, and device-integrity verdicts are
enabled. The dedicated
`collect-play-integrity@easymoai.iam.gserviceaccount.com` identity has no
unrelated project role or user/admin impersonation grant and has exactly one
active Google-managed key. Its JSON credential is configured only as the
`GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` Supabase secret in project
`lhbowpbcpwoiparwnwgt`; OAuth authentication succeeded and an authenticated
request reached the package-specific decode endpoint, which returned the
expected `INVALID_ARGUMENT` response for a deliberately invalid test token.
The downloaded JSON and temporary upload file were overwritten and removed
after that verification.

This closes the missing server credential and linked-project configuration
gate. It does not prove a genuine attestation verdict or production rollout.
Before release, exercise genuine, failed, and replayed verdict paths from a
Play-installed Android build, confirm the authenticated Edge Function result
and capability mint on the physical-device journey, and review verdict
telemetry. Enforcement must be introduced gradually with a fail-safe rollback;
it must not be inferred from a successful local APK build or invalid-token
probe.

The current Developer Reporting API snapshot and live Play Console surfaces
remain separate account-controlled evidence gates.

Keep generated Play evidence in `.cache/google_play_optimization/` or
`output/`; summarize durable decisions here.
