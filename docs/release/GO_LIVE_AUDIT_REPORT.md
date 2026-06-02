# Collect Go-Live Audit Report

Audit date: 2026-06-01

Final decision: **NO-GO** until Android SMS access UAT approval, Android
signing/iOS scope evidence, product signoff, and release-owner signoff are
complete.

## Baseline

- Product: Collect ID-only SMS-first MoMo group collection.
- Mobile shell: `Home`, `Groups`, `Settings`.
- Identity model: generated 6-digit Collect ID only; no real names or
  anonymity picker.
- Group model: group name, optional description, receiver MoMo synced from the
  creator profile and editable during creation.
- Payment model: contribution creates a Supabase payment intent and opens the
  MoMo USSD dialer through `tel:`.
- Confirmation model: receiver Android SMS ingestion, OpenAI parsing,
  deterministic payment-intent allocation, exceptions, and immutable ledger.
- Admin model: operational monitoring for groups, members, payment intents,
  SMS parsing, allocations, exceptions, ledger, receivers, audit, settings,
  feature flags, system health, and admin users.

## Gate Results

| Gate | Result | Evidence |
| --- | --- | --- |
| Flutter analyzer | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze` completed cleanly. |
| Flutter release tests | Pass | `101` tests passed after the SMS-first refactor. |
| Supabase migration validation | Pass | `./scripts/migrations/validate_supabase_migrations.sh` passed locally. |
| Edge Function auth contract | Pass | `scripts/collect_edge_auth_contract_uat.sh` passed. |
| Edge Function type-check | Pass | `deno check` passed for parser, ingestion, and allocation functions. |
| Admin PWA local build | Pass | `scripts/admin_pwa_release_build.sh` built `build/web` and passed local PWA gates. |
| Admin PWA render smoke | Pass | `scripts/admin_pwa_render_smoke.sh` passed with evidence at `.cache/repo_wide_qa_uat/20260601T205424Z/admin_pwa_render_smoke`. |
| Admin PWA live deployment | Pass | `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev ./scripts/admin_pwa_live_gate.sh --json` passed. |
| Mobile route render smoke | Pass | `scripts/mobile_route_render_smoke.sh` captured viewport-controlled Chrome CDP 390x844 screenshots and JSON nonblank checks for 21 representative mobile routes at `.cache/mobile_route_render_smoke/20260602T040433Z`. |
| Linked admin/security UAT | Pass | `scripts/collect_admin_security_uat.sh` passed via linked database query. |
| Linked SMS-first contribution UAT | Pass | `scripts/collect_linked_uat.sh` passed via linked database query after the sender-hash migration was applied. |
| Supabase readiness | Pass | `scripts/supabase_production_readiness.sh` passed after applying linked migration history and mobile-state RLS hardening. |
| Supabase release gate | Blocked | Supabase go-live remains NO-GO on product signoff, Android SMS UAT, signing/iOS scope, and release-owner signoff. |
| Real Android SMS access UAT | Pending | Production-flavor Pixel smoke passed at `.cache/android_device_uat/20260602T042542Z/summary.json`; real MoMo SMS consent, ingestion, parser, allocation, and ledger scenario approval is still missing. |
| Android release artifacts | Pass | `scripts/release_artifact_manifest.sh --json` passed and wrote `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-06-02.sha256`; APK/AAB signatures verify. |
| Android signing / iOS scope | Blocked | `scripts/flutter_mobile_release_gate.sh --json` reports `android_release_signing_review` and `ios_release_scope`; artifact signature checks pass. |
| Stakeholder product signoff | Pending | `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md` is ready for review. |

## Safe Fixes Made

- Removed the old user-facing campaign/manual-SMS/anonymity/product-definition
  language from current app and release docs.
- Reworked mobile navigation around Home, Groups, and Settings.
- Reworked group creation, sharing, contribution intent, MoMo USSD launch, and
  profile-synced MoMo/Collect ID copy.
- Reworked Admin PWA navigation around the operational SMS-first workflow.
- Added/updated the Supabase migration and Edge Function contracts for
  contributor Collect ID matching and payment-intent allocation.
- Revoked old manual allocation, public request, public directory, and
  self-reported payment RPC paths from the new migration contract.
- Updated local release gates so Admin PWA build/render and Edge Function
  contracts are verified with current evidence.

## Remaining Blockers

| ID | Area | Severity | Finding | Required action |
| --- | --- | --- | --- | --- |
| P0-001 | Product signoff | P0 | Corrected SMS-first Groups product definition still needs stakeholder approval. | Review and approve `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md`. |
| P0-002 | Android SMS UAT | P0 | Real MoMo SMS app access and automatic parsing/allocation are not freshly evidenced. | Run physical Android UAT with sanitized MoMo SMS scenarios. |
| P0-003 | Admin PWA live | Resolved | Local Admin PWA proof is green and `https://cool-admin-212.pages.dev` passes the deployed URL live gate. | Rerun live gate after every Admin PWA deployment. |
| P1-001 | Release hygiene | Pending refresh | Worktree review must be rerun after the current evidence commit is pushed/reviewed. | Push/review release branch when ready. |
| P0-004 | Store release | P0 | Android signing review and iOS release scope need current release-owner evidence. | Attach signed release metadata or explicitly scope iOS out. |

## Decision Basis

NO-GO. Current code-owned local checks, linked Supabase contribution/admin UAT,
and Admin PWA live proof pass. The platform is not production-ready until real
Android SMS approval, Android signing/iOS scope, and stakeholder release
evidence are complete.

Older CAPTCHA/HIBP/plan/PITR claims from the previous release packet are not
treated as current blockers in this audit unless fresh post-refactor readiness
evidence reproduces them.
