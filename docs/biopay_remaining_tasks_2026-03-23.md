# BioPay Remaining Tasks

Date: 2026-03-23

Context:

- audit: `docs/biopay_production_audit_2026-03-23.md`
- implementation plan: `docs/biopay_implementation_plan_2026-03-23.md`
- execution board: `docs/biopay_execution_board_2026-03-23.md`

Completed in repo:

- privacy copy and hosted policy updated for BioPay
- iOS camera and Face ID disclosures updated
- secure-screen handling moved to a cross-platform-first path
- dead cache writes removed from the live match flow
- step-up auth added for enroll, revoke, and payment handoff
- match throttling, repeated-miss lockouts, and abuse telemetry added
- model contract tooling and release-readiness gate added
- challenge-based liveness scaffold added to the scanner
- liveness metadata now reaches BioPay enrollment and match telemetry

Important caveat:

- the new liveness flow is a scaffold, not a production-grade PAD system
- the real BioPay model asset is still not bundled in the repo
- local BioPay Dart and Flutter test execution is currently stalling in build hooks / host startup, so verification is still partial in this environment

## P0 Remaining

P0-01. Bundle the real production model.

- add `assets/models/biopay/mobilefacenet_int8.tflite`
- generate `assets/models/biopay/mobilefacenet_int8.contract.json`
- validate the model on real Android and iOS hardware
- confirm runtime tensor metadata and latency on release builds

P0-02. Enforce device attestation on all BioPay edge functions.

- reject untrusted requests in `biopay-enroll`
- reject untrusted requests in `biopay-match`
- reject untrusted requests in `biopay-revoke`
- verify app-side token attachment and expiry handling

P0-03. Finish PAD from scaffold to enforceable production behavior.

- define the enforcement policy for liveness failure, timeout, restart, and missing metadata
- reject missing or failed liveness server-side instead of only logging it
- add structured persistence for liveness result if it must be auditable outside generic event metadata
- harden against printed-face and replay attacks beyond blink and head-turn heuristics
- calibrate challenge timing and false-reject rates on real devices

P0-04. Convert the confirm flow into a transaction-bound payment flow.

- bind payee, amount, reference, and route into the confirm screen
- require explicit payer confirmation on the final payment payload
- decide whether USSD dialer handoff remains v1 or is replaced by a more structured payment intent flow
- define failure handling for cancel, dialer launch failure, revoked payee, and stale match

P0-05. Finish compliance and store declarations.

- update Play Data Safety for biometric template and camera processing
- update Apple privacy metadata / nutrition labels
- finalize biometric retention, deletion, and consent wording
- get legal signoff on final BioPay policy text

P0-06. Wire release gates into CI, not just local scripts.

- add BioPay model contract checks to GitHub Actions
- add BioPay-specific test gates to CI
- add BioPay liveness checks to release readiness documentation
- verify the kill switch and rollout controls before any external pilot

P0-07. Apply and verify backend changes in real environments.

- apply the BioPay abuse-hardening migration to linked / staging / production projects
- run remote smoke tests for `biopay-enroll`, `biopay-match`, and `biopay-revoke`
- confirm observability events and lockouts behave correctly in the linked project

## P1 Remaining

P1-01. Replace crop-based alignment with landmark-based affine alignment.

- update `lib/features/biopay/services/biopay_face_alignment_service.dart`
- validate that alignment quality improves across pose and framing variance

P1-02. Add real capture quality scoring and persist it.

- compute blur, brightness, occlusion, pose, and face-size quality signals
- derive a production `quality_score`
- send it to backend enrollment
- persist and expose it in a structured way for audits and support

P1-03. Calibrate match thresholds with measured data.

- build an evaluation dataset
- measure FAR, FRR, TAR, and latency
- replace default threshold assumptions with measured thresholds
- document threshold rationale and rollback criteria

P1-04. Extend BioPay telemetry beyond the current scaffold.

- persist model version consistently
- persist liveness result consistently
- add quality signals
- add device class and decision version everywhere needed
- add operator-visible summaries for failed liveness and repeated restarts

P1-05. Add the missing automated tests.

- repository tests for BioPay enroll, match, and revoke paths
- edge-function tests for `biopay-enroll`
- edge-function tests for `biopay-revoke`
- unit tests for shared liveness normalization
- scan-screen integration tests for liveness gating
- negative-path tests for timeout, partial challenge completion, and missing metadata

P1-06. Add real-device test coverage.

- Android enrollment flow
- Android pay flow
- iOS enrollment flow
- iOS pay flow
- screenshot-block behavior verification
- dialer and handoff behavior verification
- liveness challenge behavior on front and rear cameras

P1-07. Validate secure-screen behavior on real iOS devices.

- confirm screenshot blocking behavior is acceptable
- decide whether the plugin-only path is sufficient or native iOS support is still needed

P1-08. Remove or fully retire remaining BioPay cache code.

- confirm whether `lib/features/biopay/services/biopay_cache_service.dart` has any product future
- remove it if it is not part of the shipping design
- remove any dead providers or tests that only support retired cache behavior

P1-09. Fix the local BioPay test-runner stall.

- determine why `flutter test` and `dart test` are hanging in repo build hooks / startup
- restore deterministic local test execution before broader rollout work

## P2 Remaining

P2-01. Benchmark and decide the long-term vector index strategy.

- compare exact search, IVFFlat, and HNSW for BioPay scale and latency
- migrate schema only if measured results justify it

P2-02. Add anomaly dashboards and alerts.

- spoof failures
- repeated liveness restarts
- lockouts
- miss spikes
- threshold drift

P2-03. Add fairness and cross-device consistency review.

- evaluate performance across device classes and camera conditions
- document observed bias or drift and mitigation actions

P2-04. Consolidate BioPay documentation into a living readiness source.

- replace stale planning statements
- keep one current readiness / rollout doc instead of multiple divergent plans

P2-05. Add operational playbooks.

- false-match response
- revocation disputes
- enrollment rollback campaigns
- support escalation paths

## Practical Next Order

1. deliver the real model asset and contract
2. enforce device attestation
3. finish server-side liveness enforcement
4. build the transaction-bound confirm flow
5. wire CI gates and real-environment rollout verification
6. then move into threshold calibration, quality scoring, and real-device QA
