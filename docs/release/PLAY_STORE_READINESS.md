# Play Store Readiness

Status date: 2026-06-27

Use this file as the concise Play readiness index. Store metadata lives under
`fastlane/metadata/android/en-US/`, and structured Play Console evidence lives
in `docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET_2026-06-21.json` while
scripts still consume that packet.

Current boundaries:

- Android Play approval metadata is recorded in
  `docs/release/RELEASE_APPROVALS.json`.
- Android release signing review is recorded there without exposing signing
  keys.
- Store listing, Data safety, app access, testing track, vitals, and reporting
  evidence must be refreshed from Play Console before any new external claim.
- Do not submit Play Console changes without explicit recorded owner approval.

Keep generated Play evidence in `.cache/google_play_optimization/` or
`output/`; summarize durable decisions here.
