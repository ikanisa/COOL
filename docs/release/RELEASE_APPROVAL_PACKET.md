# Collect Release Approval Packet

Prepared: 2026-06-01  
Decision: **NO-GO**  
Current QA bundle: `.cache/repo_wide_qa_uat/20260601T205424Z`

Purpose: give the product stakeholder, mobile release reviewer, iOS scope
reviewer, SMS UAT reviewer, and release owner one current evidence packet for
the remaining approvals. This packet does not approve the release. It records
what must be reviewed and signed before the release gates can move to GO.

Signed approvals must be recorded in
`docs/release/RELEASE_APPROVALS.json`. The release remains NO-GO until
`make release-approval-evidence-gate-json` passes and the final release gates
consume that approved manifest.

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
| Android device UAT | Pass |
| Supabase release gate | Blocked |
| Supabase evidence bundle | Pass |

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
- Verify: `COLLECT_PRODUCT_SIGNOFF_APPROVED=1 ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev make release-status-json`

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
  - `.cache/repo_wide_qa_uat/20260601T205424Z/android_device_uat.txt`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/uat_evidence_gate.json`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/supabase/summary.json`
- Required signoff fields:
  - tester/reviewer
  - all SMS evidence sanitized
  - persona UAT rows signed or waived
  - signed_at ISO-8601 UTC
- Verify: `COLLECT_ANDROID_SMS_UAT_APPROVED=1 ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev make release-status-json`

### Android Release Signing Review

- Key: `android_release_signing_review`
- Status: pending
- Owner: mobile/release
- Decision needed: approve the current production APK/AAB outputs and Play App
  Signing configuration without exposing signing keys.
- Evidence to review:
  - `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-31.sha256`
  - `build/app/outputs/flutter-apk/app-production-release.apk`
  - `build/app/outputs/bundle/productionRelease/app-production-release.aab`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/mobile_release_gate.json`
- Required signoff fields:
  - `ANDROID_RELEASE_SIGNING_REVIEWED=1`
  - `ANDROID_RELEASE_SIGNING_NOTE`
  - `ANDROID_RELEASE_SIGNING_REVIEWER`
  - `ANDROID_RELEASE_SIGNING_REVIEWED_AT` ISO-8601 UTC
  - `ANDROID_RELEASE_SIGNING_EVIDENCE`
- Verify: `ANDROID_RELEASE_SIGNING_REVIEWED=1 ... ./scripts/flutter_mobile_release_gate.sh --json`

### iOS Release Scope Decision

- Key: `ios_release_scope`
- Status: pending
- Owner: mobile/release
- Decision needed: either approve iOS contributor-only release evidence or
  explicitly scope iOS out of this go-live.
- Evidence to review:
  - `ios/Runner/Info.plist`
  - `ios/Runner.xcodeproj/xcshareddata/xcschemes/production.xcscheme`
  - `ios/Flutter/Release-production.xcconfig`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/mobile_release_gate.json`
- Required signoff fields:
  - `IOS_RELEASE_EVIDENCE_JSON` with approved iOS evidence
  - or `IOS_RELEASE_OUT_OF_SCOPE=1` plus scope note, reviewer, reviewed_at, and evidence reference
- Verify: `IOS_RELEASE_OUT_OF_SCOPE=1 ... ./scripts/flutter_mobile_release_gate.sh --json`

### Release-Owner Go/No-Go Approval

- Key: `release_owner_signoff`
- Status: pending
- Owner: release owner
- Decision needed: approve the current release evidence packet only after all
  product, SMS UAT, signing, iOS scope, security, and worktree checks are
  acceptable.
- Evidence to review:
  - `.cache/repo_wide_qa_uat/20260601T205424Z/summary.json`
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
- Verify: `COLLECT_RELEASE_OWNER_SIGNOFF_APPROVED=1 ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev make release-status-json`

## Required Final Commands

- `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev make release-status-json`
- `make release-approval-evidence-gate-json`
- `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev make supabase-go-live-gate-json`
- `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev ./scripts/repo_wide_qa_uat.sh --json`
