# Collect Go-Live Audit Report

Audit date: 2026-05-31

Final decision: **NO-GO** until the corrected SMS-first Groups contract is
validated on the linked Supabase project, Android SMS access UAT, Admin PWA
live deployment, Android signing/iOS scope evidence, and release-owner signoff.

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
| Flutter release tests | Pass | `78` tests passed after the SMS-first refactor. |
| Supabase migration validation | Pass | `./scripts/migrations/validate_supabase_migrations.sh` passed locally. |
| Edge Function auth contract | Pass | `scripts/collect_edge_auth_contract_uat.sh` passed. |
| Edge Function type-check | Pass | `deno check` passed for parser, ingestion, and allocation functions. |
| Admin PWA local build | Pass | `scripts/admin_pwa_release_build.sh` built `build/web` and passed local PWA gates. |
| Admin PWA render smoke | Pass | `scripts/admin_pwa_render_smoke.sh` passed with evidence at `.cache/admin_pwa_render_smoke/20260527T041454Z-sms-first-current`. |
| Admin PWA live deployment | Blocked | `scripts/admin_pwa_live_gate.sh --json` requires `ADMIN_PWA_LIVE_URL`. |
| Linked admin/security UAT | Pass | `scripts/collect_admin_security_uat.sh` passed via linked database query. |
| Linked SMS-first contribution UAT | Blocked/fail | `scripts/collect_linked_uat.sh` fails because the linked database is missing `create_group_with_owner`. |
| Linked migration dry-run | Blocked | `supabase db push --dry-run` is blocked from the current operator IP by database allowlist. |
| Real Android SMS access UAT | Pending | No fresh physical-device evidence exists for MoMo SMS consent, ingestion, parser, allocation, and ledger after this refactor. |
| Android release artifacts | Pass | `scripts/release_artifact_manifest.sh --json` passed and wrote `docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-31.sha256`. |
| Android signing / iOS scope | Blocked | `scripts/flutter_mobile_release_gate.sh --json` reports `android_release_signing_review` and `ios_release_scope`. |
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
| P0-002 | Linked Supabase | P0 | Linked project is behind the local SMS-first migration contract. | Apply/dry-run migration from an allowed DB network and rerun linked UAT. |
| P0-003 | Android SMS UAT | P0 | Real MoMo SMS app access and automatic parsing/allocation are not freshly evidenced. | Run physical Android UAT with sanitized MoMo SMS scenarios. |
| P0-004 | Admin PWA live | P0 | Local Admin PWA proof is green, but no deployed URL proof exists. | Deploy Admin PWA and rerun live gate with `ADMIN_PWA_LIVE_URL`. |
| P1-001 | Release hygiene | P1 | Worktree is dirty and release branch/staging review is not recorded. | Review and stage only intended changes before release. |
| P0-005 | Store release | P0 | Android signing review and iOS release scope need current release-owner evidence. | Attach signed release metadata or explicitly scope iOS out. |

## Decision Basis

NO-GO. Current code-owned local checks are green, and the Admin PWA local build
and linked admin/security UAT pass. The platform is not production-ready until
the linked database matches the SMS-first contract and real Android SMS,
Admin live deployment, Android signing/iOS scope, and stakeholder release
evidence are complete.

Older CAPTCHA/HIBP/plan/PITR claims from the previous release packet are not
treated as current blockers in this audit unless fresh post-refactor readiness
evidence reproduces them.
