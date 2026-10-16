# Collect Admin readiness — 14 October 2026

**Production acceptance remains NO-GO.** The recovered Admin implementation now has substantial local, full-stack and native-browser proof. Production still serves the older application. The six hosted acceptance gates below remain open.

This review covers Admin only. Efficient Codex governs execution; Revolut Design from Jean Bosco Skills is the sole visual authority. Collect terminology, identity, numeric financial semantics and server permissions are retained. Source hygiene does not certify visual fidelity.

## Current source and preservation

The original workspace is `/Volumes/T7/01 Projects/COLLECT`. Recovered edits, manual merge preimages, failed checks and the older candidate were preserved. An attached managed checkout, `admin-readiness-final/COLLECT`, isolates the reviewed Admin source from unrelated recovered changes. Its initial base is `eed1925260780d079a638603f22837f095f943be`.

The first isolated admission contained 228 paths; the payee guidance test extended it to 229. Released corrections are admitted by path and SHA-256, with target preimages and unchanged-input checks. This document is an additional reviewed documentation input. Exact final commit, file hashes and artifact identity must be read from the generated source/artifact manifests and verification record; a baseline HEAD is not a substitute for them.

Local evidence is under `.cache/admin-resume-20261014/` in the original workspace. That ignored evidence contains fictional credentials/control keys and must not be published wholesale. Redacted findings and source are reviewable independently.

## Findings and local closure

| Finding | Implemented behavior and proof | Remaining boundary |
| --- | --- | --- |
| ADM-01 | Exact-source build, artifact seal and target-specific preflight are implemented. Fresh read-only hosted evidence identifies the older production build. | Deployment, current successful CI and production readback are open. |
| ADM-02 | Stable unchanged-session authority preserves drafts, list state and original requests. Native Users page 26–50 remained intact across an actual successful session refresh. | Repeat on the hosted accepted build. |
| ADM-03–05 | The directory includes Admin, Staff, App and Direct people; six-digit IDs, authorized payment contacts, optional codes, overall/per-group contributed and posted totals are dedicated fields. Native UAT showed 233 people and Direct ALICE’s 25,000 contribution/posted totals. | Hosted identity and accounting acceptance remain open. |
| ADM-06–07 | Reconciliations and SMS have real list/detail routes. Staff created a private draft with a selected Direct owner and recorded receiver. Staff recorded a pending member proposal; privileged approval, posting and team-management controls were unavailable. | Actual hosted roles and delivered activation are required. |
| ADM-08 | Transactions retain collision-safe 18-digit numeric public references, payer/payee suffixes, original provider reference, extracted SMS facts and payer insights. Missing source facts remain unavailable. Native table/detail/payer insight values were inspected. | Real approved receiver/device/provider evidence is required. |
| ADM-09, ADM-11 | Non-Overview records, related sections, role policies and confirmations use dedicated columns with readable label/value semantics. Native narrow Members horizontal scrolling exposed later numeric columns. | Physical devices, spoken screen-reader use and comparator fidelity remain unverified. |
| ADM-10 | Account-security mutation and audit are atomic; fault, authority and lost-response cases are covered by actual backend/session tests. | Real hosted invitation/reset/password/revocation lifecycle remains open. |
| ADM-12–13 | Transaction row bodies open real detail URLs; selectable identifiers remain copyable. Allocation status and amounts are distinct numeric fields. Cookie-backed reload retained the requested posted-journal destination and checkpoint. | Repeat on the deployed artifact. |
| ADM-14 | Search normalizes phones, IDs, names, payment contacts and tested intent/filter terms. Native full-phone search found Direct ALICE by formatted international phone. | Do not describe this deterministic ranking as an embedding model. |
| ADM-15 | Reconciliation is member-first, confirms the recorded name and MoMo identity, and submits exact versions. Native Staff proposal did not create an allocation or posted contribution. | Independent hosted review/posting and original-key recovery are required. |
| ADM-16–17 | Overview has authoritative count/amount links; memberships and related histories page independently. Actual backend aggregates do not depend on truncated UI rows. | Hosted volume/latency budgets remain open. |

## Request history and lost-response recovery

Request history decodes actual versioned operation, unversioned SMS extraction and reconciliation proposal/review receipts. It exposes request ID, original reference, versions and source/review/allocation fields separately. Native Owner, Admin and Staff histories showed their real receipts; an Admin review lookup opened the correct transaction reconciliation using a read-only request lookup.

An explicitly disposable local journal test committed one posting and withheld its response. The UI retained the original intent and key, locked unsafe actions, survived reload into the now-posted record, and resolved the original receipt through GET. Instrumentation recorded exactly one posting write and one additional posted journal. It did not resubmit the financial operation.

Membership recovery retains the exact compound group/person target and can find a checkpoint after the group/user record changes state. Permission, actor, session, expiry, version and receipt binding remain enforced. Source and focused tests cover terminal-state and mismatched-target cases beyond the one native journal scenario.

## Payee lifecycle finding

Native UAT reproduced a legitimate rejection when trying to deactivate an active group’s only receiver. The database guard correctly rolled back the write. The former UI message incorrectly called this an account change.

The transport now distinguishes account, record-state, request-pending and idempotency conflicts without echoing arbitrary server details. The payee form explains the explicit suspend-group → change receiver → reactivate-group workflow and links only to the validated recorded group. Current authority and lock checks apply both while rendering and when invoking the callback. No automatic suspension or weakened receiver guard was introduced.

A real D1 regression verifies unchanged group/payee state, versions, request/audit counts and missing receipt after the rejected operation. Explicit suspension allows deactivation; group activation fails without an active receiver; receiver reactivation then permits group activation. Native verification must be bound to the rebuilt guidance artifact.

## Verification evidence and limits

| Layer | Observed proof | Limit |
| --- | --- | --- |
| Backend | 176/176 complete Admin API tests passed, including actual ephemeral D1/R2 migrations and the payee rollback/lifecycle regression. | Fake email services and explicitly synthetic receipts; no provider acceptance. |
| Flutter | The earlier isolated Admin suite passed 206/206. Followup tests cover context-aware errors and eight payee-link/session/lock cases. A subsequent 249-case run found one old GET-error wording expectation; that expectation was updated while retaining the no-false-empty check. | Use the final aggregate log for final totals; failed evidence is preserved. |
| Analysis/build | The isolated baseline analyzed cleanly and its canonical build/static seal/preflight passed. Followup source requires the final analyzer/build identity. | Local preflight explicitly records `release_admissible: false`. |
| Helpers | 73 helper tests passed with one skipped case; four retirement-worker cases passed. Design-authority hygiene passed. Worker dry-run passed after locked dependency installation. | A local bundle or manifest is not deployment/installed-PWA acceptance. |
| Native baseline | Genuine Chrome clicks, keyboard inputs, screenshots, role journeys, tables, search, paging, receipt links and lost-response recovery against the actual local Worker. | Baseline JS SHA-256 `681cf0c5f5846cb87ef1a52d96de4ad3ed125ff630943fce2a7a26dd5a15ecca`; repeat affected journeys on the final artifact. |

The owned local harness uses migrations 0001–0012, disposable fictional people/accounts/receipts, ephemeral storage and disabled external email. Its seed manifest and artifact archive bind each run; reseeding changes identity and must not silently inherit previous receipts. Failed/stale automation actions and loading snapshots are excluded from passing-case claims.

## Hosted gates and concrete next batch

| Gate | Required evidence |
| --- | --- |
| Hosted accounts | Owner completes the intended fresh activation/password workflow, followed by authorized Owner/Admin/Staff journeys and server denials. No duplicated Owner or credential bypass. |
| Provider/security | Real delivered invitation/reset, expiry/single use, password changes, cross-tab revocation, uncertain dispatch recovery and durable audit. |
| Operating schema/finance | Refresh the verified `collect-admin-accounts` target, preserve recovery evidence, apply only pending 0008–0012, provision the missing private receipt bucket, verify no public bucket exposure, and exercise approved financial workflows. |
| Exact release/CI | Publish the admitted source, obtain current successful required CI, deploy the matching preview artifact/Worker/configuration, and later accept an approved production cutover with exact rollback identity. |
| Monitoring/recovery | Verify redacted live logs and alerts, exercise a disposable restore, measure RPO/RTO and reconcile restored data. |
| Performance/devices | Hosted hashing/CPU/error/load budgets, intended physical/installed browsers and spoken accessibility. Admin manifest metadata is configured; private account responses are never offline-cached. Installed/static-offline lifecycle acceptance is open. |

Fresh read-only migration listing confirmed 0008–0012 are pending on the configured hosted database. Production readback remains version 1.2.4 build 23, source `f0b8b37a0e5c7e97a222127924fb3a7942e74ed2`. Earlier invited-Owner/private-storage observations must be refreshed before mutation.

The exact staged activation commands and prerequisites are recorded in the local `review/hosted-activation-release-plan.json`. The preview configuration targets `admin-preview.collect.ikanisa.com`; it must not be treated as a production configuration. No production cutover, real account/provider mutation, external email, real fund movement or physical-device certification is established by this review.
