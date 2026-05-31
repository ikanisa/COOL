# Collect Release Blockers

Audit date: 2026-05-31

Decision impact: NO-GO until the SMS-first Groups refactor is validated end to
end against the target mobile app, Admin PWA, and linked Supabase project.

This file intentionally does not carry forward older unverified Supabase
platform blockers from the previous product definition. Platform blockers must
come from a fresh `make release-status-json` / Supabase evidence run after this
refactor is deployed or tested against the linked project.

## P0 Blockers

| ID | Area | Finding | Evidence | Required action |
| --- | --- | --- | --- | --- |
| P0-001 | Product contract | Fresh stakeholder approval is still required for the corrected SMS-first Groups definition before production launch. | Legacy mobile/admin/backend paths were removed or revoked and targeted repo validators pass; `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md` is the current source of truth. | Review and sign off the corrected product definition and user journeys. |
| P0-002 | Android SMS ingestion UAT | Real Android MoMo SMS consent, foreground/background/killed/offline upload, parser, and allocation flow is not freshly evidenced for the new Groups/payment-intent contract. | Code migration and Edge Function checks pass locally; no fresh physical-device SMS evidence has been produced in this refactor pass. | Run Android device UAT with real MoMo SMS scenarios and store sanitized evidence. |
| P0-003 | Linked Supabase deployment | The linked project is not yet on the local SMS-first group and payment-intent contract. | `scripts/collect_linked_uat.sh` reached the linked project and failed because `create_group_with_owner` is not deployed; direct database fallback then timed out from the current operator network. | Run migration apply/dry-run from an allowed database network, then rerun linked readiness and rollback UAT. |
| P0-004 | Admin PWA live deployment | Local Admin PWA build/render/RBAC proof is green, but deployed URL proof is still missing. | `scripts/admin_pwa_release_build.sh` passed; `scripts/admin_pwa_render_smoke.sh` passed with evidence in `.cache/admin_pwa_render_smoke/20260527T041454Z-sms-first-current`; `scripts/collect_admin_security_uat.sh` passed via linked database query; `scripts/admin_pwa_live_gate.sh --json` is blocked by missing `ADMIN_PWA_LIVE_URL`. | Deploy Admin PWA and rerun `ADMIN_PWA_LIVE_URL=... ./scripts/admin_pwa_live_gate.sh --json`. |
| P0-005 | Android release signing | Android release signing / Play App Signing review is not approved for the current APK/AAB outputs. | `scripts/flutter_mobile_release_gate.sh --json` reports blocker key `android_release_signing_review`; APK/AAB artifacts are current. | Record Android release signing review evidence and rerun `scripts/flutter_mobile_release_gate.sh --json`. |
| P0-006 | iOS release scope | iOS release scope is not signed off or explicitly marked out of scope. | `scripts/flutter_mobile_release_gate.sh --json` reports blocker key `ios_release_scope`. | Sign off iOS contributor-only scope or mark iOS explicitly out of scope, then rerun `scripts/flutter_mobile_release_gate.sh --json`. |

## P1 Items

| ID | Area | Finding | Evidence | Required action |
| --- | --- | --- | --- | --- |
| P1-001 | Release evidence | Release evidence must be regenerated after linked Supabase UAT, Android SMS UAT, Admin PWA live proof, Android signing review, and iOS scope signoff are complete. | Current docs were refreshed to the SMS-first product definition; release gates remain NO-GO on current evidence gaps. | Regenerate UAT/release packet after all validators pass. |
| P1-002 | Human signoff | Stakeholder/user journey signoff for the corrected product definition is still required before production launch. | `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md` exists as the product source of truth. | Review, approve, and attach signoff evidence. |

## Current Green Evidence

- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze`: pass.
- Targeted tests passed:
  - `test/admin_pwa_test.dart`
  - `test/app_shell_test.dart`
  - `test/core/phone_and_public_id_test.dart`
  - `test/features/design_system_components_test.dart`
  - `test/features/widgets_test.dart`
  - `test/persona_uat_smoke_test.dart`
  - `test/shared/collect_repository_test.dart`
  - `test/supabase_contract_test.dart`
- `test/release_docs_test.dart`: pass.
- `scripts/admin_pwa_release_build.sh`: pass.
- `scripts/admin_pwa_render_smoke.sh`: pass, evidence at `.cache/admin_pwa_render_smoke/20260527T041454Z-sms-first-current`.
- `scripts/collect_admin_security_uat.sh`: pass via linked database query.
- `scripts/collect_edge_auth_contract_uat.sh`: pass.
- `deno check` passed for:
  - `supabase/functions/parse-payment-sms/index.ts`
  - `supabase/functions/ingest-payment-sms/index.ts`
  - `supabase/functions/allocate-payment/index.ts`
- `./scripts/migrations/validate_supabase_migrations.sh`: pass.
- `scripts/release_artifact_manifest.sh --json`: pass and wrote
  `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-31.sha256`.

## Current Blocked Evidence

- `scripts/collect_linked_uat.sh`: blocked/fails against the linked project
  because the remote database is missing `create_group_with_owner`.
- `supabase db push --dry-run`: blocked by Supabase database network allowlist
  for the current operator IP.
- `scripts/admin_pwa_live_gate.sh --json`: blocked until `ADMIN_PWA_LIVE_URL`
  points to a deployed Admin PWA.
- `scripts/flutter_mobile_release_gate.sh --json`: blocked on Android release
  signing review and iOS release scope.
