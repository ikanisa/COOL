# Robust COOL/Collect Live-Release Goal

Status: active
Created: 2026-08-04
Release baseline: `1.2.2+10`
Starting revision: `dc87acf1af987de52aa6027d6c364d6e686a651f`

## Objective

Implement, validate, deploy, and evidence the complete Collect customer app and
Admin panel from one controlled source revision. Continue through every locally
executable engineering, QA, backend, accessibility, artifact, deployment,
store-readiness, monitoring, rollback, and closeout task. Do not silently waive
identity, credential, physical-device, provider, store-review, or accountable
approval controls that cannot be delegated to Codex.

## Ownership

Codex is the sole implementation and release execution owner. No workstream is
assigned to an unnamed team. Jean Bosco remains the account holder for secure
authentication, identity verification, verification prompts, and decisions
that a provider or store requires from a natural person.

## Controlled waves

1. Reconcile the current working tree, remove generated/private material,
   validate the UI cleanup, and commit/push `main`.
2. Build Android, Admin PWA, public-site where applicable, and iOS targets from
   the same recorded revision; regenerate hashes and manifests.
3. Close local Admin role, workflow, sanitized-error, accessibility, testing,
   and operations gaps.
4. Run complete mobile/Admin/backend QA, UAT, accessibility, physical-device,
   performance, security/privacy, and reliability gates.
5. Deploy and verify the current Admin PWA with a recorded rollback version.
6. Execute authorized production Supabase, payment/MoMo, and Play Integrity
   validation without retaining raw sensitive data.
7. Complete Google Play and optional iOS submission packs, uploads, processing,
   pre-launch review, vitals, and store evidence where account access permits.
8. Refresh artifact-bound approvals, reconcile every open RT row, pass all
   aggregate gates, and produce the final completion audit.

## Mandatory gates

- Gate 0: scope, authority, privacy, and production-mutation controls.
- Gate 1: product/design evidence and current-source visual acceptance.
- Gate 2: architecture, Supabase, payment, identity, and security controls.
- Gate 3: implementation, test, build, artifact, and repository quality.
- Gate 4: accessibility, responsive behavior, performance, devices, and UAT.
- Gate 5: live deployment, monitoring, rollback, metadata, signing, and stores.
- Gate 6: revision-bound approvals, evidence consistency, audit, and closeout.

## Current execution state

- The August 4 legacy-chrome cleanup, backend hardening, App Links correction,
  public performance split, and deployment records are committed and pushed
  to `main`.
- The Admin PWA and public site are live on their custom domains with exact
  live gates passing and recorded Cloudflare rollback versions.
- The two pending production Supabase migrations are applied; the production
  schema/migration/RLS/advisor gates pass, the notification dispatcher is
  deployed with JWT verification, and the temporary database allowlist entry
  was removed after the operation.
- All 24 locally buildable public/Admin/Android/iOS release files are fresh under
  a cross-platform manifest with per-platform source fingerprints. Android and
  iOS `1.2.2+10` signing reviews pass without exposing signing material.
- The current API 36 Android route matrix passes 35/35 routes with 35 native
  screenshots after correcting stale Offline/Sync evidence assertions.
- The current iPhone 17 iOS 26.5 Simulator route matrix passes 35/35 routes,
  both controlled Camera permission phases pass, and a production-scheme
  unsigned `1.2.2 (10)` archive with dSYM was produced.
- The Google Play listing text, owned feature graphic, icon policy, and two
  current sanitized Android screenshots pass the local Console packet and
  optimization gates.
- The Product Design evidence gate now passes under the owner-approved
  retained/public-reference and explicit no-direct-analogue boundary; this does
  not claim copied assets or complete Revolut screen equivalence.
- GitHub Actions is an external platform gate: all recent pushes and a manual CI
  dispatch fail as `startup_failure` before any job is created even though local
  workflow parsing passes and repository Actions is enabled.
- Remaining gates are non-delegable, version-gated, or externally authenticated: Play
  Developer Reporting and live Console inspection/upload, release-owner and
  ten-persona UAT signoff, physical spoken-assistive-technology and production
  soak evidence, provider-authorized MoMo validation, optional iOS distribution
  provisioning/APNs configuration, Flutter 3.47+ built-in Kotlin validation,
  organization-level CI restoration, and store processing/review.

## Completion rule

The goal completes only when all executable work is finished, every required
gate passes, live actions are verified with rollback evidence, and any remaining
non-delegable external condition is evidenced precisely enough that no further
independent implementation or validation can progress without the account
holder, device, provider, or store.
