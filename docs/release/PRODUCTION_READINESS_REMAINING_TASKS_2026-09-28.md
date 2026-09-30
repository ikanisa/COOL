# Remaining production-readiness tasks for Collect

**Latest remaining-work snapshot:** [29 September exhaustive list](PRODUCTION_REMAINING_TASKS_2026-09-29.md). It reconciles all 101 open checks and includes the subsequent financial replay/rejection, notification lease/ownership and upload-validation findings. This document retains the detailed original acceptance criteria and evidence history.

**Snapshot:** 28 September 2026, updated 29 September. **Decision:** NO-GO. This is the current closure list for the Rwanda-only Collect candidate; it is not a claim that every engineering item is untouched. The [100-task Drive-to-repo crosswalk](EXTERNAL_REVIEW_EVIDENCE_2026-09-28.md) records **100 task rows: 25 P0, 71 P1 and four P2**. The G06 source-governance change has been implemented locally; production approval remains open. The [latest integration report](DRIVE_COMPLETE_COMPARATIVE_INTEGRATION_2026-09-28.md) records the local evidence and blockers at its publication date; the task audit records subsequent checks. Each unchecked box below remains open until its acceptance evidence is tied to the same reviewed release candidate.

**Status key:** “Current” is the repo assessment, often a local candidate or supporting control. “To close” states the remaining action/evidence. P0 is the critical release path; P1 applies before production GO unless explicitly scoped and approved; P2 requires completion or an accountable deferral decision. Source/test presence alone never closes a task.

## Critical path in dependency order

1. Secure Drive and any exposed material, name the canonical release owner/origin, freeze a reviewed commit, and retain `revolut-design` as the sole UI/UX authority (G01–G06, P06).
2. Approve receipt-to-ledger threat boundaries and the actual Rwanda financial/privacy/legal position (S01, F01–F04, P01–P03).
3. Read back the authorized deployed backend and rehearse a complete restore before relying on its behavior (O01–O02).
4. Resolve the five visual failures and complete current route/state review; run pinned clean builds/tests, produce signed artifacts and public/Admin builds, secure exact-package Play SMS approval, and rehearse rollback (Q01–Q05, Q10, M01).
5. Run a bounded monitored pilot with real provider/device, reconciliation, exception and stop criteria, then obtain accountable production approval (O10 and applicable P1 work).

## Current known blockers

- The prior scoring command has been removed. Current route/state visual review remains unverified: original references need validation, owner annotations and accessibility coverage remain open, and five screenshot comparisons failed in the snapshot. No visual acceptance or production GO is claimed.
- The new source remains in a heavily modified recovered worktree and was not committed or pushed as a reviewed release. Staged SQL has not been executed.
- Deployed Supabase parity, independent provider settlement, physical SMS and secure-storage lifecycle, signed production artifacts, store decisions, legal/privacy clearance, restore, operating controls and owner signoff remain unverified.
- The owner now requires `revolut-design` as the sole UI/UX authority and explicitly retired the prior repository scoring rule. The installed skill package was not edited. Current visual evidence remains subject to owner review without a numeric release score.
- The current `make release-status-json` result is **NO-GO** with seven blockers: release approval evidence, the mobile release gate, Android artifacts, Android signing review, Admin PWA live gate, linked Supabase SMS-first UAT, and release-owner signoff. Existing `product_signoff` and `android_sms_uat` flag values are historical metadata and do not close the current owner/artifact gates.

## Critical release tasks (25)

### Source and governance

- [ ] **G01 — Restrict COOL sharing to named collaborators.** Current: [fresh metadata readback](SOURCE_PRESERVATION_AND_TRUST_2026-09-28.md) shows anyone-with-link writer on the COOL root and review environment file; the connector cannot revoke those grants. To close: Owner removes broad grants and verifies readback across source, configs and delivery evidence. Acceptance: Owner confirms no anyone/domain writer grants on source, configs and delivery evidence; retain before/after permission evidence.

- [ ] **G02 — Preserve exposure evidence and scope affected content.** Current: external evidence required; gate open. To close: Owner security review, access logs and actual affected-credential rotation. Acceptance: Read-only revision/access review and incident triage identify time window, credential classes and affected personal data; no unsupported breach conclusion.

- [ ] **G03 — Invalidate real exposed review credentials and isolate secrets.** Current: external evidence required; gate open. To close: Owner security review, access logs and actual affected-credential rotation. Acceptance: Review account disabled/rotated as appropriate; secret scan includes Git history, archives and build outputs with redacted results.

- [ ] **G04 — Establish the trusted full Git origin and release owner.** Current: remote `main` matches local HEAD and [Git object validation plus private bundles](SOURCE_PRESERVATION_AND_TRUST_2026-09-28.md) pass; trusted release origin remains open. To close: Name release ownership and provide an available, verified merge/artifact protection control; branch-protection API currently returns plan-restricted 403. Acceptance: One protected repository, named owner, verified trusted commit and reviewed imports; Drive is not the build authority.

- [ ] **G05 — Freeze the reviewed Increment 11 and v2 reconciliation in one release commit.** Current: a [hash-checked snapshot](SOURCE_PRESERVATION_AND_TRUST_2026-09-28.md) preserves 397 changed/new files and 96 tracked deletions. [Decisions for all four conflicts and eight unique paths](INCREMENT_11_BRANCH_RECONCILIATION_2026-09-28.md) are recorded; the [ten adapted-file diffs](increment-11-adapted-review-2026-09-29/README.md) have now been reviewed against both verified ZIPs, with 229 focused Flutter and 24 Python checks passed. A [synthetic pre-cutover bank upgrade](historical-bank-upgrade-2026-09-29/README.md) preserved seven historical record fingerprints through migration 134; representative and deployed compatibility remain open. To close: resolve those remaining compatibility cases, commit the selected source, and rerun full tests on that exact commit. Acceptance: All four conflicting paths and eight unique paths receive merge decisions; no test/fix silently lost; resulting commit recorded.

- [x] **G06 — Remove the retired repository scoring rule and retain `revolut-design` as sole UI/UX authority.** Current: operative scripts, CI, release wrappers and the active source tree no longer invoke or name the retired rule. Exact-byte historical evidence was moved to the [external review archive](EXTERNAL_REVIEW_EVIDENCE_2026-09-28.md). The installed skill entry point SHA-256 is `59ed494b2dd61684a8f2f516385ba601cfa549b7541bc1e9706df50e28fe3e1a`. This closes source governance only; U01 and production approval remain open.

### Authentication and security

- [ ] **S01 — Threat-model receipt capture through financial posting.** Current: source-backed packet drafted; gate open. To close: Security and finance approval; full-schema, deployed-function and provider-boundary assessment. Acceptance: Trust boundaries, attacker capabilities, evidence levels and abuse cases reviewed by backend, mobile and operations owners.

### Financial evidence and receipts

- [ ] **F01 — Define and implement financial evidence levels.** Current: candidate code reviewed; release unverified. To close: Coordinated DB/Edge/Android/Dart rollout and full account-switch/commit-timeout tests. Acceptance: Requested, handed-off, SMS-observed, reconciled and final statuses have approved meanings; no device-only proof is mislabeled independent provider confirmation.

- [ ] **F02 — Establish independent reconciliation or approved constrained finality.** Current: staged approval design; independent finality open. To close: Staged approval/finalizer SQL has not been executed. Approve and prove an independent provider or statement reconciliation path, including operator review, exceptions, reversal and actual financial finality, before live posting claims. Acceptance: Authorized provider records or controlled statements resolve confirmations/reversals; any SMS-only risk boundary is documented with controls and explicit approval.

- [ ] **F03 — Fail closed on missing/unknown attestation contract.** Current: numbered v2 contract applied in a 133/133 isolated clean-schema replay, with seven rollback-only receipt assertions. Five additional synthetic handler cases now verify that a missing RPC, null, undefined, future or text version blocks both receipt ingestion and parsing before evidence mutation; the handler suite passes 43/43. Release behavior remains unverified. To close: Run this matrix against deployed functions and complete the coordinated DB/Edge/Android/Dart mixed-client rollout, account-switch and commit-timeout tests. Acceptance: Missing RPC, null, unexpected and future versions block secure ingestion with actionable alert; supported staged rollout succeeds.

- [ ] **F04 — Return durable receipt acknowledgements before local deletion.** Current: local v2 contract and native ciphertext-retention corrections passed synthetic SQL/Android checks; installed-device behavior unverified. To close: Coordinated DB/Edge/Android/Dart rollout and full account-switch/commit-timeout tests. Acceptance: ACK requires exact server-persisted envelope ID and current owner; signed-out, no-op, wrong-owner, malformed success and transport failure never delete evidence.

### Native capture and platform

- [ ] **M01 — Complete Google Play SMS permission submission evidence.** Current: external evidence required; gate open. To close: App-store credentials/approvals, signed builds, real supported devices and networks. Acceptance: Release permission list, disclosure, core-use demonstration and approval/accepted policy path documented for actual package/version.

### Privacy and legal readiness

- [ ] **P01 — Confirm product regulatory classification and permitted claims.** Current: external evidence required; gate open. To close: Responsible owner/counsel/privacy team and current vendor/regulator evidence. Acceptance: Counsel reviews actual money/receipt/loan flows and partner roles; applicable authorizations or documented scope exclusions obtained without assuming non-custodial means exempt.

- [ ] **P02 — Evidence controller/processor registration and roles.** Current: external evidence required; gate open. To close: Responsible owner/counsel/privacy team and current vendor/regulator evidence. Acceptance: Responsible entity, registration status, DPO/contact and processing inventory match actual product and vendors.

- [ ] **P03 — Document cross-border transfer and storage basis.** Current: external evidence required; gate open. To close: Responsible owner/counsel/privacy team and current vendor/regulator evidence. Acceptance: Actual hosting/backups/logs/AI locations and required overseas storage authorization documented; transfer grounds reviewed separately.

- [ ] **P06 — Complete exposure and breach-reportability assessment.** Current: external evidence required; gate open. To close: Responsible owner/counsel/privacy team and current vendor/regulator evidence. Acceptance: Privacy/security leads determine actual incident scope and notification duties; preserve timeline and deadlines without treating open sharing alone as proven breach.

### Build, QA and supply chain

- [ ] **Q01 — Resolve locked dependencies on exact pinned SDK.** Current: a fresh isolated Pub cache resolved the unchanged committed lock with Flutter 3.44.4/Dart 3.12.2 and `--enforce-lockfile`; a complete official-archive comparison documented the local `file_saver` fork. To close: repeat from the frozen clean checkout, resolve native/iOS/Edge graphs, review licenses and advisories, and build the production artifacts. Acceptance: Clean isolated full checkout resolves committed locks; local fork provenance/licensing recorded; dependency changes reviewed.

- [ ] **Q02 — Run formatter and full static analysis.** Current: non-writing format and fatal Flutter analysis pass; Android dev lint and unit tests pass with 40 lint warnings and zero errors after an API-aware SMS capability correction. To close: disposition warnings, run generated-source and release-variant checks, then repeat every gate on the frozen commit. Acceptance: Exact reconciled commit passes non-writing format check and fatal analysis across member/admin code; all failures fixed or explicitly dispositioned.

- [ ] **Q03 — Run all existing and new Dart/native/Edge tests.** Current: focused link, Android, Edge, tooling and [full-schema financial SQL checks](financial-core-2026-09-28/README.md) passed. A [new full Flutter run](full-flutter-check-2026-09-29/README.md) on the modified checkout ended **1,378 passes and five byte-identical historical screenshot differences**; the eight earlier profile/MoMo save failures were fixed and the focused account-switch race test passed. This is not exact-commit release coverage. To close: Resolve visual differences through owner review without lowering baselines, then run all Flutter, native, Edge, database and integration suites against one frozen candidate and retain logs. Acceptance: Full suite plus both retained branch suites executes; real results separated from source-string and fake-SDK tooling tests.

- [ ] **Q04 — Build actual production Android and iOS artifacts.** Current: production artifact evidence open. To close: Android dev Kotlin compilation passed only. Build signed production APK/AAB and the scoped iOS artifact from the frozen source; verify signing, version/configuration, hashes, installation and device behavior. Acceptance: Signed production AAB/APK and IPA built with production-safe config; install/run smoke and merged permissions verified; dev APK proxy not substituted.

- [ ] **Q05 — Build and test public and admin release web artifacts.** Current: an [Admin CI candidate job](admin-ci-build-2026-09-29/README.md) now requires production public configuration on the main ref, runs the Admin PWA gates, binds the clean commit and retains output hashes; local empty-bundle checks pass. No hosted candidate or deployed browser evidence exists. To close: Build clean public and Admin web release artifacts from pinned dependencies; smoke auth, route isolation, response headers, warm updates, offline/logout behavior and deployed hashes. Acceptance: Each entrypoint built from clean directory with correct environment; browser smoke, navigation and auth separation pass on deployment candidate.

- [ ] **Q10 — Run release regression and rollback rehearsal.** Current: external evidence required; gate open. To close: Rehearse high-risk member/admin/receipt-to-ledger regression and migration rollback/roll-forward using the exact signed candidate and an isolated realistic environment, preserving receipt and ledger evidence. Acceptance: All high-risk CUJs pass on signed candidate; reverting app/backend compatibility or rolling forward preserves pending receipts and ledger invariants.

### Operations and reliability

- [ ] **O01 — Capture current authorized production-readiness evidence.** Current: external evidence required; gate open. To close: With authorized access, capture timestamped production project, migration, function, RLS/grant, configuration and advisor readback for the exact candidate; investigate drift before deployment. Acceptance: Project identity, migration/Edge versions, advisors, RLS, settings and environment mapping reviewed with timestamp; local config not substituted.

- [ ] **O02 — Configure recovery objectives and demonstrate a restore.** Current: a synthetic database-only archive restored into a new empty database with matching data, schema, roles and grants; the prebootstrapped target was rejected for widened grants. Hosted recovery remains unverified. To close: Approve RPO/RTO and demonstrate isolated restore of the authorized database, Storage, configuration, auth and receipt/ledger evidence; reconcile restored balances and exceptions. Acceptance: Approved RPO/RTO, backup/PITR configuration, isolated restore and ledger/receipt reconciliation documented from the actual environment.

- [ ] **O10 — Run gated pilot and signed production decision.** Current: external evidence required; gate open. To close: Authorized project access, restoration and object recovery, approved objectives/budgets and pilot signoff. Acceptance: Small authorized cohort, daily reconciliation, stop/rollback criteria, support coverage and evidence-backed signoffs completed before expanding.

## Required production tasks (71)

### Source and governance

- [ ] **G07 — Create a baseline-to-release provenance manifest.** Current: [source preservation hashes](SOURCE_PRESERVATION_AND_TRUST_2026-09-28.md) exist; release artifact provenance remains open. To close: Independent trusted manifest, exact release commit, real run evidence and signed approval. Acceptance: Commit, dependency locks, toolchain versions, build inputs and signed artifact hashes link to one reviewable release record.

- [ ] **G08 — Separate build output, private configuration and delivery archives.** Current: generated golden-failure images are ignored and review candidates are retained in the evidence folder; broader gate remains open. To close: Full reference/dependency inventory; original Drive/Git cleanup only after non-use proof. Acceptance: Clean checkout builds without archived outputs; ignore rules and allowed artifact locations are tested.

- [ ] **G09 — Protect merges and artifact publication.** Current: candidate code reviewed; release unverified. To close: Actually configure repository/environment protections, trusted runner and read-only credentials. Acceptance: Required checks/reviews, CODEOWNERS and restricted release credentials are verified by repository policy export.

- [ ] **G10 — Maintain a single release decision register.** Current: supporting control only; gate open. To close: Independent trusted manifest, exact release commit, real run evidence and signed approval. Acceptance: Every release blocker has an owner, evidence link, accepted scope and decision; no checksum/test count is called production approval.

### Authentication and security

- [ ] **S02 — Enforce Rwanda phone validation before OTP reservation/send.** Current: candidate code reviewed; release unverified. To close: Full auth hook staging and actual supported-number/provider tests. Acceptance: Malformed, blank, overlong and non-supported-country inputs rejected without provider calls; valid normalized cases pass.

- [ ] **S03 — Implement layered OTP abuse and spend limits.** Current: candidate code reviewed; release unverified. To close: Run concurrent SQL tests; configure approved quotas and independent source-IP/CAPTCHA budgets. Acceptance: Per-phone, source/network and global quotas withstand concurrent tests; limits cover bypass paths and return safe throttling responses.

- [ ] **S04 — Resolve SMS-hook signature compatibility.** Current: candidate code reviewed; release unverified. To close: Deploy documented hook and secrets; test real signed Supabase payloads and unresolved send recovery. Acceptance: Unsigned/replayed/stale requests fail except any explicitly approved scoped migration path; signed hook integration passes.

- [ ] **S05 — Prove production OTP test mode is disabled.** Current: candidate code reviewed; release unverified. To close: Deploy documented hook and secrets; test real signed Supabase payloads and unresolved send recovery. Acceptance: Production configuration and release artifacts contain no reusable OTP bypass; review accounts isolated and expiry controlled.

- [ ] **S06 — Complete Play Integrity policy and redemption tests.** Current: candidate code reviewed; release unverified. To close: Real Play certificate/build configuration, quota controls, capability redemption and outage tests. Acceptance: Licensed install decision, version policy, hash binding, expiry, replay, quota and unsupported device cases have expected outcomes.

- [ ] **S07 — Replace raw public errors with safe stable codes.** Current: isolated eight-entrypoint HTTP audit passed 38/38; local release-script secret transport is hardened and mock tested, while deployed behavior remains unverified. To close: Audit gateway and log/export surfaces and SDK error paths in deployed functions. Acceptance: Error corpus containing tokens, phone numbers, provider bodies and SQL details does not escape HTTP responses or routine logs.

- [ ] **S08 — Audit actual grants, RLS and security-definer functions.** Current: a guarded 17-assertion synthetic full-schema role test passed anonymous raw-SMS denial, service-only receipt/finality grants, non-admin Admin RLS/RPC denial and private-group history isolation. A separate 15-assertion test passed local approved-owner and approval/role/session invalidation cases. The [retired-bank boundary UAT](historical-bank-boundary-2026-09-29/README.md) passed 11 rollback-only assertions and found no API-role grants across 33 retired functions and ten bank tables. A [pre-cutover record upgrade UAT](historical-bank-upgrade-2026-09-29/README.md) passed 14 more rollback-only assertions for retained rows, API denial, active-read exclusion and retired-client profile calls; hosted grants remain unknown. To close: Read back the authorized hosted schema and extend negative tests to every receiver/operator/service action, concurrent revocation and cross-group ID. Acceptance: Role-by-role exported grants and negative tests prove least privilege for anonymous/member/operator/service roles and raw SMS.

- [ ] **S09 — Verify admin authorization and step-up policy.** Current: local approval panel refresh correction plus 15 rollback-only full-schema Admin assertions passed approved-owner access, sensitive-access audit and same-session approval/role/session invalidation; deployed behavior remains open. To close: Run concurrent/deployed revocation, step-up, Admin UI and complete role/action matrix on the exact candidate. Acceptance: Member sessions cannot access admin data/actions; grants/revocation invalidate access; sensitive actions require audit reason and selected stronger authentication.

- [ ] **S10 — Add bounded provider requests and retry policy.** Current: candidate code reviewed; release unverified. To close: Provider outage/backoff/lease tests and real throughput evidence. Acceptance: OTP/Integrity/provider calls have explicit timeout/backoff budgets; retry class respects idempotence and does not multiply side effects.

### Financial evidence and receipts

- [ ] **F05 — Preserve ciphertext on transient Keystore failures.** Current: candidate code reviewed; release unverified. To close: Android Keystore transient/permanent failure, backup/reinstall and physical-device tests. Acceptance: Transient locked/unavailable key leaves ciphertext recoverable; genuine corruption gets explicit quarantine and support signal, not silent empty success.

- [ ] **F06 — Define capacity and overflow recovery for receipt queue.** Current: candidate code reviewed; release unverified. To close: Approved capacity increase/overflow evidence recovery and durable background delivery. Acceptance: 100/101 boundary, burst and prolonged-offline tests demonstrate retained evidence, overflow visibility and a documented recovery route.

- [ ] **F07 — Resolve late receipt/expired-intent semantics.** Current: full-schema rollback-only tests show exact-expiry and one-minute-late uploads go to review with no payment or ledger entry, even when attested device time falls within the apparent two-hour evidence allowance; 14/16-minute early-device-clock boundaries also behave differently. To close: Obtain the financial owner's choice between always holding late evidence and a bounded review-only candidate, align SQL and operator copy to that policy, then test delayed uploads, clock integrity, concurrent workers and deployed behavior. Acceptance: Before/at/after-expiry and skew outcomes are deterministic, auditable and cannot create credit without independent provider confirmation.

- [ ] **F08 — Prove transaction idempotence and reversal accounting.** Current: SMS self-finality containment, 133/133 isolated clean migration replay and 40 rollback-only financial assertions passed. A [15-assertion adversarial payer rehearsal](payer-identity-adversarial-2026-09-29/README.md) ignored a second payer's reused provider reference without another candidate or changed financial snapshot. A stricter two-worker test exposed a genuine gateway deadlock in migration 134. The additive [lock-order correction and 135/135 concurrency packet](financial-concurrency-2026-09-29/README.md) now pass a populated 134-to-135 upgrade with unchanged 14-row financial digest, simultaneous duplicate SMS handling, two same-confirmation finality workers, one balanced Admin reversal with replay, a conflicting-confirmation race with one winner and no orphan request, and rollback-only confirmation/rejection orderings with no lasting credit change. All results are synthetic local evidence. To close: approve late receipt policy; test authenticated conflicting/delayed events, duplicate references across payments and historical reversal variants on representative upgrade data; read back deployed functions and independent provider evidence. Acceptance: Duplicate/reordered/conflicting references, simultaneous workers and compensation create no duplicate credit; journals balance and audit chain is intact.

- [ ] **F09 — Validate payer identity and ambiguous matches.** Current: confirmed-identity and strict SMS-match migrations passed clean replay; synthetic UAT holds several zero/multiple/conflicting cases for review. A [new full-schema adversarial fixture](payer-identity-adversarial-2026-09-29/README.md) passed 15 rollback-only assertions: same amount/name/phone suffix required distinct confirmed Auth hashes, weak or conflicting identity stayed in review, and two pending routes were ambiguous without a receiver. To close: Exercise concurrent matching and representative historical migrations, duplicate memberships, deployed/provider identity and operator review. Acceptance: Same amount, same phone suffix/name, multiple pending intents, route changes and duplicate memberships require exact identity or operator review.

- [ ] **F10 — Implement reconciliation operations and dispute evidence.** Current: candidate code reviewed; release unverified. To close: Rehearse migrations in the real complete schema; implement/validate operator UI, reviewer-role revocation fencing, provider evidence authenticity and dispute operations. SQL NOT executed. Acceptance: Every exception links receipt, intent, route, journal and resolution; maker/checker where required; notifications cannot independently mark a payment final.

### Database and data integrity

- [ ] **D01 — Profile real history SQL with representative volumes.** Current: full-schema nested `auto_explain` plans with actual buffers passed at 1,000 and 10,000 synthetic read-plan rows for four sorts, first/deep and selected/all-group scopes; production representativeness is unknown. To close: Add approved workload, old-JSON comparison, middle pages, repeat-run variance and accepted p95/p99/scan-growth limits. Acceptance: EXPLAIN ANALYZE BUFFERS captured in isolated staging for all sorts and group scopes; latency/scan growth documented.

- [ ] **D02 — Replace whole-JSON history paging with relational keyset reads.** Current: local additive migration, 133-migration replay and synthetic 1,000/10,000-row first/deep-page checks pass; exact totals/revisions still scan matching rows. To close: Compare against the old JSON path on an approved workload, complete middle-page/concurrent authorization checks and verify the deployed RPC and indexes. Acceptance: Actor-authorized query uses stable ordering/indexes; page depth does not require rebuilding full JSON history; benchmark comparison retained.

- [ ] **D03 — Keep aggregate and revision consistency across pages.** Current: full-schema interleaved authenticated RPC tests reject stale cursors after synthetic posting, reversal and private-group membership revocation; fresh totals and access update, and a stable second page has no duplicate IDs. To close: Exercise the Dart decoder and installed app, privacy-choice and governed financial reversal flows, in-call concurrency pressure and hosted RLS/reconnect behavior. Acceptance: Posting, reversal and permission changes produce consistent totals or a refresh-required response; no mismatched snapshot is accepted.

- [ ] **D04 — Bound recent intent and notification database work.** Current: the full-schema intent rehearsal confirms the 50-row window, old exact-ID lookup and exact active-pending count at 1,000/10,000 intents. The 134th numbered migration moves Admin delivery counts after the notification page; ten JSON parity cases pass, a 10,000-event nested plan reduces delivery probes from 10,001 twice to 25 once, and a separate clean 134/134 PostgreSQL 17.6 replay plus a small historical 133-to-134 upgrade pass. To close: Compare old and new intent paths on a multi-actor workload, test receiver and notification load at expected volume and p95/p99, rehearse representative historical volume, and verify hosted indexes and migration timing. Acceptance: Row limits precede JSON aggregation, old actor-owned IDs resolve, exact count policies are measured, and notification detail work is page bounded.

- [ ] **D05 — Replace label-based ownership attribution.** Current: candidate code reviewed; release unverified. To close: Full-checkout UI/cached payload tests; complete-total fallback changes remain separate D06. Acceptance: Totals use server-authored immutable member/user identity; substring/suffix collisions and forged labels cannot change own totals.

- [ ] **D06 — Remove complete-total fallbacks from partial histories.** Current: local correction tested; live aggregate unverified. To close: Local partial-history fallbacks were corrected and regression tested. Validate the deployed aggregate RPC and all affected group/ledger routes with complete and missing server summaries; preserve Not available when evidence is absent. Acceptance: Unavailable/stale/zero states distinct on every consumer; absent aggregate never computed from a truncated page as a complete total.

- [ ] **D07 — Validate every admin paged RPC against strict client contract.** Current: client paging recovery and 25/26/50/51 tests pass locally; the notification RPC candidate preserves ten old/new JSON cases including sort, search, status and expired offset. To close: Execute Dart/DB contracts against every actual Admin RPC on the candidate, including role/country denial, deterministic ordering under concurrent writes and representative-volume plans. Acceptance: Page boundaries, filters, totals, duplicates, last-page shrink and country scope pass against actual staging RPCs.

- [ ] **D08 — Extend exact-number and date validation across all financial inputs.** Current: intent, contribution, parsed event and legacy-cache decoders hardened with focused tests; broader validation open. To close: Execute complete Dart/DB contracts, all actual RPCs, reconnect cases and financial model migration fixtures. Acceptance: Intent, contribution, modern/legacy summaries and cache paths cover safe-integer bounds, aliases, timezone/calendar errors and valid historical records.

- [ ] **D09 — Rehearse migration and rollback/roll-forward order.** Current: an earlier task-owned PostgreSQL 17.6 fixture passed 133/133 clean migrations, 40 financial and seven receipt rollback-only assertions. A guarded 127+6 historical upgrade preserved the 16-row financial/evidence hash and RWF 1,500 balance, and an empty-target database restore matched data, schema, roles and grants; a prebootstrapped restore was rejected for grant drift. Notification migration 134 passed a separate clean 134/134 replay and a guarded 133-to-134 upgrade of that restored historical fixture: the financial hash/balance, 128 other table-data sections and sequences matched, while three Admin page cases passed and rolled back. A [126+8 pre-cutover bank upgrade](historical-bank-upgrade-2026-09-29/README.md) preserved seven synthetic bank/profile/group/membership fingerprints and passed 14 rollback-only isolation assertions. The [provider lock-order migration 135](financial-concurrency-2026-09-29/README.md) passed two clean 135/135 replays and a guarded populated 134-to-135 upgrade with all 14 financial/evidence rows unchanged. To close: Run a representative historical upgrade through migration 135, then test incompatible installed clients, staged reconciliation, authorized hosted recovery and rollback/roll-forward on the exact candidate. Acceptance: Clean and realistic upgrade databases reach expected schema; incompatible clients fail safely; financial data is preserved.

- [ ] **D10 — Test Realtime reconnect and invalidation boundaries.** Current: bounded rejoin, duplicate, owner-switch and cache-revocation safeguards with focused tests added; deployed validation open. To close: Exercise actual websocket/RLS, offline revocation, account switching and representative traffic. Acceptance: Only authorized areas invalidate; missed/repeated messages trigger bounded refresh without wrong-account leakage or query storms.

### Native capture and platform

- [ ] **M02 — Implement or verify OS-durable receipt drain behavior.** Current: dedicated capture lane, event replay and capped foreground retry added; OS/device validation open. To close: Test persistent recovery and authenticated drain on real devices without storing a background token. Acceptance: Process death, reboot, Doze, network restoration and force-stop expectations documented; no claim that a daemon executor guarantees delivery.

- [ ] **M03 — Align native/server receipt validation bounds.** Current: candidate code reviewed; release unverified. To close: Full Android/Dart execution, all real multipart/provider fixtures and switch races. Acceptance: Sender/body length, multipart, timestamp, envelope ID and provider grammar contract tested at both boundaries.

- [ ] **M04 — Run account-switch races on native queue bridge.** Current: candidate code reviewed; release unverified. To close: Full Android/Dart execution, all real multipart/provider fixtures and switch races. Acceptance: Sign-out, token expiry and account switch at each await preserve/quarantine correct owner evidence and never acknowledge the wrong account.

- [ ] **M05 — Validate backup, reinstall and key-loss behavior.** Current: engineering or validation open. To close: Device and recovery tests including permanent key loss and consent revocation. Acceptance: Release merged manifests and on-device restore tests confirm no leaked raw SMS and explicit recovery expectations when a key is lost.

- [ ] **M06 — Verify Android versus iOS capability matrix.** Current: engineering or validation open. To close: Integrate persistent drain strategy and validate capability/deep-link matrix. Acceptance: Group creation restrictions, joining, contribution handoff and receipt dependency shown accurately; unsupported iOS actions are not dead-end buttons.

- [ ] **M07 — Audit merged iOS privacy/entitlement output.** Current: external evidence required; gate open. To close: App-store credentials/approvals, signed builds, real supported devices and networks. Acceptance: App plus SDK manifests, required-reason APIs, APNS environment and associated domains verified from actual archived IPA.

- [ ] **M08 — Test links and notification routes by identity/state.** Current: 24-hour owner-bound invitations, explicit Join, strict link/QR target parsing and account-switch fencing passed 18 focused Dart tests; ADB UAT was syntax checked but no device was connected. To close: Run installed fresh/signed-out/wrong-group/revoked/malformed/notification matrix on signed builds. Acceptance: Fresh install, signed-out, wrong group, revoked member and malformed URL cases preserve authorization and return useful recovery.

- [ ] **M09 — Test MoMo USSD on real supported networks/SIMs.** Current: local prelaunch intent recheck and synthetic account/receiver tests passed; external evidence required and gate open. To close: Verify the deployed intent function and use signed builds on real supported devices and networks. Acceptance: MTN/Airtel, route deactivation, dual-SIM, cancel, invalid receiver and return-to-app scenarios never equate USSD launch with payment success.

- [ ] **M10 — Record native crash/ANR and low-resource baseline.** Current: external evidence required; gate open. To close: App-store credentials/approvals, signed builds, real supported devices and networks. Acceptance: Selected minimum devices sustain long-session/thermal, memory pressure, background and accessibility journeys with version-bound evidence.

### User experience and admin web

- [ ] **U01 — Complete route/state visual review under `revolut-design`.** Current: historical golden comparisons, unchanged baselines, owner annotation index and five [candidate renders](VISUAL_CANDIDATE_REVIEW_2026-09-28.md) are restored as evidence; visual acceptance is open. One dated cohort source file and all ten older original-mobile image paths are missing. To close: Inventory mobile, Admin and public website routes/states separately; bind selected references, owner annotations, interaction and accessibility evidence to the exact candidate; resolve material mismatches and obtain owner review. Acceptance: Member, Admin and public surfaces mapped to actual states and approved references without a parallel scoring rule.

- [ ] **U02 — Test compact contribution forms and text scaling.** Current: engineering or validation open. To close: Full Flutter/web artifacts and real accessibility, cache, update, localization and admin journey tests. Acceptance: 320x568, 2x text and visible keyboard retain all fields/actions; focus retained while typing; errors and submit reachable.

- [ ] **U03 — Verify screen-reader and keyboard navigation.** Current: engineering or validation open. To close: Full Flutter/web artifacts and real accessibility, cache, update, localization and admin journey tests. Acceptance: TalkBack, VoiceOver and desktop keyboard cover focus order, labels, errors, dialogs, tables and disabled destructive actions.

- [ ] **U04 — Standardize financial terminology and availability states.** Current: Activity and Ledger empty states now show confirmed MoMo wording; absent MoMo routes have no contribution CTA, and the shared component displays guidance visibly. Three [focused route tests](../../test/features/rwanda_scope_empty_states_test.dart) pass; release remains unverified. To close: Complete canonical terminology through remaining routes, Kinyarwanda/localization and screen-reader/device review. No visual acceptance claim. Acceptance: Member/group/contribute terminology consistent; unknown, stale, zero, observed and confirmed values unmistakably different.

- [ ] **U05 — Review offline and recovery states against actual data.** Current: local group-detail load failure now has a retry state, with other supporting controls; gate open. To close: Rendered route/state inventory and product-approved wording on every affected surface. Acceptance: Refresh never claims payment success, no-SMS-replay option verified, no-op/failed refresh cannot report success, queue attention stays visible.

- [ ] **U06 — Validate admin operation flows rather than minimize route count.** Current: local platform-access panel refresh correction implemented; route review remains open. To close: Full Flutter/web artifacts and real accessibility, cache, update, localization and admin journey tests. Acceptance: All 24 declared paths have an intentional role, data source and authorization; consolidation does not remove needed audit/health tools.

- [ ] **U07 — Verify public/admin deployment isolation and security headers.** Current: local header control added; deployed proof open. To close: Local Admin header installer and CI build step exist. Verify actual deployed Admin/public isolation, response headers, authentication boundaries and old service-worker/cache behavior in browsers. Acceptance: Actual responses and bundles show correct entrypoint, restrictive headers appropriate to Flutter, no private data in public caches and no mixed environment.

- [ ] **U08 — Test PWA upgrade, offline and logout caching.** Current: static-cache and auth-user provider safeguards with synthetic two-tab tests added; deployed browser validation open. To close: Full Flutter/web artifacts and real accessibility, cache, update, localization and Admin journey tests. Acceptance: Old/new service workers, failed update, multiple tabs, revoked Admin and account switch do not display another account financial data.

- [ ] **U10 — Measure layout/compositing costs before further redesign.** Current: engineering or validation open. To close: Full Flutter/web artifacts and real accessibility, cache, update, localization and admin journey tests. Acceptance: Profile traces identify rebuild/raster hotspots on minimum device; lazy rendering preserved; no unmeasured FPS or automatic native rewrite claim.

### Privacy and legal readiness

- [ ] **P04 — Complete processor/vendor agreements and due diligence.** Current: external evidence required; gate open. To close: Responsible owner/counsel/privacy team and current vendor/regulator evidence. Acceptance: Supabase, messaging, cloud, AI and support vendors mapped with subprocessors, purposes, retention and incident obligations.

- [ ] **P05 — Define data minimization and retention schedule.** Current: supporting control only; gate open. To close: Approve schedules, implement verified deletion/correction and retention exceptions. Acceptance: Raw SMS, names, phone hashes, financial journals, evidence and analytics each have purpose, access, duration and deletion/hold rules.

- [ ] **P07 — Implement cache/session privacy controls.** Current: candidate code reviewed; release unverified. To close: Flutter/native application builds and real Keystore/Keychain tests, session-token review, logout/clear races, iOS lock/reinstall and browser tests. Existing auth-token storage was not changed. Acceptance: Account-scoped encryption/minimization, logout clearing, clipboard/export and notification previews tested; no irreversible financial evidence deletion by accident.

- [ ] **P08 — Verify account deletion end to end.** Current: engineering or validation open. To close: The protected financial cache source is integrated. Exercise account deletion across server records, storage, native secure cache, browser cache, notifications and legally retained evidence on the exact candidate. Acceptance: In-app initiation, reauthentication, status tracking, vendor deletion and legally retained records explanation demonstrated; disabling account alone not called deletion.

- [ ] **P09 — Align consent, disclosures and store privacy labels.** Current: external evidence required; gate open. To close: Responsible owner/counsel/privacy team and current vendor/regulator evidence. Acceptance: SMS purpose and optionality, processing of payer data, AI extraction and financial-data storage match actual release behavior and reviewed legal basis.

- [ ] **P10 — Document disputes, correction and retention exceptions.** Current: supporting control only; gate open. To close: Approve schedules, implement verified deletion/correction and retention exceptions. Acceptance: Member support process distinguishes app records from provider funds; correction uses traceable entries and legal hold/deletion decisions are auditable.

### Build, QA and supply chain

- [ ] **Q06 — Set critical-path coverage and mutation-test expectations.** Current: supporting control only; gate open. To close: Generate signed-artifact dependency SBOM/licenses and critical-path mutation coverage. Acceptance: Authentication, money, receipt ACK, allocation/reversal and account-switch paths have explicit negative/concurrency coverage; 40% global floor not sole criterion.

- [ ] **Q07 — Generate dependency inventory, SBOM and license review.** Current: source inventory and published-source `file_saver` fork comparison pass; an offline Android production runtime graph records 156 selected external modules and 16 project components. Signed-artifact component and license assurance remain open. To close: repeat Android resolution from the frozen checkout, resolve iOS/Edge transitives, generate signed-artifact SBOMs, review advisories and actual distribution rights, including fonts and image assets. Acceptance: Dart, Gradle, CocoaPods, Deno/npm and local forks checked against supported versions/advisories; approved fonts and asset licenses retained.

- [ ] **Q08 — Protect production-readiness workflow.** Current: the [Admin PWA candidate job](admin-ci-build-2026-09-29/README.md) is main-only, requires configured public production inputs and records a clean source commit plus artifact hashes. Other workflow policy and hosted execution remain unverified. To close: Actually configure repository/environment protections, trusted runner and read-only credentials. Acceptance: PR jobs use isolated credentials; protected release job blocks on missing settings, checks trusted ref and records approvals plus read-only check results.

- [ ] **Q09 — Produce verifiable source-to-artifact provenance.** Current: supporting control only; gate open. To close: Independent trusted manifest, exact release commit, real run evidence and signed approval. Acceptance: Signed build manifest links commit, locks, test result URLs and production artifact hashes outside public-writable storage.

### Operations and reliability

- [ ] **O03 — Protect Storage assets and external evidence separately.** Current: external evidence required; gate open. To close: Authorized project access, restoration and object recovery, approved objectives/budgets and pilot signoff. Acceptance: Object backup/version recovery covers files absent from DB backups; manifests and access policies survive restore.

- [ ] **O04 — Integrate bot protection without breaking OTP journeys.** Current: external evidence required; gate open. To close: Authorized project access, restoration and object recovery, approved objectives/budgets and pilot signoff. Acceptance: Actual WhatsApp/Supabase flow handles valid, missing, expired and failed challenges; approved settings and abuse tests recorded.

- [ ] **O05 — Validate notification scheduler and lease recovery.** Current: candidate code reviewed; release unverified. To close: Real scheduler/leases/duplicate delivery/dead-letter/capacity validation. Acceptance: Stalled workers, provider failures, expired tokens and retry exhaustion recover without endless loops; dead-letter operator path exists.

- [ ] **O06 — Add actionable receipt and financial observability.** Current: supporting control only; gate open. To close: Wire actual metrics/alerts and rehearse with accountable operators. Acceptance: Dashboards show queue depth/age, ACK failures, parsing failures, unmatched receipts, reconciliation age and duplicate/reversal events with redacted correlation IDs.

- [ ] **O07 — Load-test capacity and set service objectives.** Current: external evidence required; gate open. To close: Authorized project access, restoration and object recovery, approved objectives/budgets and pilot signoff. Acceptance: Representative users/history/receipt burst loads, p95/p99 latency and backlog drain times measured; thresholds approved before pilot.

- [ ] **O08 — Set operating-cost budgets and alerts.** Current: external evidence required; gate open. To close: Authorized project access, restoration and object recovery, approved objectives/budgets and pilot signoff. Acceptance: Model cost per OTP, receipt, notification and roster extraction including retries; alerts/limits tested; no invented traffic or margin figures.

- [ ] **O09 — Write and rehearse incident/support runbooks.** Current: supporting control only; gate open. To close: Wire actual metrics/alerts and rehearse with accountable operators. Acceptance: On-call roles handle provider outage, stuck queue, compromised account, corrupt cache, wrong allocation and rollback with escalation criteria.

### AI, assets and operational administration

- [ ] **A01 — Keep AI roster extraction preview-only and audited.** Current: candidate code reviewed; release unverified. To close: Review audit persistence and actual admin commit paths end to end. Acceptance: No model result writes membership or financial state without validated human approval and source/approver audit trail.

- [ ] **A02 — Evaluate extraction on multilingual and adversarial files.** Current: engineering or validation open. To close: Actual fixture evaluation, assets/licenses/reachability, vendor config and operator journey validation. Acceptance: Ground-truth corpus includes scans, duplicates, ambiguous names/numbers and prompt injection; precision/error categories and rejection behavior documented.

- [ ] **A03 — Validate actual upload bytes and resource budgets.** Current: candidate code reviewed; release unverified. To close: Complete image/PDF decode/malware resource tests and account-level extraction budgets. Acceptance: MIME spoofing, oversized/page-heavy/corrupt files and decompression bombs are rejected or sandboxed before vendor calls.

- [ ] **A04 — Verify AI retention, consent and processing configuration.** Current: engineering or validation open. To close: Actual fixture evaluation, assets/licenses/reachability, vendor config and operator journey validation. Acceptance: store=false, vendor retention controls, data-subject basis, geography and minimization documented; no blanket zero-retention claim.

- [ ] **A08 — Govern dynamic settings and product copy.** Current: engineering or validation open. To close: Actual fixture evaluation, assets/licenses/reachability, vendor config and operator journey validation. Acceptance: Existing runtime config/policy RPCs inventoried; thresholds and mutable content have versioning, validation and permissions; stable strings remain local where appropriate.

- [ ] **A09 — Test admin exports, imports and sensitive-data reveal.** Current: engineering or validation open. To close: Actual fixture evaluation, assets/licenses/reachability, vendor config and operator journey validation. Acceptance: Formula injection, row limits, redaction, consent and reason prompts covered; all grants/retries/reveals audited server-side.

- [ ] **A10 — Publish handover and evidence index for one candidate.** Current: supporting control only; gate open. To close: The v2 source was integrated locally. Publish the final handover/evidence index bound to one reviewed commit, deployed artifacts and accountable release decision; do not treat Drive receipts as approval. Acceptance: Owner receives source commit, artifact links, exact tested scope, operational contacts, open exceptions and signed gate status; old branches clearly historical.

## Lower-priority closure or explicit deferral (4)

### User experience and admin web

- [ ] **U09 — Validate real member comprehension and localization.** Current: engineering or validation open. To close: Full Flutter/web artifacts and real accessibility, cache, update, localization and admin journey tests. Acceptance: Rwanda representative users explain where funds go, pending/confirmed distinction and recovery; Kinyarwanda/English copy and long names tested.

### AI, assets and operational administration

- [ ] **A05 — Complete asset-reference reachability inventory.** Current: asset inventory local; full reachability open. To close: The Rwanda runtime manifest was reconciled to 42 concepts and 84 derivatives. Prove reachability, licensing, references, hashes and dimensions for all approved active assets before pruning. Acceptance: Every declared asset/font/icon is traced from active sources/builds and licensed; deletion candidates proven unused on all supported surfaces.

- [ ] **A06 — Verify remaining approved asset bytes and dimensions.** Current: engineering or validation open. To close: Actual fixture evaluation, assets/licenses/reachability, vendor config and operator journey validation. Acceptance: Previously unverified approved assets checked against immutable trusted manifest; stale summaries corrected without silently approving changed artwork.

- [ ] **A07 — Remove proven dead code/dependencies with regression checks.** Current: engineering or validation open. To close: Actual fixture evaluation, assets/licenses/reachability, vendor config and operator journey validation. Acceptance: Deletion-only candidate reviewed; Android/iOS/admin/public builds and all route tests pass; no blanket SVG/font removal based on filename.

## Explicit cross-cutting closure checks beyond the 100 register rows

These make two requirements visible as release checks; they overlap the referenced register rows and are **not** extra Drive task IDs.

- [ ] **X01 — Complete mobile visual review** (U01, Q03–Q04). The [recovered comparison report](VISUAL_CANDIDATE_REVIEW_2026-09-28.md) records five current differences, unchanged baseline hashes and source availability gaps. Validate the original reference images; bind the approved comparison cohort, owner browser annotations, route/state and accessibility cases to the current installed build; resolve the visual differences and open findings through review. Do not blindly regenerate baselines or claim owner approval.
- [ ] **X02 — Reconcile the Rwanda-only release scope** (G10, U04, P01, Q09). The member Activity and Ledger empty states and an Admin detail label no longer advertise bank contributions; the Ledger hides contribution when a group lacks an active MoMo route. A [rollback-only current-schema UAT](historical-bank-boundary-2026-09-29/README.md) passed 11 synthetic assertions. A separate [pre-cutover upgrade](historical-bank-upgrade-2026-09-29/README.md) retained actual predecessor-style synthetic EUR bank and diaspora records through migration 134, with 14 active-scope, grant and old-profile-call assertions. Audit current architecture, deployment, public/support, privacy and store descriptions against the active Rwanda-only RWF/MTN/Airtel MoMo product. Prove representative hosted upgrade retention and the governed historical audit path; do not represent historical rails as current production capabilities or approvals.

## Final GO condition

Close each applicable checkbox with dated evidence for the same source commit, backend state and signed artifact; document any permitted deferral and its owner. Run the protected release gates and require an accountable GO decision after pilot evidence. Until then, the current status is **NO-GO**.
