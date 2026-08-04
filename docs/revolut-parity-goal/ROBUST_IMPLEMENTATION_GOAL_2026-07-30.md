# Collect × Revolut Robust Implementation Goal

## Objective

Implement and test the complete July 30 Collect × Revolut improvement plan
inside the existing full-app parity programme. Close all locally actionable
visual, interaction, language, state, accessibility, integration, evidence,
and release-hardening work without weakening Collect's product truth or
claiming external completion from local evidence.

## Source material

- `docs/revolut-parity-goal/GOAL.md`
- `docs/revolut-parity-goal/REMAINING_TASKS.md`
- `output/collect_revolut_parity_audit_20260730/COLLECT_REVOLUT_CRITICAL_COMPARATIVE_REPORT_2026-07-30.md`
- `output/collect_revolut_parity_audit_20260730/COLLECT_REVOLUT_ROBUST_IMPLEMENTATION_PLAN_2026-07-30.md`
- `/Volumes/PRO-G40/AFRICLUB/output/revolut_rayon_visual_audit_20260730/REVOLUT_RAYON_CRITICAL_COMPARATIVE_REPORT_2026-07-30.md`
- `/Volumes/PRO-G40/AFRICLUB/output/revolut_rayon_visual_audit_20260730/REVOLUT_SCREEN_INVENTORY.md`

The detailed `CRP-*` implementation packages and acceptance criteria remain in
the robust implementation plan. This file is the controlled goal overlay that
connects them to the existing `RT-*`, `I-*`, and `E-*` registers.

## Authority

Authorized:

- local Flutter, web, Admin, test, documentation, simulator, emulator,
  accessibility, performance, build, and evidence work;
- privacy-safe fixture data and non-production controlled integration;
- non-destructive inspection of connected devices and local release setup.

Not authorized:

- real payment execution;
- production Supabase mutation;
- credential, key, certificate, or signing-identity creation;
- public deployment;
- store upload or submission;
- user or third-party contact;
- external approval on another person's behalf.

## Non-negotiable outcome

The implementation must preserve:

1. Riverpod, GoRouter, repository ownership, and one confirmed-ledger truth.
2. MoMo handoff and receiver-privacy boundaries.
3. Inter and the governed Collect asset system.
4. Collect-native group, contribution, ledger, and support language.
5. The separation between Revolut's design grammar and unsupported banking,
   custody, card, investment, crypto, exchange, or credit products.
6. Fail-closed completion status while direct evidence or external gates remain
   open.

## Execution packages

### Wave 0 — Governance

- CRP-001: govern the July 30 reference set.
- CRP-002: establish implementation and regression baselines.

### Wave 1 — Immediate local defects

- CRP-101: correct destructive-button state styling.
- CRP-102: repair Activity information hierarchy and truncation.
- CRP-103: establish one product-language contract.
- CRP-104: prove floating-navigation and safe-area clearance.
- CRP-105: make route evidence deterministic.

### Wave 2 — Complete state quality

- CRP-201: simplify Offline and Sync recovery.
- CRP-202: complete authentication hierarchy and state family.
- CRP-203: add task-led Help and recovery entry points.
- CRP-204: complete contribution entry, review, and outcome states.

### Wave 3 — Product Design evidence

- CRP-301: obtain missing privacy-safe auth and amount-entry references.
- CRP-302: produce normalized mobile comparisons.
- CRP-303: complete public and Admin comparison scope.
- CRP-304: refresh Product Design decisions and registers.

### Wave 4 — Integration and device proof

- CRP-401: validate contribution lifecycle in a controlled environment.
- CRP-402: validate backend, offline, and restoration behavior.
- CRP-403: complete assistive-technology and responsive QA.
- CRP-404: complete physical-device performance and resilience.

### Wave 5 — Closeout

- CRP-501: run final local gates and rebuild artifacts.
- CRP-502: prepare the external release handoff.
- CRP-503: complete the final audit and accountable acceptance.

## Current execution checkpoint — E-078

- E-078 captures and visually reviews 16 material states across Dark, Light,
  and System on explicit iOS Light: phone empty/valid, OTP empty/invalid,
  Groups/Activity empty, contribution amount empty/valid, new/reused review,
  deletion disabled/enabled/confirmation, offline, sync, and missing group.
- The state harness is fail closed on exact variant/completion/state markers,
  screenshot count/diversity, simulator identity, and fixture-only evidence.
- Visual review rejected technically passing pre-fix evidence that exposed the
  complete fixture MoMo receiver. Accepted recaptures mask it as `078***3456`
  only when `COLLECT_MOBILE_EVIDENCE_MODE=true`; normal product behavior is
  unchanged.
- The controlled state disposition is in
  `MATERIAL_STATE_COMPARISON_MATRIX_2026-08-01.md`. It distinguishes direct,
  pattern-only, and no-direct-analogue states and makes no feature-equivalence
  claim.
- CRP-302 and RT-005 advance. CRP-301, RT-001, and RT-002 remain blocked on
  direct authentication/OTP and amount/review references, and Product Design
  acceptance remains open.
- E-078 changes a product build input, even though normal behavior is
  unchanged. The production APK/AAB and Admin wrapper were therefore rebuilt
  locally; the nine-artifact freshness manifest passes on E-078 source.
- Canonical test, coverage, source-hygiene, and consistency results are
  recorded after final reconciliation in `VALIDATION_MANIFEST.md`.

### Prior physical-iOS checkpoint — E-077

- E-077 passed the 440-test canonical suite at 78.74% coverage; its artifact
  freshness statement is superseded by E-078's source-input change.
- Physical-iOS execution is now governed by an exact-device, staging-only,
  fixture-only harness that refuses production identity and excludes raw
  device, signing, customer, payment, SMS, OTP, and screenshot evidence.
- The exact iPhone 12 Pro is paired, supported, in Developer Mode, and accepted
  by automatic development signing. A locked attempt was rejected before
  runner start; after unlock, the isolated staging app launched and passed the
  Dark matrix with exact variant/completion markers and 35/35 routes.
- Physical-host screenshots are unavailable and excluded. The accepted route
  matrix is not actual VoiceOver, lifecycle-interruption, OS accessibility, or
  permission-dialog evidence.
- A second System/200%-text/high-contrast/reduced-motion build was rejected at
  0/35 when wireless mDNS/debugger attach failed; it is retained only as
  fail-closed infrastructure evidence.
- The scanner now observes iOS resume, rechecks Camera status after App
  Settings, and coalesces duplicate starts. The exact iPhone 17 Simulator
  recertification passes stopped-app denied/granted states on this current
  source with a visually reviewed recovery sheet.
- Separate exact-device lifecycle and owner-assisted Camera Settings targets
  now prebuild before a bounded unlock window and require their own completion
  markers. Physical attempts reached staging signing/install/attach but were
  rejected after the phone auto-locked before any lifecycle marker; the Camera
  Settings phase and VoiceOver were not completed.
- Next executable action: use a stable unlocked physical window, preferably
  USB, for lifecycle, Camera Settings recovery, and VoiceOver before RT-034 can
  close.

## Required evidence

Every package must produce:

- changed-file inventory;
- focused automated regressions;
- applicable responsive/theme/accessibility captures;
- assumptions and decisions;
- direct mapping to existing `RT-*` and `I-*` items;
- a new sequential `E-*` entry only after the evidence exists;
- explicit limitations and stale-evidence impact.

## Quality gates

1. Authority and scope preserved.
2. Product Design claims grounded in current, privacy-governed evidence.
3. Architecture, ledger, data, security, and privacy invariants preserved.
4. Formatting, static analysis, focused tests, and full tests pass.
5. Responsive, theme, large-text, reduced-motion, focus, target, semantics,
   assistive-technology, performance, and device evidence is complete for the
   claimed scope.
6. Builds, manifests, and hashes come from one recorded source revision.
7. External signing, production, payment, deployment, store, and approval
   gates remain separate and truthful.

## Completion rule

This goal is achieved only when all `CRP-*` packages have direct current
evidence, every resulting P0/P1/P2 issue is closed, all existing `RT-*` exit
criteria are satisfied, `design-qa.md` legitimately ends
`final result: passed`, and the final completion audit proves every required
gate.

If a source, physical device, controlled backend, signing authority, account,
deployment authority, store authority, or named approval remains absent, the
corresponding gate remains blocked. Local completion must not be expanded into
an external or total-completion claim.
