# Collect Release Approval Packet

- Generated at: `2026-06-21T13:12:21Z`
- Decision: `GO`
- Status: `pass`
- QA summary: `.cache/repo_wide_qa_uat/20260601T205424Z/summary.json`
- QA bundle: `.cache/repo_wide_qa_uat/20260601T205424Z`
- Secret handling: No secrets, signing keys, raw SMS bodies, phone/MoMo numbers, service-role keys, provider tokens, or production customer data may be pasted into approval records.

## Surface Status
- `flutter_app`: `pass`
- `admin_pwa`: `pass`
- `admin_pwa_live_deployment`: `pass`
- `worktree_review`: `pass`
- `human_uat_evidence`: `blocked`
- `human_uat_signoff`: `blocked`
- `android_release_artifacts`: `pass`
- `release_artifact_manifest`: `pass`
- `flutter_mobile_release`: `blocked`
- `release_evidence_index`: `pass`
- `android_device_uat`: `pass`
- `supabase_release_gate`: `blocked`
- `supabase_evidence_bundle`: `pass`

## Required approval gates

### Product definition approval

- Key: `product_signoff`
- Status: `approved`
- Required now: `false`
- Owner: product/stakeholder
- Decision needed: Approve the SMS-first Groups product definition, including Collect ID-only identity, Android-only group creation, and automated MoMo SMS allocation.
- Suggested evidence reference: `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md`
- Record: `make record-release-approval ARGS="--key product_signoff --reviewer '<name>' --evidence-reference docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md --notes '<SMS-first Groups product review summary>' --sanitized-evidence --no-production-customer-data"`
- Verify: `Run the record_command for product_signoff, then ADMIN_PWA_LIVE_URL=https://admin.collect.ikanisa.com make release-status-json`
- Evidence to review:
  - `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md`
  - `DESIGN.md`
  - `scripts/collect_product_boundary_scan.sh`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/collect_product_boundary_scan.json`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/summary.json`
- Required signoff fields:
  - reviewer
  - decision=GO
  - signed_at ISO-8601 UTC
  - evidence reference

### Android MoMo SMS UAT approval

- Key: `android_sms_access_uat`
- Status: `approved`
- Required now: `false`
- Owner: mobile/release
- Decision needed: Approve real Android device UAT for SMS consent, MoMo SMS ingestion, parser output, candidate allocation, exception handling and offline retry, plus separate provider-finality reconciliation before any ledger update.
- Suggested evidence reference: `docs/release/UAT_EVIDENCE_MANIFEST.json`
- Record device evidence: `make record-android-sms-uat-evidence ARGS="--tester '<name>' --tested-at '<ISO-8601 UTC timestamp>' --device-label '<Android UAT device label>' --scenarios consent,foreground_sms,background_sms,killed_app_sms,offline_retry,parser_allocation,exception_review,provider_finality,ledger_posting,balance_reconciliation,privacy --evidence-summary '<sanitized scenario summary>' --sanitized-evidence --no-production-customer-data --raw-sms-not-public --no-phone-or-momo --no-transaction-ids --sms-never-used-as-settlement --provider-finality-independently-authenticated --balances-reconciled"`
- Record: `make record-release-approval ARGS="--key android_sms_access_uat --reviewer '<name>' --evidence-reference docs/release/UAT_EVIDENCE_MANIFEST.json --notes '<sanitized real-device SMS UAT review summary>' --sanitized-evidence --no-production-customer-data"`
- Verify: `Run the evidence_record_command for Android SMS UAT, record UAT signoffs, then run the record_command for android_sms_access_uat and ADMIN_PWA_LIVE_URL=https://admin.collect.ikanisa.com make release-status-json`
- Evidence to review:
  - `docs/ANDROID_SMS_ACCESS.md`
  - `docs/release/UAT_EVIDENCE_MANIFEST.json`
  - `.cache/android_device_uat/20260611T082249Z/summary.json`
  - `.cache/android_device_uat/20260611T082249Z/android_device_uat.txt`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/android_device_uat.txt`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/uat_evidence_gate.json`
  - `.cache/supabase_go_live_evidence/20260611T124742Z/summary.json`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/supabase/summary.json`
- Required signoff fields:
  - tester/reviewer
  - all SMS evidence sanitized
  - persona UAT rows signed or waived
  - signed_at ISO-8601 UTC

### Android release signing review

- Key: `android_release_signing_review`
- Status: `approved`
- Required now: `false`
- Owner: mobile/release
- Decision needed: Approve the current production APK/AAB outputs and Play App Signing configuration without exposing signing keys.
- Suggested evidence reference: `docs/release/RELEASE_STATUS.md`
- Record: `make record-release-approval ARGS="--key android_release_signing_review --reviewer '<name>' --evidence-reference docs/release/RELEASE_STATUS.md --notes '<APK/AAB and Play App Signing review summary>' --sanitized-evidence --no-production-customer-data --no-signing-keys-exposed"`
- Verify: `Run the record_command for android_release_signing_review, then ./scripts/flutter_mobile_release_gate.sh --json`
- Evidence to review:
  - `docs/release/RELEASE_STATUS.md`
  - `output/release_artifacts/BUILD_ARTIFACT_CHECKSUMS_2026-06-19.sha256`
  - `.cache/mobile_release_gate/20260602T050529Z/summary.json`
  - `.cache/android_install/20260619T131004Z/final_release_summary.json`
  - `build/app/outputs/flutter-apk/app-production-release.apk`
  - `build/app/outputs/bundle/productionRelease/app-production-release.aab`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/mobile_release_gate.json`
- Required signoff fields:
  - reviewer
  - decision=GO
  - signed_at ISO-8601 UTC
  - evidence reference
  - signing_keys_exposed=false

### iOS release scope decision

- Key: `ios_release_scope`
- Status: `approved`
- Required now: `false`
- Owner: mobile/release
- Decision needed: Either approve iOS contributor-only release evidence or explicitly scope iOS out of this go-live.
- Suggested evidence reference: `docs/release/RELEASE_STATUS.md`
- Record: `make record-release-approval ARGS="--key ios_release_scope --reviewer '<name>' --evidence-reference docs/release/RELEASE_STATUS.md --notes '<iOS contributor-scope review summary>' --sanitized-evidence --no-production-customer-data"`
- Record Android-only scope: `make record-release-approval ARGS="--key ios_release_scope --out-of-scope --reviewer '<name>' --evidence-reference docs/release/RELEASE_STATUS.md --notes '<Android-only go-live scope rationale>' --sanitized-evidence --no-production-customer-data"`
- Verify: `Run record_command or record_out_of_scope_command for ios_release_scope, then ./scripts/flutter_mobile_release_gate.sh --json`
- Evidence to review:
  - `docs/release/RELEASE_STATUS.md`
  - `ios/Runner/Info.plist`
  - `ios/Runner.xcodeproj/xcshareddata/xcschemes/production.xcscheme`
  - `ios/Flutter/Release-production.xcconfig`
  - `.cache/mobile_release_gate/20260602T050529Z/summary.json`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/mobile_release_gate.json`
- Required signoff fields:
  - reviewer
  - decision=GO or OUT_OF_SCOPE
  - signed_at ISO-8601 UTC
  - evidence reference
  - status=approved or status=out_of_scope

### Release-owner go/no-go approval

- Key: `release_owner_signoff`
- Status: `approved`
- Required now: `false`
- Owner: release owner
- Decision needed: Approve the current release evidence packet only after all product, SMS UAT, signing, iOS scope, security, and worktree checks are acceptable.
- Suggested evidence reference: `docs/release/RELEASE_APPROVAL_PACKET.md`
- Record: `make record-release-approval ARGS="--key release_owner_signoff --reviewer '<name>' --evidence-reference docs/release/RELEASE_APPROVAL_PACKET.md --notes '<final release-owner decision summary>' --sanitized-evidence --no-production-customer-data"`
- Verify: `Run the record_command for release_owner_signoff, then ADMIN_PWA_LIVE_URL=https://admin.collect.ikanisa.com make release-status-json`
- Evidence to review:
  - `.cache/repo_wide_qa_uat/20260601T205424Z/summary.json`
  - `.cache/admin_pwa_render_smoke/20260602T081408Z/summary.json`
  - `.cache/mobile_route_render_smoke/20260602T210133Z/summary.json`
  - `.cache/android_device_uat/20260611T082249Z/summary.json`
  - `.cache/supabase_go_live_evidence/20260611T124742Z/summary.json`
  - `docs/release/RELEASE_APPROVAL_PACKET.md`
  - `docs/release/GO_NO_GO_DECISION.md`
  - `docs/release/RELEASE_BLOCKERS.md`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/evidence_index.json`
  - `.cache/repo_wide_qa_uat/20260601T205424Z/worktree_review.json`
- Required signoff fields:
  - release owner name
  - decision=GO
  - signed_at ISO-8601 UTC
  - evidence packet reference

## Required Final Commands
- `ADMIN_PWA_LIVE_URL=https://admin.collect.ikanisa.com make release-status-json`
- `make release-approval-evidence-gate-json`
- `ADMIN_PWA_LIVE_URL=https://admin.collect.ikanisa.com make supabase-go-live-gate-json`
- `ADMIN_PWA_LIVE_URL=https://admin.collect.ikanisa.com ./scripts/repo_wide_qa_uat.sh --json`
