# Collect Release Blockers

Audit date: 2026-06-01

Decision impact: NO-GO until the SMS-first Groups refactor is signed off,
validated on a real Android SMS device, and approved for the current
Android/iOS release scope. A fresh linked UAT also shows the linked database
has not yet applied the sender-hash preservation migration for contribution
intents.

This file intentionally does not carry forward older unverified Supabase
platform blockers from the previous product definition. Platform blockers must
come from a fresh `make release-status-json` / Supabase evidence run after this
refactor is deployed or tested against the linked project.

## P0 Blockers

| ID | Area | Finding | Evidence | Required action |
| --- | --- | --- | --- | --- |
| P0-001 | Product contract | Fresh stakeholder approval is still required for the corrected SMS-first Groups definition before production launch. | Legacy mobile/admin/backend paths were removed or revoked and targeted repo validators pass; `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md` is the current source of truth. | Review and sign off the corrected product definition and user journeys. |
| P0-002 | Android SMS ingestion UAT | Real Android MoMo SMS consent, foreground/background/killed/offline upload, parser, and allocation flow is not freshly evidenced for the new Groups/payment-intent contract. | Code migration and Edge Function checks pass locally; no fresh physical-device SMS evidence has been produced in this refactor pass. | Run Android device UAT with real MoMo SMS scenarios and store sanitized evidence. |
| P0-003 | Android release signing | Android release signing / Play App Signing review is not approved for the current APK/AAB outputs. | `scripts/flutter_mobile_release_gate.sh --json` reports blocker key `android_release_signing_review`; APK/AAB artifacts are current. | Record Android release signing review evidence and rerun `scripts/flutter_mobile_release_gate.sh --json`. |
| P0-004 | iOS release scope | iOS release scope is not signed off or explicitly marked out of scope. | `scripts/flutter_mobile_release_gate.sh --json` reports blocker key `ios_release_scope`. | Sign off iOS contributor-only scope or mark iOS explicitly out of scope, then rerun `scripts/flutter_mobile_release_gate.sh --json`. |
| P0-005 | Linked Supabase migration | Linked contribution UAT now verifies the contributor sender hash is stored on payment intents, and the linked project still drops it. | `scripts/collect_linked_uat.sh` fails with `payment intent sender hash was not stored`; `scripts/release_status.sh --json` reports `linked_supabase_sms_first_migration`. | Apply `supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql`, then rerun `scripts/collect_linked_uat.sh`. |
| P0-006 | Release-owner signoff | Release-owner signoff for the current evidence packet is not approved. | `scripts/release_status.sh --json` reports blocker key `release_owner_signoff`. | Review the refreshed evidence packet and record release-owner approval. |

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
  - `test/features/design_system_components_test.dart`
  - `test/features/widgets_test.dart`
  - `test/persona_uat_smoke_test.dart`
  - `test/shared/collect_repository_test.dart`
  - `test/supabase_contract_test.dart`
- `test/release_docs_test.dart`: pass.
- `scripts/admin_pwa_release_build.sh`: pass.
- `scripts/admin_pwa_render_smoke.sh`: pass, evidence at `.cache/repo_wide_qa_uat/20260601T205424Z/admin_pwa_render_smoke`.
- `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev ./scripts/admin_pwa_live_gate.sh --json`: pass.
- `scripts/mobile_route_render_smoke.sh`: pass, evidence at `.cache/mobile_route_render_smoke/20260602T040433Z`.
- `scripts/collect_admin_security_uat.sh`: pass via linked database query.
- `scripts/collect_linked_uat.sh`: blocked until the linked project stores the
  contribution intent sender hash.
- `scripts/supabase_production_readiness.sh`: blocked by linked SMS-first UAT
  until the sender-hash migration is applied.
- `scripts/collect_edge_auth_contract_uat.sh`: pass.
- `deno check` passed for:
  - `supabase/functions/parse-payment-sms/index.ts`
  - `supabase/functions/ingest-payment-sms/index.ts`
  - `supabase/functions/allocate-payment/index.ts`
- `./scripts/migrations/validate_supabase_migrations.sh`: pass.
- `scripts/release_artifact_manifest.sh --json`: pass and wrote
  `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-06-02.sha256`.

## Current Blocked Evidence

- `scripts/flutter_mobile_release_gate.sh --json`: blocked on Android release
  signing review and iOS release scope.
- `scripts/release_status.sh --json`: blocked on product signoff, Android SMS
  device UAT, Android signing review, iOS scope, linked Supabase migration, and
  release-owner signoff.
