# Collect Production Readiness Checklist

Audit date: 2026-05-27

This checklist reflects the corrected SMS-first Groups product definition. It
does not carry forward previous unverified Supabase platform blockers. Run
fresh release gates after the linked database is updated before making a final
production decision.

## Current Readiness

| Check | Status | Evidence |
| --- | --- | --- |
| Correct product source of truth | Pending signoff | `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md` describes the approved Groups/SMS-first workflow for review. |
| Mobile navigation contract | Pass locally | App routes and shell are reduced to `Home`, `Groups`, and `Settings`. |
| Removed legacy UX | Pass locally | Public directory, active goals, categories, target amounts, cover URL, anonymity picker, manual SMS paste, and contributor-reported transaction IDs are no longer current user journeys. |
| Profile identity model | Pass locally | Profile owns MoMo and generated 6-digit Collect ID; flows use Collect ID, not real names. |
| International WhatsApp login | Pass locally | Phone normalization supports international `+` numbers instead of Rwanda-only assumptions. |
| Android-only group creation | Pass locally | iPhone group creation warns exactly `group creation is available only on Android`. |
| Payment intent contribution | Pass locally | Contribution creates a payment intent and launches MoMo USSD via `tel:`. |
| Automated SMS parsing/allocation | Partially proven | Edge Function type-check and local contracts pass; linked SMS-first UAT is blocked until the migration is deployed. |
| Admin PWA local build | Pass | `scripts/admin_pwa_release_build.sh` passed. |
| Admin PWA local render smoke | Pass | `scripts/admin_pwa_render_smoke.sh` passed with evidence at `.cache/admin_pwa_render_smoke/20260527T041454Z-sms-first-current`. |
| Admin PWA live deployment | Blocked | `scripts/admin_pwa_live_gate.sh --json` requires `ADMIN_PWA_LIVE_URL`. |
| Flutter analyzer | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze` completed cleanly. |
| Flutter tests | Pass | Full Flutter/release-doc suite passed `79` tests. |
| Local migration validation | Pass | `./scripts/migrations/validate_supabase_migrations.sh` passed. |
| Edge Function auth contract | Pass | `scripts/collect_edge_auth_contract_uat.sh` passed. |
| Linked admin/security UAT | Pass | `scripts/collect_admin_security_uat.sh` passed through linked database query mode. |
| Linked SMS-first contribution UAT | Blocked/fail | Linked database is missing `create_group_with_owner`; migration must be applied. |
| Linked migration dry-run | Blocked | `supabase db push --dry-run` failed from this network with database allowlist error `EADDRNOTALLOWED`. |
| Android real SMS UAT | Pending | Fresh MoMo SMS consent/ingestion/parse/allocation/ledger evidence is not yet recorded. |
| Android release APK/AAB | Blocked | Existing production APK/AAB artifacts are older than current Android/mobile sources; `scripts/flutter_mobile_release_gate.sh --json` reports `android_release_artifacts`. |
| Release worktree review | Pending | The worktree is dirty during active refactor. |
| Android signing and iOS scope | Pending | Current store-release metadata/signoff is not refreshed after this refactor. |

## Production Blockers

Current release-status blocker keys for release readiness include
`linked_supabase_sms_first_migration` and `android_release_artifacts`.

| ID | Blocker | Required action |
| --- | --- | --- |
| P0-001 | Stakeholder signoff for corrected product definition is missing. | Approve `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md`. |
| P0-002 | Linked Supabase is behind the local SMS-first migration contract. | Apply/dry-run migration from an allowed DB network and rerun `scripts/collect_linked_uat.sh`. |
| P0-003 | Real Android SMS access UAT is missing. | Run controlled Android SMS scenarios and attach sanitized evidence. |
| P0-004 | Admin PWA live URL proof is missing. | Deploy Admin PWA and rerun `ADMIN_PWA_LIVE_URL=... ./scripts/admin_pwa_live_gate.sh --json`. |
| P0-005 | Current Android release APK/AAB artifacts are stale. | Rebuild release APK/AAB from current sources and rerun `scripts/flutter_mobile_release_gate.sh --json` plus `scripts/release_artifact_manifest.sh --json`. |

## Release Commands To Rerun

```sh
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze
TMPDIR=/Volumes/PRO-G40/tmp/cool-flutter-test /Volumes/PRO-G40/flutter_3_44/bin/flutter test \
  test/admin_placeholder_test.dart \
  test/app_shell_test.dart \
  test/core/phone_and_public_id_test.dart \
  test/features/design_system_components_test.dart \
  test/features/widgets_test.dart \
  test/persona_uat_smoke_test.dart \
  test/shared/collect_repository_test.dart \
  test/supabase_contract_test.dart \
  test/release_docs_test.dart
./scripts/migrations/validate_supabase_migrations.sh
./scripts/collect_edge_auth_contract_uat.sh
./scripts/admin_pwa_release_build.sh
ADMIN_PWA_RENDER_EVIDENCE_DIR=.cache/admin_pwa_render_smoke/20260527T041454Z-sms-first-current ./scripts/admin_pwa_render_smoke.sh
./scripts/collect_admin_security_uat.sh
./scripts/collect_linked_uat.sh
./scripts/flutter_mobile_release_gate.sh --json
./scripts/release_artifact_manifest.sh --json
```

After deployment:

```sh
ADMIN_PWA_LIVE_URL="https://<admin-host>" ./scripts/admin_pwa_live_gate.sh --json
supabase db push --dry-run
```

## Notes

- Use synthetic or sanitized SMS/payment data in UAT evidence.
- Do not include raw SMS, MoMo numbers, phone numbers, service-role keys,
  OpenAI keys, WhatsApp hook secrets, or production customer data in evidence.
- Treat any older release report that mentions goals, public campaigns, manual
  SMS paste, self-reported transaction IDs, or anonymity options as historical
  only.
