# Collect Production Readiness Checklist

Audit date: 2026-06-01

This checklist reflects the corrected SMS-first Groups product definition. It
does not carry forward previous unverified Supabase platform blockers. Run
fresh release gates after Android SMS UAT and release signoffs before making a
final production decision.

## Current Readiness

| Check | Status | Evidence |
| --- | --- | --- |
| Correct product source of truth | Pending signoff | `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md` describes the approved Groups/SMS-first workflow for review. |
| Collect product-boundary scan | Pass locally | `scripts/collect_product_boundary_scan.sh --json` passed across 80 Flutter source files with zero forbidden Buro/crypto/trading/legacy navigation hits. |
| Mobile navigation contract | Pass locally | App routes and shell are reduced to `Home`, `Groups`, and `Settings`. |
| Removed legacy UX | Pass locally | Public directory, active goals, categories, target amounts, cover URL, anonymity picker, manual SMS paste, and contributor-reported transaction IDs are no longer current user journeys. |
| Profile identity model | Pass locally | Profile owns MoMo and generated 6-digit Collect ID; flows use Collect ID, not real names. |
| International WhatsApp login | Pass locally | Phone normalization supports international `+` numbers instead of Rwanda-only assumptions. |
| Android-only group creation | Pass locally | iPhone group creation warns exactly `group creation is available only on Android`. |
| Payment intent contribution | Pass locally | Contribution creates a payment intent and launches MoMo USSD via `tel:`. |
| Automated SMS parsing/allocation | Backend linked UAT pass; real SMS UAT pending | Edge Function type-check and local contracts pass. Linked SMS-first rollback UAT passes after applying the contribution-intent sender-hash migration. Production-flavor Pixel smoke passed at `.cache/android_device_uat/20260602T042542Z/summary.json`, but real Android MoMo SMS scenario approval is still pending. |
| Admin PWA local build | Pass | `scripts/admin_pwa_release_build.sh` passed. |
| Admin PWA local render smoke | Pass | `scripts/admin_pwa_render_smoke.sh` passed with current standalone evidence at `.cache/admin_pwa_render_smoke/20260602T081408Z`. |
| Admin PWA live deployment | Pass | `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev ./scripts/admin_pwa_live_gate.sh --json` passed. |
| Mobile route render smoke | Pass | `scripts/mobile_route_render_smoke.sh` captured viewport-controlled Chrome CDP 390x844 screenshots and JSON nonblank checks for 45 stable mobile routes at `.cache/mobile_route_render_smoke/20260602T210133Z`. |
| Flutter analyzer | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze` completed cleanly. |
| Flutter tests | Pass | Full Flutter/release-doc suite passed `101` tests. |
| Local migration validation | Pass | `./scripts/migrations/validate_supabase_migrations.sh` passed. |
| Edge Function auth contract | Pass | `scripts/collect_edge_auth_contract_uat.sh` passed. |
| Linked admin/security UAT | Pass | `scripts/collect_admin_security_uat.sh` passed through linked database query mode. |
| Linked SMS-first contribution UAT | Pass | `scripts/collect_linked_uat.sh` passed via linked database query after applying `supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql`. |
| Linked Supabase readiness | Pass | `scripts/supabase_production_readiness.sh` passed. It used linked query/advisor/schema gates because direct pooler lint/dry-run remains unavailable from this network because of Supabase tenant allow-listing. |
| Android real SMS UAT | Pending | Fresh MoMo SMS consent/ingestion/parse/allocation/ledger evidence is not yet recorded. |
| Android release APK/AAB | Pass | Production APK/AAB artifacts are newer than Android/mobile sources, checksums were refreshed, and signatures verify; `scripts/release_artifact_manifest.sh --json` passed and wrote `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-06-02.sha256`. |
| Release worktree review | Re-run on final tree | `scripts/release_worktree_review_gate.sh --json` must pass on the exact final release branch after any recorder, evidence, or release-doc refresh is committed and synced. |
| Android signing and iOS scope | Blocked | `scripts/flutter_mobile_release_gate.sh --json` reports `android_release_signing_review` and `ios_release_scope`; artifact freshness/signature subchecks pass. |

## Production Blockers

Current release-status blocker keys for release readiness are
`product_signoff`, `android_sms_access_uat`,
`android_release_signing_review`, `ios_release_scope`, and
`release_owner_signoff`.

| ID | Blocker | Required action |
| --- | --- | --- |
| P0-001 | Stakeholder signoff for corrected product definition is missing. | Approve `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md`. |
| P0-002 | Real Android SMS access UAT is missing. | Run controlled Android SMS scenarios and attach sanitized evidence. |
| P0-003 | Android release signing / Play App Signing review is missing. | Record signing review evidence and rerun `scripts/flutter_mobile_release_gate.sh --json`. |
| P0-004 | iOS release scope is not signed off. | Sign off iOS contributor-only scope or mark iOS explicitly out of scope, then rerun `scripts/flutter_mobile_release_gate.sh --json`. |
| P0-005 | Release-owner signoff for the current evidence packet is missing. | Review the current evidence packet and record release-owner approval. |

## Release Commands To Rerun

```sh
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze
TMPDIR=/Volumes/PRO-G40/tmp/cool-flutter-test /Volumes/PRO-G40/flutter_3_44/bin/flutter test \
  test/admin_pwa_test.dart \
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
ADMIN_PWA_RENDER_EVIDENCE_DIR=.cache/admin_pwa_render_smoke/20260602T081408Z ./scripts/admin_pwa_render_smoke.sh
./scripts/mobile_route_render_smoke.sh
./scripts/collect_admin_security_uat.sh
./scripts/collect_linked_uat.sh
./scripts/supabase_production_readiness.sh
./scripts/flutter_mobile_release_gate.sh --json
./scripts/release_artifact_manifest.sh --json
```

After deployment:

```sh
ADMIN_PWA_LIVE_URL="https://cool-admin-212.pages.dev" ./scripts/admin_pwa_live_gate.sh --json
```

## Notes

- Use synthetic or sanitized SMS/payment data in UAT evidence.
- Do not include raw SMS, MoMo numbers, phone numbers, service-role keys,
  OpenAI keys, WhatsApp hook secrets, or production customer data in evidence.
- Treat any older release report that mentions goals, public campaigns, manual
  SMS paste, self-reported transaction IDs, or anonymity options as historical
  only.
