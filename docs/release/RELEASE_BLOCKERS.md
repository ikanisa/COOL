# Collect Release Blockers

Status date: 2026-08-05

Decision: **NO-GO** until the current external/device/version/approval gates are
closed. Local build, backend, design, deployment, and artifact evidence must not
be represented as provider, store, physical-device, CI, or release approval.
The governed product remains the SMS-first Groups contract; no legacy contact,
email, or mailbox-ingestion scope is restored by this release refresh.

## Current blockers

| ID | Area | Current evidence | Closure requirement |
|---|---|---|---|
| RB-001 | Spoken accessibility | Structural semantics, controlled TalkBack focus/action evidence, native target measurement, and large-text/high-contrast matrices pass. | Complete common-task spoken TalkBack and VoiceOver traversal with human action/announcement review (RT-020/021). |
| RB-002 | Physical reliability and iOS | Prior physical Android/iPhone evidence is retained; current Simulator routes/Camera and unsigned iOS archive pass. E-081 finds the paired iPhone supported, but it remained locked after a successful staging prebuild, so no runner started. | Provide an unlocked/awake device window and complete accepted physical soak, iPhone lifecycle/Camera Settings/VoiceOver, and distribution provisioning (RT-027/034). |
| RB-003 | Flutter built-in Kotlin | Source compatibility passes on Flutter 3.44.4, but official built-in Kotlin enablement requires Flutter 3.47+. | Upgrade when the governed stable toolchain supports it, enable built-in Kotlin, and rerun Android build/UAT (RT-037). |
| RB-004 | Provider and stores | Production schema/RLS/migrations and linked UAT pass, but strict readiness lacks four APNs secrets. Play/App Store local packs and artifacts pass. No authorized MoMo transaction, Play Reporting/Console, App Store Connect, upload, or processing evidence exists. | Configure APNs securely; execute provider UAT and authenticated store inspection/submission only with account-holder authority (RT-041/042/043). |
| RB-005 | CI availability | Local workflow YAML parses and repository Actions is enabled, but current push run `30954970376` fails before job creation as `startup_failure`; organization-level policy inspection returns 403. | Organization owner restores Actions billing/policy/runner eligibility and reruns the approved revision (I-064). |
| RB-006 | Accountable approval | The machine release status remains `NO-GO`; persona evidence is pending and the release-owner record is not current for the final packet. | Complete human UAT and record product, privacy/security, and release-owner acceptance tied to `1.2.2+10` and current hashes (RT-048). |

## Current green evidence

- `flutter analyze --no-pub`: pass.
- Canonical suite: 455/455 tests, 78.38% line coverage.
- Focused release-document suite: 75/75 tests.
- Product Design evidence: passed for the owner-approved retained/public-pattern
  and explicit no-direct-analogue boundary.
- Native Android and iOS Simulator route matrices: 35/35 each.
- iOS controlled Camera permission phases: denial recovery and host-granted
  relaunch pass; physical/native-dialog/VoiceOver claims remain excluded.
- Public quality: 55/55; live public: 34/34.
- Production Supabase schema: 60/60 migrations, 312/312 schema entries, 58 RLS
  tables, 153 policies, 91 functions, and passing linked SMS/Admin UAT. Strict
  readiness is blocked on APNs configuration and is not claimed as a pass.
- `https://collect.ikanisa.com` and `https://admin.collect.ikanisa.com` are live
  on recorded Cloudflare versions with rollback evidence.
- Current Android APK/AAB and the E-081 production-scheme unsigned iOS archive
  pass local inspection; the 24-file cross-platform manifest has no missing or
  stale file.
- Android and iOS local signing review is current for `1.2.2+10`; this is not
  distribution, upload, processing, or store approval.

Machine-readable release inputs and the exact approval boundary remain in
`docs/release/RELEASE_STATUS.md`, `docs/release/RELEASE_APPROVALS.json`, and
`docs/release/UAT_EVIDENCE_MANIFEST.json`.
