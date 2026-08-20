# Collect Go-Live Audit Report

Audit date: 2026-08-20

Final decision: **NO-GO**. The current 79-migration standalone source and Admin
PWA are production-deployed and the rollback-only SMS/ledger balance contract
passes, but provider credentials, a real low-value receipt reconciliation,
artifact freeze, physical acceptance and store approval remain open.
The June gate table below is retained as historical evidence and must not be
used as current approval. Current acceptance is governed by
`QA_TEST_REPORT.md` and the 2026-08-20 group-journey remediation plan.

## Current 2026-08-20 verification delta

- `flutter analyze` is clean; 492 non-golden Flutter tests and 14 governed
  visual tests pass. The Deno Edge suite passes 11 tests.
- Migration-chain validation covers all 79 migrations; group, linked
  contribution, Admin security, privacy lifecycle and true concurrent-join UAT
  lanes are the governed backend checks. Supabase contracts cover the
  standalone OpenAI and balanced-ledger path; Edge type checking is clean.
- Android production-debug JVM tests pass. Fresh production APK/AAB generation,
  embedded-runtime checks, upload-key signature verification and the local
  artifact manifest pass; accountable approval remains stale and blocks the
  mobile release gate.
- The live public website gate passes 35/35, including all 16 sitemap routes,
  `/c/production-link-audit`, governed assets, metadata, security headers,
  performance and accessibility signals.
- Current rendered public-route QA passes 48 route/viewport results covering
  valid, expired, invalid and oversized group links, with 76 screenshots and
  no failures. Evidence is in
  `.cache/group_goal_public_browser_qa/20260820T-current/route_rendered_qa.json`
  (SHA-256
  `16f48e47ce575eea6f7665e8c4a7cfc8861193714f54289a041499dbd6507c2c`).
- Linked production reconciliation passes 79/79 migrations, 336/336 schema
  objects, 60/60 RLS tables, 153 policies, error-level advisors and both
  rollback-only SMS/ledger and Admin security UATs. All 19 files across the 10
  deployed Edge Functions match the repository. Strict readiness fails because
  `FCM_SERVICE_ACCOUNT_JSON`, `STRIPE_SECRET_KEY`, and
  `STRIPE_WEBHOOK_SECRET` are absent. No secret values were recorded.
- Admin PWA version `ff6801b3-447d-45d0-8d50-f5369dcbce2d` was deployed
  directly to production. Its custom-domain live gate passes and its live main
  bundle/bootstrap hashes exactly match the validated 58-file build.

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
- Confirmation model: receiver Android SMS ingestion, OpenAI parsing, exact
  database matching, exceptions, and an immutable exactly-once two-entry ledger.
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
| Admin PWA live deployment | Pass | `https://admin.collect.ikanisa.com` passes the custom-domain gate and exact build hash readback on version `ff6801b3-447d-45d0-8d50-f5369dcbce2d`. |
| Mobile route render smoke | Pass | `scripts/mobile_route_render_smoke.sh` captured viewport-controlled Chrome CDP 390x844 screenshots and JSON nonblank checks for 45 stable mobile routes at `.cache/mobile_route_render_smoke/20260602T210133Z`. |
| Linked admin/security UAT | Pass | `scripts/collect_admin_security_uat.sh` passed via linked database query. |
| Linked SMS-first contribution UAT | Pass | `scripts/collect_linked_uat.sh` passed via linked database query after the sender-hash migration was applied. |
| Supabase readiness | Core pass; provider readiness blocked | Migration/schema/RLS/privilege/advisor/function/UAT gates pass; strict readiness stops on missing FCM and Stripe provider secrets. |
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
| P0-005 | Provider secrets | P0 when in scope | Android FCM and the deployed Stripe/diaspora functions lack their required production secrets. | Provision least-privilege FCM and governed Stripe secrets, or explicitly remove Stripe/diaspora from release scope, then rerun strict readiness and provider UAT. |

## Decision Basis

NO-GO. Current code-owned database, authorization, privacy, idempotency,
atomic allocation, Admin PWA and public deployment controls have production
evidence. The platform is not fully release-ready until the FCM/Stripe scope is
closed, a real low-value receipt is reconciled end to end, fresh artifact-bound
physical and TalkBack UAT passes, Google restricted-SMS/release approval and
public availability are confirmed, and the 72-hour monitoring review completes.

The fresh production run also reports disabled leaked-password protection,
disabled bot protection, the Supabase Free plan and disabled PITR as current
hardening/capacity/recovery findings. They do not override the named provider,
physical-device, store and accountable-approval release gates.
