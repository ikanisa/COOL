# Play Store Readiness

Status date: 2026-07-24

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

This proves implementation presence, not an operational production rollout.
Before release, the owner must verify the Play Console/Google Cloud project
link, deploy and configure the verification function through the approved
Supabase path, confirm service-account access without copying credentials into
the repository, exercise genuine/failed/replayed verdict paths on a
Play-installed build, and review verdict telemetry. Enforcement must be
introduced gradually with a fail-safe rollback; it must not be inferred from a
successful local APK build.

The current Developer Reporting API snapshot and live Play Console surfaces
remain separate account-controlled evidence gates.

Keep generated Play evidence in `.cache/google_play_optimization/` or
`output/`; summarize durable decisions here.
