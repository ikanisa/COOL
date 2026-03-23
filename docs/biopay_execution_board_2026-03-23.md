# BioPay Execution Board

Date: 2026-03-23
Context:

- Audit: `docs/biopay_production_audit_2026-03-23.md`
- Implementation plan: `docs/biopay_implementation_plan_2026-03-23.md`

## Status

Completed already:

- privacy copy improved in the BioPay enrollment flow
- hosted privacy policy updated for BioPay
- iOS camera purpose string updated for BioPay
- permission matrix updated for BioPay camera use
- route-level secure-screen service switched to a cross-platform-first path
- dead BioPay cache writes removed from the live match flow

Still blocked:

- no production model asset in repo
- no step-up auth
- no PAD / liveness
- no backend throttling or attestation enforcement
- no transaction-bound payment flow

## Owner Lanes

Mobile owner:

- `lib/features/biopay/screens/biopay_register_screen.dart`
- `lib/features/biopay/screens/biopay_scan_screen.dart`
- `lib/features/biopay/screens/biopay_confirm_screen.dart`
- `lib/core/services/screen_security_service.dart`
- `lib/shared/widgets/secure_screen_wrapper.dart`

Backend owner:

- `supabase/functions/biopay-enroll/index.ts`
- `supabase/functions/biopay-match/index.ts`
- `supabase/functions/biopay-revoke/index.ts`
- `supabase/migrations/20260322190000_biopay_supabase_foundation.sql`
- future BioPay hardening migrations

ML owner:

- `assets/models/biopay/`
- `lib/features/biopay/services/biopay_embedding_service.dart`
- `lib/features/biopay/services/biopay_face_detection_service.dart`
- `lib/features/biopay/services/biopay_face_alignment_service.dart`

QA / release owner:

- `test/features/biopay/`
- `test/shared/widgets/secure_screen_wrapper_test.dart`
- `integration_test/`
- `.github/workflows/`
- `docs/qa_release_readiness.md`

Product / legal owner:

- `hosting/privacy/index.html`
- `docs/PERMISSIONS.md`
- store metadata outside repo

## P0

Definition:

- Required before any external pilot or non-internal rollout.

P0-01. Bundle and validate the production model asset.
Owner: ML
Touchpoints: `assets/models/biopay/`, `lib/features/biopay/services/biopay_embedding_service.dart`
Dependency: none
Done when: release builds load the real model and the tensor contract is documented.

P0-02. Add step-up auth for enroll, revoke, and payment handoff.
Owner: Mobile
Touchpoints: `lib/features/biopay/screens/biopay_register_screen.dart`, `lib/features/biopay/screens/biopay_confirm_screen.dart`, new auth-gate service
Dependency: none
Done when: a warm session cannot perform any high-risk BioPay action without device auth.

P0-03. Add backend throttling, lockouts, and abuse logging for matching.
Owner: Backend
Touchpoints: `supabase/functions/biopay-match/index.ts`, new risk or throttle migration
Dependency: none
Done when: repeated probing is rate-limited and logged.

P0-04. Enforce device attestation on BioPay edge functions.
Owner: Backend
Touchpoints: BioPay edge functions, app-side token attachment path if needed
Dependency: P0-03 can run in parallel
Done when: BioPay functions reject untrusted device requests.

P0-05. Add PAD / liveness for enrollment and pay matching.
Owner: ML + Mobile
Touchpoints: `lib/features/biopay/services/`, `lib/features/biopay/screens/biopay_scan_screen.dart`
Dependency: P0-01
Done when: spoof attempts are explicitly evaluated and blocked.

P0-06. Convert confirm flow into a transaction-aware payment handoff.
Owner: Mobile
Touchpoints: `lib/features/biopay/screens/biopay_confirm_screen.dart`, `lib/features/biopay/services/biopay_dialer_service.dart`
Dependency: P0-02
Done when: payee, amount, and reference are bound before launch.

P0-07. Finish store and compliance declarations.
Owner: Product / legal
Touchpoints: store metadata, policy copy
Dependency: none
Done when: Play Data Safety and Apple privacy metadata reflect BioPay behavior.

P0-08. Add release gates for model presence and BioPay test health.
Owner: QA / release
Touchpoints: `.github/workflows/`, `docs/qa_release_readiness.md`
Dependency: P0-01
Done when: CI blocks any release with a missing model or failing BioPay gates.

## P1

Definition:

- Required before a broader pilot or production enablement after P0 is complete.

P1-01. Replace crop-only alignment with landmark-based affine alignment.
Owner: ML
Touchpoints: `lib/features/biopay/services/biopay_face_alignment_service.dart`

P1-02. Add real capture quality scoring and persist it.
Owner: ML + Backend
Touchpoints: scan screen, enroll function, migrations

P1-03. Calibrate threshold with measured data instead of defaults.
Owner: ML
Touchpoints: `biopay_match_threshold`, evaluation harness, release docs

P1-04. Extend telemetry with model version, PAD result, quality signals, device class, and decision version.
Owner: Backend
Touchpoints: BioPay edge functions and schema

P1-05. Add repository and edge-function tests.
Owner: QA / release
Touchpoints: `test/features/biopay/`, Supabase function tests

P1-06. Add Android and iOS device-flow tests for enrollment, pay, screenshot blocking, and dialer behavior.
Owner: QA / release
Touchpoints: `integration_test/`, device matrix docs

P1-07. Validate secure-screen behavior on real iOS devices and decide whether native support is still needed beyond the plugin-first path.
Owner: Mobile + QA
Touchpoints: `lib/core/services/screen_security_service.dart`, iOS runtime verification

P1-08. Remove or fully delete remaining cache code if it is still not part of the product.
Owner: Mobile
Touchpoints: `lib/features/biopay/services/biopay_cache_service.dart`, `lib/features/biopay/providers/biopay_providers.dart`, `lib/features/auth/providers/auth_provider.dart`, tests

## P2

Definition:

- Quality, scale, and operational maturity work after the feature is already safe enough for a controlled rollout.

P2-01. Benchmark exact KNN vs IVFFlat vs HNSW and migrate index strategy if needed.
Owner: Backend + ML
Touchpoints: pgvector schema and migration path

P2-02. Add anomaly dashboards and operator alerts for misses, spoof failures, lockouts, and threshold drift.
Owner: Backend + QA
Touchpoints: metrics and operational docs

P2-03. Add fairness and cross-device consistency review to the release process.
Owner: ML + QA
Touchpoints: evaluation harness and release checklist

P2-04. Replace stale BioPay planning statements in `docs/biopay_supabase_implementation_plan.md` with a living readiness doc.
Owner: QA / release
Touchpoints: `docs/`

P2-05. Add support playbooks for false matches, revocation disputes, and enrollment rollback campaigns.
Owner: Product / operations
Touchpoints: operational docs

## Next PR-Sized Chunks

PR-1. Step-up auth scaffolding
Owner: Mobile
Files:

- add `lib/features/biopay/services/biopay_auth_gate_service.dart`
- wire enroll, revoke, and confirm to the auth gate
- add tests around allow / deny / unavailable states

PR-2. Match throttling and abuse telemetry
Owner: Backend
Files:

- update `supabase/functions/biopay-match/index.ts`
- add migration for throttle or risk-event storage
- add function tests for allowed, throttled, and locked-out states

PR-3. Model asset contract and release gate
Owner: ML + QA
Files:

- add bundled model
- update `lib/features/biopay/services/biopay_embedding_service.dart`
- add CI or release-check script that fails on missing model

PR-4. PAD / liveness scaffold
Owner: ML + Mobile
Files:

- add `lib/features/biopay/services/biopay_liveness_service.dart`
- integrate into `lib/features/biopay/screens/biopay_scan_screen.dart`
- add negative-path tests and manual QA checklist

PR-5. Transaction-bound confirm flow
Owner: Mobile
Files:

- update `lib/features/biopay/screens/biopay_confirm_screen.dart`
- update `lib/features/biopay/services/biopay_dialer_service.dart`
- add amount and reference confirmation path

## Recommended Execution Order

1. PR-1
2. PR-2
3. PR-3
4. PR-4
5. PR-5

Reason:

- security controls should land before feature exposure
- backend throttling should exist before the matcher is accessible
- model delivery and PAD should be verified before wider testing
- payment UX should be hardened after trust and anti-abuse controls are in place
