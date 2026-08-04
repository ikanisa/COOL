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

## Current entry blockers

- The August 4 UI cleanup is not yet committed.
- Android and Admin artifacts predate the current source.
- The Admin custom domain fails the current exact live gate.
- Signing and release-owner approvals refer to `1.2.2+9` instead of
  `1.2.2+10`.
- All ten UAT persona rows remain unsigned and lack evidence files.
- Physical accessibility, selected physical-iOS behaviors, production soak,
  and account-controlled store/provider checks remain open.

## Completion rule

The goal completes only when all executable work is finished, every required
gate passes, live actions are verified with rollback evidence, and any remaining
non-delegable external condition is evidenced precisely enough that no further
independent implementation or validation can progress without the account
holder, device, provider, or store.
