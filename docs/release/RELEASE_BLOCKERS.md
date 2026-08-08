# Collect Release Blockers

Status date: 2026-08-08

Owner decision: **GO** for `1.2.2+12`. The entries below are execution risks and
third-party state, not missing owner authorization. Local build, backend,
design, deployment, and artifact evidence must still not be represented as
provider, store, physical-device, CI, or store-processing evidence.
The governed product remains the SMS-first Groups contract; no legacy contact,
email, or mailbox-ingestion scope is restored by this release refresh.

## Current blockers

| ID | Area | Current evidence | Closure requirement |
|---|---|---|---|
| RB-001 | Spoken accessibility | Structural semantics, controlled TalkBack focus/action evidence, native target measurement, and large-text/high-contrast matrices pass. The governed native accessibility gate explicitly removes spoken traversal from the release gate and assigns final responsibility to Codex. | Accepted for this release without a claim that human spoken traversal occurred. |
| RB-002 | Physical reliability and iOS | Prior accepted physical Android/iPhone evidence is retained. The final unlocked iPhone staging build installed, launched, attached, and passed 3/35 routes before CoreDevice invalidated the wireless connection; the incomplete run is rejected. A production archive and Apple Distribution IPA pass. | Owner accepted the remaining physical-scenario risk; retain the failed run as rejected evidence and do not describe it as a pass. |
| RB-003 | Flutter built-in Kotlin | Source compatibility passes on Flutter 3.44.4. Flutter 3.47 is not an available governed stable release, so the requested enablement cannot be a current release requirement. | Non-blocking upstream maintenance item; rerun when a governed Flutter release actually exposes the required feature. |
| RB-004 | Provider and stores | Production schema/RLS/migrations and linked UAT pass. Play Console is authenticated; internal version 12 is available to testers and supersedes the legacy permission-heavy build. The production 100% rollout retains the complete device catalog and is in Google review with accurate Advertising ID and SMS/Call Log declarations. Strict backend readiness still lacks APNs/FCM provider secrets. | Obtain Google restricted-SMS/release approval and configure real push-provider values when obtained. No placeholders. |
| RB-005 | CI availability | Local workflow YAML parses and repository Actions is enabled, but current push run `30954970376` fails before job creation as `startup_failure`; organization-level policy inspection returns 403. | Organization owner restores Actions billing/policy/runner eligibility and reruns the approved revision (I-064). |
| RB-006 | Accountable approval | The release, UAT-evidence, approval-evidence, and native accessibility gates pass with decision `GO`; all ten personas are explicitly owner-waived rather than misreported as tested. | Closed for `1.2.2+12`; retain the owner-waiver limitation in release reporting. |

## Current green evidence

- E-082 is the current execution checkpoint and retains E-081's fail-closed
  external/device observations.
- `flutter analyze --no-pub`: pass.
- Canonical suite: 456/456 tests for the E-083 final source. The latest retained
  coverage measurement remains the separately recorded E-080 snapshot.
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
- Current Android APK/AAB, the production-scheme signed iOS archive, and the
  Apple Distribution IPA pass local inspection. The IPA export confirms
  production provisioning; App Store Connect separately reports build `10`
  already present. This is not a claim of review approval or public release.

Machine-readable release inputs and the exact approval boundary remain in
`docs/release/RELEASE_STATUS.md`, `docs/release/RELEASE_APPROVALS.json`, and
`docs/release/UAT_EVIDENCE_MANIFEST.json`.
