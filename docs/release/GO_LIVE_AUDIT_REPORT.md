# Collect Go-Live Audit Report

Audit date: 2026-08-15

Final decision: **NO-GO**. The current 78-migration/provider-finality source is
locally hardened but not production-deployed, provider-reconciled,
public-link-deployed, artifact-frozen, physically accepted or store-approved.
The June gate table below is retained as historical evidence and must not be
used as current approval. Current acceptance is governed by
`QA_TEST_REPORT.md` and the 2026-08-15 group-journey remediation plan.

## Current 2026-08-15 verification delta

- `flutter analyze` is clean; the canonical suite passes 509 tests and the
  governed visual suite passes 14 tests against 13 pinned baselines.
- A clean local Supabase reset applies all 78 migrations; SQL lint, group,
  linked contribution, Admin security, privacy/provider lifecycle and true
  concurrent-join UAT lanes pass. Supabase contracts pass 68 tests, and the
  provider gateway passes 11 Deno signature/payload/HTTP tests plus type
  checking.
- Android production-debug JVM tests pass. Fresh production APK/AAB generation,
  embedded-runtime checks, upload-key signature verification and the local
  artifact manifest pass; accountable approval remains stale and blocks the
  mobile release gate.
- The local public website passes 56 checks. The live public gate fails 33/35:
  `/c/production-link-audit` is HTTP 404 and deployed brand-asset hashes are
  stale.
- Read-only production inventory is 321/341 expected schema objects and misses
  20 current group/payment contracts. Strict readiness also blocks on the
  warning-level advisor inventory. No production mutation was performed.
- Read-only Edge inventory is 10/11 and specifically misses
  `provider-finality`. Required-secret name inventory is 13/15 and misses
  `PAYMENT_PROVIDER_FINALITY_SECRET_CURRENT` plus the already-open
  `FCM_SERVICE_ACCOUNT_JSON`. No secret values were inspected or recorded.

The historical table below is retained only as prior evidence; where it
conflicts with this delta, the current delta controls.

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
  deterministic payment-intent candidate matching, provider/bank finality,
  exceptions, and an immutable exactly-once two-entry ledger.
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
| Admin PWA render smoke | Pass | `scripts/admin_pwa_render_smoke.sh` passed with evidence at `.cache/admin_pwa_render_smoke/20260602T081408Z`. |
| Admin PWA live deployment | Pass | `ADMIN_PWA_LIVE_URL=https://cool-admin-212.pages.dev ./scripts/admin_pwa_live_gate.sh --json` passed. |
| Mobile route render smoke | Pass | `scripts/mobile_route_render_smoke.sh` captured viewport-controlled Chrome CDP 390x844 screenshots and JSON nonblank checks for 45 stable mobile routes at `.cache/mobile_route_render_smoke/20260602T210133Z`. |
| Linked admin/security UAT | Pass | `scripts/collect_admin_security_uat.sh` passed via linked database query. |
| Linked SMS-first contribution UAT | Pass | `scripts/collect_linked_uat.sh` passed via linked database query after the sender-hash migration was applied. |
| Supabase readiness | Pass | `scripts/supabase_production_readiness.sh` passed after applying linked migration history and mobile-state RLS hardening. |
| Supabase release gate | Blocked | Supabase go-live remains NO-GO on product signoff, Android SMS UAT, signing/iOS scope, and release-owner signoff. |
| Real Android SMS access UAT | Pending | Production-flavor Pixel smoke passed at `.cache/android_device_uat/20260602T042542Z/summary.json`; real MoMo SMS consent, ingestion, parser, allocation, and ledger scenario approval is still missing. |
| Android release artifacts | Pass | `scripts/release_artifact_manifest.sh --json` passed and wrote `output/release_artifacts/BUILD_ARTIFACT_CHECKSUMS_2026-06-02.sha256`; APK/AAB signatures verify. |
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
| P1-001 | Release hygiene | Re-run on final tree; owner signoff pending | Worktree review must pass on the exact final release branch after any recorder, evidence, or release-doc refresh is committed and synced. | Release owner still needs to review and sign the current packet. |
| P0-004 | Store release | P0 | Android signing review and iOS release scope need current release-owner evidence. | Attach signed release metadata or explicitly scope iOS out. |

## Decision Basis

NO-GO. Current code-owned database, authorization, privacy, idempotency,
provider-finality and release-control remediations have local evidence. The
platform is not production-ready until authorized deployment and authenticated
smoke, provider reconciliation, live `/c/*` proof, fresh artifact-bound physical
and TalkBack UAT, Google restricted-SMS/release approval, public availability
and the 72-hour monitoring review are complete.

Older CAPTCHA/HIBP/plan/PITR claims from the previous release packet are not
treated as current blockers in this audit unless fresh post-refactor readiness
evidence reproduces them.
