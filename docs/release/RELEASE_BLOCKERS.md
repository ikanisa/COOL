# Collect Release Blockers

Audit date: 2026-06-01

Decision impact: NO-GO until the SMS-first Groups refactor is signed off,
validated on a real Android SMS device, and approved for the current
Android/iOS release scope. The linked sender-hash preservation migration has
now been applied through the linked Supabase query path and linked contribution
UAT passes.

Update 2026-07-02: mobile screen, popup, wizard, and state completion is now
governed only by root `DESIGN.md`. Any evidence below predates the universal
contract unless rerun on the final current worktree.

This file intentionally does not carry forward older unverified Supabase
platform blockers from the previous product definition. Platform blockers must
come from a fresh `make release-status-json` / Supabase evidence run after this
refactor is deployed or tested against the linked project.

## P0 Blockers

| ID | Area | Finding | Evidence | Required action |
| --- | --- | --- | --- | --- |
| P0-001 | Product contract | Fresh stakeholder approval is still required for the corrected SMS-first Groups definition before production launch. | Legacy mobile/admin/backend paths were removed or revoked and targeted repo validators pass; `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md` is the current source of truth. | Review and sign off the corrected product definition and user journeys. |
| P0-002 | Android SMS ingestion UAT | Real Android MoMo SMS consent, foreground/background/killed/offline upload, parser, and allocation flow is not approved for the new Groups/payment-intent contract. | Production-flavor Pixel smoke passed at `.cache/android_device_uat/20260602T042542Z/summary.json`, but this is not real MoMo SMS scenario evidence. | Run Android device UAT with real MoMo SMS scenarios and store sanitized evidence. |
| P0-003 | Android release signing | Android signing / Play App Signing approval is stale for the current APK/AAB outputs. | Current artifact version is `1.2.2+10`; durable signing approval identifies `1.2.2+9`. `scripts/flutter_mobile_release_gate.sh --json` reports blocker key `android_release_signing_review`; APK/AAB are current and signatures verify. | Review the current hashes, record Android signing approval with `--artifact-version 1.2.2+10`, and rerun the gate. |
| P0-004 | iOS release scope | iOS is explicitly out of scope for the current Android Google Play go-live, but a future iOS submission still requires compatible Associated Domains provisioning and fresh signed evidence. | The current iOS scope record passes; the unsigned archive passes and the signed archive is provisioning-blocked. | No action for Android-only scope; obtain compatible provisioning and new approval before any iOS release. |
| P0-005 | Release-owner signoff | Release-owner approval is stale for the current evidence packet. | Current artifact version is `1.2.2+10`; durable owner approval identifies `1.2.2+9`. `scripts/release_status.sh --json` reports blocker key `release_owner_signoff`. | Review the refreshed packet, record owner approval with `--artifact-version 1.2.2+10`, and rerun release status. |

## P1 Items

| ID | Area | Finding | Evidence | Required action |
| --- | --- | --- | --- | --- |
| P1-001 | Release evidence | Release evidence must be regenerated after Android SMS UAT, Android signing review, iOS scope signoff, and release-owner approval are complete. | Current docs were refreshed to the SMS-first product definition; release gates remain NO-GO on current evidence gaps. | Regenerate UAT/release packet after all validators pass. |
| P1-002 | Human signoff | Stakeholder/user journey signoff for the corrected product definition is still required before production launch. | `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md` exists as the product source of truth. | Review, approve, and attach signoff evidence. |

## Current Green Evidence

- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze`: pass.
- Targeted tests passed:
  - `test/admin_pwa_test.dart`
  - `test/app_shell_test.dart`
  - `test/core/phone_and_public_id_test.dart`
  - `test/features/runtime_component_contract_test.dart`
  - `test/features/widgets_test.dart`
  - `test/persona_uat_smoke_test.dart`
  - `test/shared/collect_repository_test.dart`
  - `test/supabase_contract_test.dart`
- `test/release_docs_test.dart`: pass.
- Raw Admin Flutter-web release compilation passes. The complete
  `scripts/admin_pwa_release_build.sh` wrapper is blocked on the required
  public `COLLECT_ADMIN_WHATSAPP_PHONE` build setting and must not be described
  as a complete current PWA artifact.
- `scripts/admin_pwa_render_smoke.sh`: pass, evidence at `.cache/admin_pwa_render_smoke/20260602T081408Z`.
- `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev ./scripts/admin_pwa_live_gate.sh --json`: pass.
- `scripts/mobile_route_render_smoke.sh`: pass for 45 representative mobile
  routes at `390x844`, evidence at
  `.cache/mobile_route_render_smoke/20260602T210133Z/summary.json`.
- `scripts/android_device_uat.sh`: pass, evidence at `.cache/android_device_uat/20260602T042542Z/summary.json`.
- `scripts/collect_admin_security_uat.sh`: pass via linked database query.
- `scripts/collect_linked_uat.sh`: pass via linked database query after
  applying `supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql`.
- `scripts/supabase_production_readiness.sh`: pass after applying the linked
  migrations and `supabase/migrations/20260602050000_harden_mobile_state_rls_initplan.sql`.
- `scripts/supabase_go_live_evidence_bundle.sh`: blocked as expected on
  release approvals, with code-owned Supabase readiness command `code_owned_readiness`
  exit code `0`; evidence at `.cache/supabase_go_live_evidence/20260602T045205Z/summary.json`.
- `scripts/supabase_go_live_gate.sh --json`: still NO-GO on current
  non-backend approval blockers.
- `scripts/collect_edge_auth_contract_uat.sh`: pass.
- `deno check` passed for:
  - `supabase/functions/parse-payment-sms/index.ts`
  - `supabase/functions/ingest-payment-sms/index.ts`
  - `supabase/functions/allocate-payment/index.ts`
- `./scripts/migrations/validate_supabase_migrations.sh`: pass.
- The current `scripts/release_artifact_manifest.sh --json` run is blocked
  until the Admin wrapper regenerates `custom-sw.js`, `manifest.json`,
  `_headers`, and `robots.txt`.
- `scripts/flutter_mobile_release_gate.sh --json`: Android APK/AAB freshness
  and signature checks pass; evidence at
  `.cache/mobile_release_gate/20260602T050529Z/summary.json`.

## Current Blocked Evidence

- 2026-06-07 mobile completion validation: the 100% completion diff is now
  proven through the pinned Flutter tool snapshot because the shell wrapper was
  unreliable on this machine. `analyze --no-pub`, the focused mobile completion
  tests, shell/design/persona/release docs tests, and the flavored mobile route
  matrix pass on the current worktree. Production Android APK/AAB artifacts were
  rebuilt and signature-verified. Remaining release gate blockers are human
  approvals only: Android release signing review and iOS release scope.
- `scripts/flutter_mobile_release_gate.sh --json`: blocked on Android signing
  review because the durable approval is for `1.2.2+9`, not current
  `1.2.2+10`; iOS Android-only scope passes.
- `scripts/release_status.sh --json`: `NO-GO`, blocked on stale Android signing
  review and stale release-owner approval. Current Android artifacts and other
  recorded approval flags pass the aggregate gate.
