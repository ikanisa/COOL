# COOL Documentation Consolidation Plan - 2026-06-27

Repo: `/Volumes/PRO-G40/COOL`
Reviewer: Codex
Scope: tracked repo documentation, release/design evidence, markdown/json docs, Fastlane metadata, web/iOS manifest-style files, and generated doc-like local output.

## Executive Decision

The repo has too many docs because it has been using `docs/design` and `docs/release` as both:

1. live source-of-truth documentation; and
2. dated audit evidence, implementation goalbooks, release packets, screenshot manifests, and historical proof.

Those two uses should be separated. Keep a small set of active source-of-truth docs in the repo. Move dated reports, goalbooks, screenshots, and superseded evidence into an archive folder or external evidence pack after owner approval. Delete only generated cache output and docs proven unreferenced and fully superseded.

No external filing, release submission, legal notice, app-store submission, or regulatory report should be made from this cleanup without explicit human approval.

## Inventory Summary

Current checkout:

| Area | Count / size | Finding |
| --- | ---: | --- |
| All doc-like files in checkout, including generated `.cache` and `.dart_tool` | 818 | Misleading headline number; most are local/generated evidence or tool output. |
| Tracked doc-like files excluding generated folders | 111 | Includes markdown, JSON manifests, Fastlane metadata text, web/iOS manifests, and root docs. |
| Tracked `docs/design` + `docs/release` markdown/json | 70 files / 11,290 lines | Main source of documentation bloat. |
| Product design audit folder | 50 files | 1 README, 1 manifest, 48 tracked screenshots; valuable evidence but not day-to-day docs. |
| Existing code/test/script references to doc paths | concentrated | `test/release_docs_test.dart`, release scripts, Supabase tests, and design gates lock several paths. |

The previous cleanup audit already identified this pattern: `docs/design` and `docs/release` are useful for audit history, but the active repo should keep only current product, architecture, operations, and release-decision docs in the main docs tree.

## Current Relevance Classification

### Keep As Active Source Of Truth

These are live and should remain in the main repo, with content refreshed during consolidation:

| File | Role | Required action |
| --- | --- | --- |
| `README.md` | Product and route overview | Update product scope if category/diaspora pivot is active. |
| `DESIGN.md` | Primary enforceable design contract | Keep as the one design source of truth. |
| `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md` | Product definition and product rules | Rename or update status from draft if approved; reconcile category/diaspora wording. |
| `docs/ARCHITECTURE.md` | Architecture overview | Keep. |
| `docs/DATABASE.md` | Database overview | Keep. |
| `docs/ENVIRONMENT.md` | SDK, build defines, environment | Correct Flutter/Dart versions to `.fvmrc` and local SDK. |
| `docs/SUPABASE_OPERATIONS_RUNBOOK.md` | Operations runbook | Keep; referenced by tests. |
| `docs/SUPABASE_FUNCTIONS.md` | Edge Function map | Keep. |
| `docs/ANDROID_SMS_ACCESS.md` | SMS access/policy reference | Keep; referenced by approval gates. |
| `docs/PRIVACY_AND_COMPLIANCE_NOTES.md` | Compliance caveats | Merge into a fuller privacy/release compliance doc or keep as short checklist. |
| `docs/admin/ADMIN_SECURITY_MODEL.md` | Admin security model | Keep. |
| `docs/admin/ADMIN_ARCHITECTURE_PLAN.md` | Admin architecture | Keep, or merge into `docs/ARCHITECTURE.md` if no unique detail remains. |
| `fastlane/README.md` | Fastlane operational docs | Keep with Fastlane folder. |
| `fastlane/app_privacy_details.json` | App privacy automation input | Keep; not a narrative doc. |
| `fastlane/metadata/**` | Store listing metadata | Keep; not repo documentation. |
| `web/manifest.json`, `web/.well-known/assetlinks.json`, `web/robots.txt` | Runtime/public web metadata | Keep; not cleanup candidates. |
| `ios/Runner/Assets.xcassets/**/Contents.json` | Platform asset metadata | Keep; not documentation. |

### Keep But Consolidate

These contain current value but should collapse into fewer files:

| Current files | Target |
| --- | --- |
| `docs/design/DESIGN_SYSTEM.md`, `docs/archive/2026-06/design/COMPONENT_CATALOG.md`, `docs/archive/2026-06/design/TYPOGRAPHY.md`, `docs/archive/2026-06/design/ACCESSIBILITY_CHECKLIST.md`, `docs/archive/2026-06/design/UI_UX_REFERENCE_RESEARCH.md` | Merge into `DESIGN.md` plus one short `docs/design/README.md` pointer. |
| `docs/release/GO_NO_GO_DECISION.md`, `docs/release/RELEASE_BLOCKERS.md`, `docs/release/PRODUCTION_READINESS_CHECKLIST.md`, `docs/release/QA_TEST_REPORT.md`, `docs/release/UAT_TEST_PLAN.md`, `docs/release/UAT_EXECUTION_REPORT.md`, `docs/release/GO_LIVE_AUDIT_REPORT.md`, `docs/release/UAT_GO_LIVE_PACKET_2026-05-24.md` | Merge into `docs/release/RELEASE_STATUS.md`. Keep machine-readable manifests separately. |
| `docs/release/RELEASE_APPROVAL_PACKET.md`, `docs/release/RELEASE_APPROVALS.json`, `docs/release/RELEASE_APPROVALS.example.json` | Keep as release-governance package, but generate the packet from JSON/status where possible. |
| `docs/release/UAT_EVIDENCE_MANIFEST.json`, `docs/release/UAT_EVIDENCE_MANIFEST.example.json`, `docs/release/UAT_SIGNOFF_CHECKLIST_2026-05-24.md` | Keep JSON as canonical. Fold checklist instructions into `RELEASE_STATUS.md` or `RELEASE_APPROVAL_PACKET.md`. |
| `docs/archive/2026-06/release/IOS_APP_STORE_READINESS_2026-06-24.md`, `docs/archive/2026-06/release/IOS_APP_STORE_COMPLETION_ALTERNATIVES_2026-06-25.md`, `SDK_UPGRADE_REPORT.md`, `docs/tech/FLUTTER_DART_3_44_3_12_RESEARCH.md` | Merge current facts into `docs/ENVIRONMENT.md` and a short `docs/release/APP_STORE_READINESS.md`; archive dated research. |
| `docs/release/GOOGLE_PLAY_OPERATIONAL_READINESS_2026-06-21.md`, `docs/release/GOOGLE_PLAY_OPTIMIZATION_GOAL_2026-06-21.md`, `docs/release/GOOGLE_PLAY_OPTIMIZATION_SURFACE_MATRIX_2026-06-21.md`, `docs/release/GOOGLE_PLAY_PRODUCTION_SUBMISSION_2026-06-21.md`, `docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET_2026-06-21.json` | Merge narrative into `docs/release/PLAY_STORE_READINESS.md`; keep JSON packet only if scripts still consume it. |
| Public website signoff/evidence docs dated 2026-06-22 | Merge active items into `docs/release/PUBLIC_WEBSITE_READINESS.md`; archive dated evidence. |

### Archive After Consolidation

These appear historical, dated, or implementation-pass evidence. Archive after extracting any current facts and updating references:

- `docs/archive/2026-05/design/COLLECT_ASSET_SCREEN_UI_UX_UPDATE_REPORT_2026-05-31.md`
- `docs/archive/2026-05/design/COLLECT_UI_IMPLEMENTATION_GOALBOOK_2026-05-31.md`
- `docs/archive/2026-06/design/COLLECT_MOBILE_100_PERCENT_COMPLETION_GOALBOOK_2026-06-07.md`
- `docs/archive/2026-06/design/COLOR_COMPLIANCE_AUDIT_2026-06-08.md`
- `docs/archive/2026-06/design/SECONDARY_COLOR_PALETTE_ANALYSIS_2026-06-09.md`
- `docs/archive/2026-06/design/REVOLUT_REFERENCE_GAP_ANALYSIS_2026-06-08.md`
- `docs/archive/2026-06/design/REVOLUT_REFERENCE_100_PERCENT_PARITY_GOAL_2026-06-15.md`
- `docs/archive/2026-06/design/REVOLUT_REFERENCE_MANUAL_PARITY_AUDIT_2026-06-15.md`
- `docs/archive/2026-06/design/REVOLUT_REFERENCE_PARITY_IMPLEMENTATION_REPORT_2026-06-15.md`
- `docs/design/REVOLUT_PARITY_EVIDENCE_2026-06-18.md`
- `docs/design/REVOLUT_PARITY_SIGNOFF_CHECKLIST_2026-06-18.md`
- `docs/archive/2026-06/design/REVOLUT_SECONDARY_UI_UPGRADE_PROGRESS_2026-06-21.md`
- `docs/archive/2026-06/design/SCREEN_REDESIGN_PLAN.md`
- `docs/archive/2026-06/design/BEFORE_AFTER_AUDIT.md`
- `docs/archive/2026-06/design/GOOGLE_AI_STUDIO_STITCH_MOBILE_REDESIGN_BRIEF.md`
- `docs/archive/2026-06/design/COLLECT_PUBLIC_WEBSITE_AUDIT_TRACKER_2026-06-22.md`
- `docs/archive/2026-06/design/COLLECT_PUBLIC_WEBSITE_FULL_IMPLEMENTATION_GOAL_2026-06-22.md`
- `docs/archive/2026-06/design/COLLECT_PUBLIC_WEBSITE_WORLD_CLASS_REMEDIATION_PLAN_2026-06-22.md`
- `docs/design/REVOLUT_BORROWED_ALIGNMENT_PLAN_2026-06-27.md` once its actionable requirements are merged into `DESIGN.md`
- `docs/archive/2026-06/release/AGGRESSIVE_REPO_CLEANUP_OPTIMIZATION_GOAL_2026-06-23.md`
- `docs/archive/2026-06/release/FULL_REPO_AUDIT_IMPLEMENTATION_2026-06-15.md`
- `docs/archive/2026-06/release/REPO_RESTRUCTURE_CLEANUP_AUDIT_2026-06-22.md`
- `docs/archive/2026-06/release/FULLSTACK_QA_DEEP_CLEANUP_GOAL_2026-06-24.md`
- `docs/archive/2026-06/release/FULLSTACK_QA_DEEP_CLEANUP_REPORT_2026-06-24.md`
- `docs/archive/2026-06/release/COLLECT_FLUTTER_PRODUCT_IOS_ARCHITECTURE_GOAL_2026-06-26.md`
- `docs/archive/2026-06/release/COLLECT_PREMIUM_MOBILE_FRONTEND_IMPLEMENTATION_GOAL_2026-06-26.md`
- `docs/release/COLLECT_PREMIUM_MOBILE_FRONTEND_COMPLETION_REPORT_2026-06-27.md`
- `docs/archive/2026-06/release/COLLECT_MOBILE_ANNOTATED_FINDINGS_FIX_GOAL_2026-06-26.md`
- `docs/release/product_design_mobile_audit_2026-06-26/`
- `docs/archive/2026-06/release/PIXEL4A_DEVICE_SCREENSHOT_QA_2026-06-23.md`
- `docs/archive/2026-06/release/BRAND_DEVICE_QA_2026-06-07.md`
- `docs/archive/2026-06/release/PERMISSION_READINESS_REPORT_2026-06-09.md`
- `docs/archive/2026-06/release/RELEASE_GATE_EVIDENCE_2026-06-07.md`
- `docs/archive/2026-06/release/ANDROID_SIGNING_CERTIFICATE_SEARCH_2026-06-23.md`
- `docs/release/ANDROID_IOS_RELEASE_REVIEW_EVIDENCE_2026-06-02.md` only after approval gate references are moved.

Preferred archive target:

```text
docs/archive/YYYY-MM/
```

If repository size matters, move bulky screenshot evidence outside git into:

```text
output/evidence-packs/
```

and keep only a small manifest in `docs/release`.

### Delete Candidates

Delete only after consolidation, reference updates, and validation:

- Generated local output under `.cache/`, `.dart_tool/`, `build/`, `output/` when not intentionally retained as evidence.
- Superseded dated reports whose useful facts have been merged and that have zero live code/test/script references.
- Duplicate pointer docs replaced by one canonical doc and one README index.

Do not delete:

- Supabase migrations.
- release approval/signoff JSON before gates are updated.
- app-store metadata.
- platform manifest JSON.
- docs referenced by release/security tests until tests and scripts are migrated.

## Contradictions To Resolve

### 1. Design Direction: Authorized Revolut Alignment vs Collect-Owned Separation

Current active `DESIGN.md` and `docs/design/DESIGN_SYSTEM.md` say approved Revolut partnership assets, fonts, marks, icons, screenshots, and component patterns are valid implementation inputs.

Several older docs still use older language around Collect-owned assets, "Revolut-style" parity, benchmark quality, or not copying Revolut material. Examples:

- `docs/archive/2026-06/design/COLLECT_PUBLIC_WEBSITE_FULL_IMPLEMENTATION_GOAL_2026-06-22.md`
- `docs/archive/2026-06/design/COLLECT_PUBLIC_WEBSITE_WORLD_CLASS_REMEDIATION_PLAN_2026-06-22.md`
- `docs/archive/2026-06/design/SECONDARY_COLOR_PALETTE_ANALYSIS_2026-06-09.md`
- `docs/archive/2026-06/design/REVOLUT_REFERENCE_PARITY_IMPLEMENTATION_REPORT_2026-06-15.md`
- `docs/archive/2026-06/design/REVOLUT_REFERENCE_MANUAL_PARITY_AUDIT_2026-06-15.md`
- `docs/design/REVOLUT_PARITY_EVIDENCE_2026-06-18.md`

Decision: `DESIGN.md` wins. Merge the current partnership contract into `DESIGN.md`; mark older design reports as archived/historical.

### 2. Release Status: GO Packet vs NO-GO Reports

`docs/release/RELEASE_APPROVAL_PACKET.md` says:

- Decision: `GO`
- Status: `pass`

But the same packet lists blocked surfaces:

- `human_uat_evidence`
- `human_uat_signoff`
- `flutter_mobile_release`
- `supabase_release_gate`

Other files still say NO-GO or pending, including:

- `docs/release/GO_NO_GO_DECISION.md`
- `docs/release/RELEASE_BLOCKERS.md`
- `docs/release/PRODUCTION_READINESS_CHECKLIST.md`
- `docs/release/UAT_EVIDENCE_MANIFEST.json`
- `docs/release/QA_TEST_REPORT.md`

Decision: generated/current gates win over prose. Create `docs/release/RELEASE_STATUS.md` as the readable current status and make it clearly state whether the current validated state is GO or NO-GO. Older reports remain archived evidence.

### 3. Product Scope: No Categories vs Approved Category/Diaspora Pivot

`README.md` and `docs/release/PRODUCTION_READINESS_CHECKLIST.md` still say no category, target, cover, public directory, or campaign workflow.

`docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md` now says a 2026-06-21 owner update approved reintroducing first-class collection categories and a Stripe-powered diaspora rail, while still carrying older "no category" lines later in the same file.

`docs/release/COLLECT_MARKET_EXPANSION_STRIPE_DIASPORA_GOAL_2026-06-21.md` says it supersedes the simplified-product rule that removed categories, targets, covers, and campaign-like context.

Decision needed: either categories/diaspora are now active product scope, or they remain future approved-but-not-implemented scope. Update README, product definition, architecture, release checklist, and boundary tests to say one thing.

Recommended wording:

```text
Collect supports category-specific collection context only where explicitly implemented and approval-gated. The default Rwanda MoMo/SMS workflow remains non-custodial, Collect-ID-only, and does not expose public-directory or contributor-reported transaction-ID flows.
```

### 4. SDK Version Drift

`.fvmrc` currently pins:

```json
{ "flutter": "3.44.3" }
```

Local SDK reports:

```text
Flutter 3.44.3
Dart 3.12.2
```

But these docs still say Flutter `3.44.0` / Dart `3.12.0`:

- `docs/ENVIRONMENT.md`
- `SDK_UPGRADE_REPORT.md`
- `docs/tech/FLUTTER_DART_3_44_3_12_RESEARCH.md`

Decision: update `docs/ENVIRONMENT.md` as canonical. Archive dated upgrade/research docs after extracting any useful notes.

## Target Documentation Structure

After consolidation:

```text
README.md
DESIGN.md
docs/
  README.md
  PRODUCT.md
  ARCHITECTURE.md
  DATABASE.md
  ENVIRONMENT.md
  ANDROID_SMS_ACCESS.md
  PRIVACY_COMPLIANCE.md
  SUPABASE_FUNCTIONS.md
  SUPABASE_OPERATIONS_RUNBOOK.md
  admin/
    ADMIN_SECURITY_MODEL.md
    ADMIN_ARCHITECTURE.md
  design/
    README.md
  release/
    RELEASE_STATUS.md
    RELEASE_APPROVAL_PACKET.md
    RELEASE_APPROVALS.json
    RELEASE_APPROVALS.example.json
    UAT_EVIDENCE_MANIFEST.json
    UAT_EVIDENCE_MANIFEST.example.json
    APP_STORE_READINESS.md
    PLAY_STORE_READINESS.md
    PUBLIC_WEBSITE_READINESS.md
    LIVE_DEPLOYMENTS.json
  archive/
    2026-05/
    2026-06/
```

The `docs/design/README.md` should point to `DESIGN.md` and explain that dated design audits are archived. It should not become a second design system.

The `docs/release/RELEASE_STATUS.md` should be the readable release source of truth. JSON manifests remain canonical for machine gates.

## Merge Plan

### Phase 1: Create The Index And Canonical Targets

1. Add `docs/README.md` with a short map of canonical docs.
2. Add or update `docs/PRODUCT.md` by merging current product rules from `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md`.
3. Update `README.md` to point to `docs/PRODUCT.md`, `DESIGN.md`, and `docs/release/RELEASE_STATUS.md`.
4. Update `docs/ENVIRONMENT.md` to Flutter `3.44.3` and Dart `3.12.2`.
5. Add `docs/release/RELEASE_STATUS.md` generated from current release gates/manifests, not copied from older prose.

Validation:

```sh
rg -n "3\\.44\\.0|3\\.12\\.0|Decision: `GO`|Decision: GO|NO-GO|category|Revolut-style|Collect-owned" README.md DESIGN.md docs
```

Review every hit and mark as current, historical, or fixed.

### Phase 2: Migrate Test/Script Path Coupling

Update path references in:

- `test/release_docs_test.dart`
- `test/supabase_contract_test.dart`
- `scripts/release_approval_evidence_gate.sh`
- `scripts/revolut_parity_signoff_gate.sh`
- `scripts/admin_pwa_live_gate.sh`
- `scripts/google_play_console_audit_packet.sh`
- `scripts/google_play_metadata_export.sh`
- any release/go-live scripts found by `rg "docs/" scripts test`

Where scripts need stable historical evidence references, either:

1. allow both old and new paths during migration; or
2. update the manifest JSON to point to new canonical files.

Validation:

```sh
rg -n "docs/design/|docs/release/" scripts test lib Makefile
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/supabase_contract_test.dart test/security_hygiene_test.dart
```

### Phase 3: Consolidate Design Docs

1. Keep `DESIGN.md` as canonical.
2. Move still-current content from `docs/design/DESIGN_SYSTEM.md`, `COMPONENT_CATALOG.md`, `TYPOGRAPHY.md`, `ACCESSIBILITY_CHECKLIST.md`, and `UI_UX_REFERENCE_RESEARCH.md` into `DESIGN.md`.
3. Replace `docs/design/DESIGN_SYSTEM.md` with a short pointer only if scripts/tests still require the path.
4. Archive dated design audits and goalbooks.
5. Update `scripts/collect_mobile_design_compliance_audit.sh` to enforce current `DESIGN.md` language and remove old Collect-owned separation checks.

Validation:

```sh
scripts/collect_mobile_design_compliance_audit.sh --json
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart test/app_shell_test.dart
```

### Phase 4: Consolidate Release Docs

1. Create `docs/release/RELEASE_STATUS.md`.
2. Merge active blocker/readiness prose from:
   - `GO_NO_GO_DECISION.md`
   - `RELEASE_BLOCKERS.md`
   - `PRODUCTION_READINESS_CHECKLIST.md`
   - `QA_TEST_REPORT.md`
   - `UAT_TEST_PLAN.md`
   - `UAT_EXECUTION_REPORT.md`
   - `GO_LIVE_AUDIT_REPORT.md`
3. Keep approval and UAT JSON files.
4. Archive dated release reports and goalbooks.
5. Keep app store, Play Store, and public website readiness as three concise current files.

Validation:

```sh
make release-status-json
make release-approval-evidence-gate-json
make uat-evidence-gate-json
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart
```

### Phase 5: Archive Bulky Evidence

Move dated screenshot and audit evidence after references are updated:

```text
docs/release/product_design_mobile_audit_2026-06-26/
```

Preferred approach:

1. preserve the screenshot manifest and README in an archive/evidence pack;
2. move 48 screenshots out of active docs unless a release gate still requires them;
3. keep a small manifest that records where the evidence pack lives.

Validation:

```sh
rg -n "product_design_mobile_audit_2026-06-26|screenshot_manifest" .
```

### Phase 6: Delete Superseded Files

Only after Phases 1-5 pass:

1. delete pointer docs that have no live references;
2. delete superseded dated reports whose useful content was merged;
3. run `git diff --stat` and ensure the deletion list is intentional.

Validation:

```sh
git status --short
git diff --check
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart test/supabase_contract_test.dart test/security_hygiene_test.dart
./scripts/repo_wide_qa_uat.sh --json
```

## Practical Delete/Archive Order

Use this order to avoid breaking gates:

1. Archive zero-reference dated design reports.
2. Archive zero-reference dated release goalbooks and implementation reports.
3. Consolidate public website evidence docs into `PUBLIC_WEBSITE_READINESS.md`.
4. Consolidate Play/iOS docs into `PLAY_STORE_READINESS.md` and `APP_STORE_READINESS.md`.
5. Update tests/scripts for release-governance paths.
6. Replace duplicate design docs with pointers.
7. Move bulky screenshots last.

## Expected End State

The repo should end with:

- one product source of truth;
- one design source of truth;
- one readable release status file;
- machine-readable approval/UAT manifests kept where gates need them;
- store metadata kept with Fastlane;
- dated audit reports moved out of the active docs path;
- no contradictory GO/NO-GO claims in active docs;
- no contradictory category/diaspora scope claims in active docs;
- SDK docs matching `.fvmrc` and the local pinned SDK;
- tests and release gates passing after path updates.

## Immediate Next Actions

1. Decide whether the category/diaspora pivot is active scope or approved future scope.
2. Update `docs/ENVIRONMENT.md` to Flutter `3.44.3` / Dart `3.12.2`.
3. Create `docs/README.md`, `docs/PRODUCT.md`, and `docs/release/RELEASE_STATUS.md`.
4. Fold `docs/design/DESIGN_SYSTEM.md` into `DESIGN.md`.
5. Update path-coupled tests/scripts.
6. Archive zero-reference dated docs.
7. Rerun release-doc and repo-wide QA gates.
