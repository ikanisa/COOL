# Collect Release Approval Packet

Prepared: 2026-06-01  
Decision: **NO-GO**  
Current QA bundle: `.cache/repo_wide_qa_uat/20260601T205424Z`

Purpose: give the product stakeholder, mobile release reviewer, iOS scope
reviewer, SMS UAT reviewer, and release owner one current evidence packet for
the remaining approvals. This packet does not approve the release. It records
what must be reviewed and signed before the release gates can move to GO.

Signed approvals must be recorded in
`docs/release/RELEASE_APPROVALS.json`. Use
`make record-release-approval ARGS='...'` rather than hand-editing JSON when
possible; the recorder validates reviewer metadata, sanitizer assertions,
evidence references, and release-owner prerequisites before writing. The release
remains NO-GO until `make release-approval-evidence-gate-json` passes and the
final release gates consume that approved manifest.

Approval evidence references must resolve to an existing repo artifact or a
valid HTTPS URL. Placeholder paths, missing files, `file:` URLs, and non-HTTPS
URLs fail closed.

Secret handling: do not paste secrets, signing keys, raw SMS bodies,
phone/MoMo numbers, service-role keys, provider tokens, or production customer
data into approval records.

## Current Surface Status

| Surface | Status |
| --- | --- |
| Flutter app | Pass |
| Admin PWA | Pass |
| Admin PWA live deployment | Pass |
| Worktree review | Pass |
| Human UAT evidence | Blocked |
| Human UAT signoff | Blocked |
| Android release artifacts | Pass |
| Release artifact manifest | Pass |
| Flutter mobile release | Blocked |
| Release evidence index | Pass |
| Android device smoke | Pass |
| Supabase readiness | Pass |
| Supabase release gate | Blocked |
| Supabase linked contribution UAT | Pass |

## Pending Approval Records

### Product Definition Approval

- Key: `product_signoff`
- Status: pending
- Owner: product/stakeholder
- Decision needed: approve the SMS-first Groups product definition, including
  Collect ID-only identity, Android-only group creation, and automated MoMo SMS
  allocation.
- Evidence to review:
  - `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md`
  - `docs/design/COLLECT_ASSET_SCREEN_UI_UX_UPDATE_REPORT_2026-05-31.md`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/summary.json`
- Required signoff fields:
  - reviewer
  - `decision=GO`
  - signed_at ISO-8601 UTC
  - evidence reference
- Verify: record `product_signoff` in `docs/release/RELEASE_APPROVALS.json`,
  then run `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev make release-status-json`.
- Recorder:
  `make record-release-approval ARGS="--key product_signoff --reviewer '<name>' --evidence-reference docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md --notes '<review summary>' --sanitized-evidence --no-production-customer-data"`

### Android MoMo SMS UAT Approval

- Key: `android_sms_access_uat`
- Status: pending
- Owner: mobile/release
- Decision needed: approve real Android device UAT for SMS consent, MoMo SMS
  ingestion, parser output, allocation, exception handling, offline retry, and
  ledger update.
- Evidence to review:
  - `docs/ANDROID_SMS_ACCESS.md`
  - `docs/release/UAT_EVIDENCE_MANIFEST.json`
  - `.cache/android_device_uat/20260602T042542Z/summary.json`
  - `.cache/android_device_uat/20260602T042542Z/android_device_uat.txt`
  - `scripts/collect_linked_uat.sh` pass after applying
    `supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql`
  - `.cache/supabase_go_live_evidence/20260602T045205Z/summary.json`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/uat_evidence_gate.json`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/supabase/summary.json`
- Required signoff fields:
  - tester/reviewer
  - all SMS evidence sanitized
  - persona UAT rows signed or waived
  - signed_at ISO-8601 UTC
- Verify: record `android_sms_access_uat` in
  `docs/release/RELEASE_APPROVALS.json`, then run
  `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev make release-status-json`.
- Recorder:
  `make record-release-approval ARGS="--key android_sms_access_uat --reviewer '<name>' --evidence-reference docs/release/UAT_EVIDENCE_MANIFEST.json --notes '<sanitized real-device SMS UAT review summary>' --sanitized-evidence --no-production-customer-data"`

### Android Release Signing Review

- Key: `android_release_signing_review`
- Status: pending
- Owner: mobile/release
- Decision needed: approve the current production APK/AAB outputs and Play App
  Signing configuration without exposing signing keys.
- Evidence to review:
  - `docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md`
  - `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-06-02.sha256`
  - `.cache/mobile_release_gate/20260602T050529Z/summary.json`
  - `.cache/android_install/20260602T050529Z/final_release_summary.json`
  - `build/app/outputs/flutter-apk/app-production-release.apk`
  - `build/app/outputs/bundle/productionRelease/app-production-release.aab`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/mobile_release_gate.json`
- Required signoff fields:
  - reviewer
  - `decision=GO`
  - signed_at ISO-8601 UTC
  - evidence reference
  - `signing_keys_exposed=false`
- Verify: record `android_release_signing_review` in
  `docs/release/RELEASE_APPROVALS.json`, then run
  `./scripts/flutter_mobile_release_gate.sh --json`.
- Recorder:
  `make record-release-approval ARGS="--key android_release_signing_review --reviewer '<name>' --evidence-reference docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md --notes '<APK/AAB and Play App Signing review summary>' --sanitized-evidence --no-production-customer-data --no-signing-keys-exposed"`

### iOS Release Scope Decision

- Key: `ios_release_scope`
- Status: pending
- Owner: mobile/release
- Decision needed: either approve iOS contributor-only release evidence or
  explicitly scope iOS out of this go-live.
- Evidence to review:
  - `docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md`
  - `ios/Runner/Info.plist`
  - `ios/Runner.xcodeproj/xcshareddata/xcschemes/production.xcscheme`
  - `ios/Flutter/Release-production.xcconfig`
  - `.cache/mobile_release_gate/20260602T050529Z/summary.json`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/mobile_release_gate.json`
- Required signoff fields:
  - reviewer
  - `decision=GO` or `decision=OUT_OF_SCOPE`
  - signed_at ISO-8601 UTC
  - evidence reference
  - `status=approved` or `status=out_of_scope`
- Verify: record `ios_release_scope` in
  `docs/release/RELEASE_APPROVALS.json`, then run
  `./scripts/flutter_mobile_release_gate.sh --json`.
- Recorder for approved iOS scope:
  `make record-release-approval ARGS="--key ios_release_scope --reviewer '<name>' --evidence-reference docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md --notes '<iOS contributor-scope review summary>' --sanitized-evidence --no-production-customer-data"`
- Recorder for Android-only scope:
  `make record-release-approval ARGS="--key ios_release_scope --out-of-scope --reviewer '<name>' --evidence-reference docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md --notes '<Android-only go-live scope rationale>' --sanitized-evidence --no-production-customer-data"`

### Release-Owner Go/No-Go Approval

- Key: `release_owner_signoff`
- Status: pending
- Owner: release owner
- Decision needed: approve the current release evidence packet only after all
  product, SMS UAT, signing, iOS scope, security, and worktree checks are
  acceptable.
- Evidence to review:
  - `.cache/repo_wide_qa_uat/20260601T205424Z/summary.json`
  - `.cache/admin_pwa_render_smoke/20260602T081408Z/summary.json`
  - `.cache/mobile_route_render_smoke/20260602T082935Z/summary.json`
  - `.cache/android_device_uat/20260602T042542Z/summary.json`
  - `.cache/supabase_go_live_evidence/20260602T045205Z/summary.json`
  - `docs/release/UAT_GO_LIVE_PACKET_2026-05-24.md`
  - `docs/release/GO_NO_GO_DECISION.md`
  - `docs/release/RELEASE_BLOCKERS.md`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/evidence_index.json`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/worktree_review.json`
- Required signoff fields:
  - release owner name
  - `decision=GO`
  - signed_at ISO-8601 UTC
  - evidence packet reference
- Verify: record `release_owner_signoff` in
  `docs/release/RELEASE_APPROVALS.json`, then run
  `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev make release-status-json`.
- Recorder:
  `make record-release-approval ARGS="--key release_owner_signoff --reviewer '<name>' --evidence-reference docs/release/RELEASE_APPROVAL_PACKET.md --notes '<final release-owner decision summary>' --sanitized-evidence --no-production-customer-data"`
  The recorder refuses this record until product, Android SMS UAT, Android
  signing, and iOS scope approvals are already valid.

## Required Final Commands

- `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev make release-status-json`
- `make release-approval-evidence-gate-json`
- `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev make supabase-go-live-gate-json`
- `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev ./scripts/repo_wide_qa_uat.sh --json`
