# Collect — exhaustive remaining production tasks

**Snapshot: 30 September 2026 (Africa/Kigali), revision 3. Release decision: NO-GO.**

**101 acceptance checks remain open: 99 of the 100 original tasks, plus X01 and X02.** G06 is locally closed. An open check can contain substantial implemented work; this count does not measure code completion.

| Priority | Open | Required disposition |
| --- | ---: | --- |
| P0 | 24 | Critical release blockers; acceptance before production |
| P1 | 71 | Required implementation and production acceptance |
| P2 | 4 | Complete or record a specific accountable deferral |
| Crosscutting | 2 | Exact-build visual and Rwanda-only scope acceptance |
| **Total** | **101** | Crosscutting checks overlap other tasks |

**Evidence state:** 65 Partial, 29 External, 7 Unverified. Partial means implementation/evidence exists but acceptance is incomplete. External means decisive proof, access or decisions are external. Unverified means required coverage has not been established. Named accountable owners remain unverified; responsible roles are listed below.

**Source:** HEAD `c2569a47c7f87de68a60c4a247b5c5e3ca640f06` plus 619 working-tree status entries. Capture: `2026-09-29T22:55:51.582738+00:00`. No release candidate is frozen. 142 migration files are present; isolated execution reaches 141, and the last complete clean replay remains 138. Migration 142 is work in progress.

## Latest verified progress and evidence limits

- **F10/S09/D09:** five real two-session reconciliation scenarios passed: duplicate finalization and both orders of Auth and Admin-role revocation. Synthetic postings were balanced; the graph was removed and scoped data/control fingerprints restored.
- **F10/S08/D09:** the superseded staged installer refused before mutation on 141; all 58 original reconciliation assertions passed in the explicit integrated variant. Both runs preserved data, function and ACL fingerprints.
- **O05/S10/D09:** 35 registration and 62 notification delivery/session SQL assertions passed on the isolated 141 fixture. All 124 table fingerprints were restored after each rollback. The strengthened real notification-session race harness still awaits execution.
- **D09:** read-only tracing accounts for the ten additional synthetic Realtime events while proving all 560 baseline events and 123 other table fingerprints unchanged. Original phase transaction IDs were not captured; attribution and any cleanup disposition remain open. No trace cleanup was performed.
- **F10/D07/U05/P07:** the retained reconciliation UI and notification recovery packets contain local MFA/ACK/paging/session and recovery tests. Current hash readback matches all 51 reconciliation sources/48 artifacts and 15 recovery sources/five artifacts at capture. These are scoped mocked checks; installed/deployed acceptance remains.
- **A01/A09:** SQL142, source/consent-first Edge extraction and typed session-pinned Admin review/commit work is actively being integrated. Source exists; it is not frozen, applied or accepted. The old flow’s provenance, all-row access and retry/ACK gaps remain until replacement and verification.
- **A03/A09/Q01/Q03:** the older XLSX packet has current source drift in dependency declarations and roster parsing, plus two log-hash mismatches. Its 57-test result is historical evidence and requires a fresh complete packet.
- **A05/A06/Q01/Q07:** fresh read-only checks still fail: seven indexed local asset deletions and stale candidate dependency inventory. All 174 present approved asset hashes match.

No new Drive permissions, hosted project/provider, legal/store or signed physical-device evidence was verified. Local synthetic tests keep an item open until its stated required environment and accountable acceptance are satisfied. PostgreSQL sequence allocations are not restored by rollback; the SQL packets state this limitation.

## Immediate engineering and validation queue

- **A01, A09, S09, P07:** Finish source/consent/extraction/review/approver provenance and reference-bound roster commits across SQL142, Edge and Admin. Prove all-row access, strict ACK, retry identity, bypass closure and session-race behavior.
- **D09, O05, S10:** Review the exact ten traced synthetic Realtime events; execute strengthened notification-session races and complete clean/final-set replay. Apply/test142 only after source review and backup.
- **F10, S09, S08:** Validate authentic reconciliation intake, deployed MFA/role/session/GoTrue semantics, exceptions/disputes/reversals and operator acceptance; rerun the five local races and integrated58 cases on the frozen candidate.
- **P07, O05, M08, U05:** Validate recovery against deployed Auth, installed permission/lifecycle/session changes and actual APNS/FCM delivery.
- **O05, S10:** Configure and prove unattended hosted scheduling and real provider backoff, duplicate and dead-letter recovery.
- **S03, O04, O08:** Complete trusted end-user network/bot controls and concurrent phone/account/global quota and spend acceptance.
- **S04:** Complete evidence-based uncertain OTP-send recovery without blind resend.
- **A02:** Build and evaluate labeled multilingual/scan/identity-ambiguity/prompt-injection inputs.
- **A03, A09:** Complete image/PDF/page/animation expansion limits, durable budgets, original-versus-derived XLSX validation and realistic browser/workbook resource acceptance.
- **O06:** Complete push queue/lease/completion/scheduler metrics and alerts, then rehearse operator response.
- **Q01, Q03, Q07, A05, A06, A10:** Resolve seven asset deletions and stale dependency inventory; preserve the drifted XLSX evidence and retain fresh source/lock/log-matched validation.
- **U01, Q03, X01:** Resolve five visual differences and missing comparators; complete exact-build route/state/accessibility and owner review.

These are subtasks within the original IDs, not additional count items.

## G — Source and governance: 9 open

**Responsible roles:** Repository/release owner, security owner and engineering lead.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| G01 | P0 | External | Remove broad Drive write/sharing grants from source, configuration and delivery evidence; retain permission readback proving access is limited to approved collaborators. Recheck the 28 September observation. |
| G02 | P0 | External | Preserve revisions/access evidence and establish the actual exposure window, affected material and personal-data scope. Record findings without inferring access from open sharing alone. |
| G03 | P0 | External | Scan Git history, ignored archives and outputs with redacted results; rotate or disable genuinely exposed credentials and prove old credentials no longer work. |
| G04 | P0 | External | Name the release owner and canonical trusted Git origin; verify protected merges/artifact publication despite the earlier protection-API 403. Bind reviewed imports to the trusted source. |
| G05 | P0 | Partial | Finish representative compatibility validation of the selected Increment 11/v2 changes, preserve all merge decisions, integrate remaining corrections and freeze one reviewed release commit. Repeat full validation on that commit. |
| G07 | P1 | Partial | Produce a manifest binding the frozen source, dependency locks, toolchain, build inputs and signed artifact hashes; retain trusted review evidence. |
| G08 | P1 | Partial | Prove an isolated clean checkout builds without private archives, ignored outputs or undeclared files. Verify artifact locations and ignore rules before removing anything. |
| G09 | P1 | External | Configure and export actual required checks/reviews, code ownership, trusted runners and restricted publication credentials; demonstrate enforcement on protected release paths. |
| G10 | P1 | Partial | Assign a named accountable owner to every blocker, with dependency, next action, dated evidence and decision/deferral. Bind one decision register to the release candidate. |

## S — Authentication and security: 10 open

**Responsible roles:** Security lead, authentication/backend engineer and Admin owner.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| S01 | P0 | Partial | Obtain security, finance and operations review of the complete receipt-to-ledger threat model, including the newly found finality and notification boundaries; verify deployed functions, callers and provider trust. |
| S02 | P1 | Partial | Stage the real OTP hook and prove malformed, unsupported-country and invalid Rwanda numbers fail before reservation/provider calls; valid supported numbers must authenticate. |
| S03 | P1 | Partial | Implement or configure trusted end-user source/network and bot controls before the signed OTP hook; the hook caller IP is not the end-user IP. Approve per-phone/global spend limits and test concurrent reservations, bypasses and safe throttling. |
| S04 | P1 | Partial | Implement evidence-based recovery for reserved-but-unresolved OTP sends without blindly resending an uncertain delivery. Verify actual signed hook configuration, signature checks, stale/replayed requests and the complete recovery procedure. |
| S05 | P1 | External | Read production Auth/hook settings and exact release configuration; prove reusable test OTP mappings, bypasses and unbounded review accounts are disabled. |
| S06 | P1 | Partial | Test Play Integrity on certificate/version-bound builds: replay, expiry, redemption, quota, outages and unsupported-device behavior, with approved expected outcomes. |
| S07 | P1 | Partial | Extend stable-error verification to deployed gateways, logs, exports and SDK failures. Test a corpus containing secrets, phone data, provider responses and SQL details for leakage. |
| S08 | P1 | External | Export actual hosted grants, RLS and security-definer functions; test every role, cross-group ID, receiver/operator/service action and concurrent revocation. Verify finality helper grants and migration-order effects. |
| S09 | P1 | Partial | Verify every sensitive Admin operation against the deployed role/action/step-up matrix, durable audit and immediate role, approval and session revocation. Validate actual GoTrue transaction and whole-transaction retry behavior, configured MFA factors, installed-browser account switching and accessibility. Repeat passing local reconciliation races on the frozen candidate. |
| S10 | P1 | Partial | Run the strengthened 141 notification-session concurrency cases and coordinated server/client rollout. Rehearse actual OTP, Integrity, extraction and push outages, transport/commit uncertainty, quotas, bounded retries and provider Retry-After under representative throughput. Verify deployed scheduler settings, credentials and unattended recovery; repeat scoped checks after source freeze. |

## F — Financial evidence and receipt custody: 10 open

**Responsible roles:** Finance/reconciliation owner, backend/mobile engineers and operations.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| F01 | P0 | Partial | Approve requested, handed-off, SMS-observed, reconciled and final meanings; align DB, Edge, Android, Dart and all financial wording. Test the coordinated rollout and commit-timeout/account-switch boundaries. |
| F02 | P0 | External | Approve an independent provider/statement evidence route or an explicit constrained finality policy. Prove source authenticity and settlement-to-candidate matching, including ambiguous evidence, exceptions, corrections and reversals before treating any review hash as final-payment evidence. |
| F03 | P0 | Partial | Run missing/null/unsupported/future receipt-contract cases against deployed handlers and mixed client versions; verify no mutation, actionable alerts and safe coordinated rollout. |
| F04 | P0 | Partial | On installed devices, prove only an exact durable, current-owner server ACK deletes the corresponding envelope; test no-op/malformed success, wrong owner, transport/commit timeout and consent/account-switch races. |
| F05 | P1 | Partial | Exercise transient/permanent Keystore failure, corrupt ciphertext, quarantine, reinstall and support recovery on physical devices; transient faults must retain recoverable evidence. |
| F06 | P1 | Partial | Approve queue capacity and overflow policy; test 100/101 boundaries, bursts and prolonged offline use with persistent attention signals and recoverable evidence. |
| F07 | P1 | Partial | Decide late-upload/expired-intent/grace and clock-skew policy; align SQL and operator wording, then test before/at/after expiry, delayed upload and concurrent workers without device-only final credit. |
| F08 | P1 | Partial | Extend the locally verified replay/rejection correction to representative historical and authenticated provider cases, cross-payment duplicate references, delayed events and reversal variants; verify deployed definitions and balanced journals. |
| F09 | P1 | Partial | Extend exact confirmed-payer matching to concurrent candidates, duplicate memberships and deployed/provider identity; ambiguous or conflicting evidence must enter the governed exception process without automatic credit. Validate historical remediation. |
| F10 | P1 | Partial | Complete authentic evidence intake, deployed AAL2 and actual GoTrue transaction/retry integration, exception/dispute/reversal journeys and operator acceptance. Rerun the now-passing five reconciliation races, staged-installer refusal and 58 integrated assertions on the frozen candidate and representative staging data; preserve evidence and balanced history. |

## D — Database and data integrity: 10 open

**Responsible roles:** Database/backend engineer and data/QA lead.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| D01 | P1 | Partial | Capture representative history plans for all sorts, scopes and first/middle/deep pages; compare old/new paths and repeated p95/p99, buffers and scan growth against approved limits. |
| D02 | P1 | Partial | Finish relational keyset performance/authorization validation and hosted RPC/index readback. Verify page depth avoids whole-history JSON reconstruction; measure remaining total/revision scans. |
| D03 | P1 | Partial | Test client and installed-app handling of posting, governed reversal, privacy/membership changes and concurrent reads; require consistent totals/revisions or explicit refresh, including hosted RLS. |
| D04 | P1 | Partial | Validate bounded recent-intent and notification work at representative multi-actor/receiver volumes; compare previous paths, measure exact totals and migration/index timing, and read back deployed definitions. |
| D05 | P1 | Partial | Test all ownership totals against server-authored immutable identity, forged labels, name/phone-suffix collisions and cached payloads. |
| D06 | P1 | Partial | Exercise every history/group/ledger consumer with complete, absent, stale and zero server summaries; a partial page must never be presented as a complete financial total. |
| D07 | P1 | Partial | Validate every Admin paged RPC on staging: bounds, exact totals, filters, country scope, role denial, concurrent deterministic ordering and realistic volume. Recheck queue shrink during real writes. Reconciliation review/history paging is implemented; its lineage display pages use the complete returned detail response and require payload-volume acceptance. |
| D08 | P1 | Partial | Audit all modern/legacy financial inputs and actual RPC/cache payloads for exact integer bounds, aliases, identifiers, timezone/calendar validity and preserved valid historical values. |
| D09 | P1 | Partial | Run a complete clean replay through the final frozen migration set; the last accepted clean replay is 138. Resolve the ten traced synthetic Realtime events from the 140-to-141 upgrade with an explicitly reviewed disposition, then complete notification-session races, representative populated upgrades and incompatible-client cases. Migration 142 roster provenance is under construction and needs its own upgrade/UAT/race coverage. Rehearse rollback/roll-forward and authorized hosted recovery while preserving financial/evidence history. |
| D10 | P1 | Partial | Test deployed Realtime reconnect/missed/duplicate messages, offline revocation and account switches under load; verify bounded refresh and no wrong-account cached data. |

## M — Native app, devices and stores: 10 open

**Responsible roles:** Android/iOS engineers, physical-device QA and store owner.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| M01 | P0 | External | Obtain the exact Android package/version restricted-SMS permission decision, release disclosure and core-use evidence; retain actual Play readback tied to signed artifact hashes. |
| M02 | P1 | Partial | Verify real SMS capture and authenticated drain through process death, reboot, Doze, offline recovery and force stop; record OS limits and retained pending evidence. |
| M03 | P1 | Partial | Run one valid/malformed multipart/provider SMS corpus against native capture and server receipt bounds; prove matching decisions at each boundary. |
| M04 | P1 | Partial | Test sign-out and account-switch races at every async native queue/permission boundary on devices; retain old-owner ciphertext and prevent cross-account drain. |
| M05 | P1 | Unverified | Exercise release-build backup, restore, reinstall, permanent key loss and consent revocation; prove no raw-SMS leakage and documented recovery behavior. |
| M06 | P1 | Partial | Validate truthful Android/iOS capabilities and complete group, membership, contribution and receipt journeys; unsupported operations must have useful explanations/recovery. |
| M07 | P1 | External | Inspect the signed iOS archive's merged app/SDK privacy manifests, required-reason APIs, entitlements, APNS environment and associated domains. |
| M08 | P1 | Partial | Test installed links, QR and recipient-bound notification taps through fresh install, cold start, delayed Auth restoration, signed-out, wrong account/group, revoked membership, expiry and malformed input. Exercise permission recovery, stale taps and session replacement on exact signed Android/iOS artifacts with real APNS/FCM delivery and backend route authorization. |
| M09 | P1 | External | Run MTN/Airtel real-SIM USSD tests including dual-SIM, cancellation, route changes, invalid receiver and return to app; launch must never be reported as payment success. |
| M10 | P1 | External | Record crash/ANR, memory-pressure, thermal, long-session and background baselines on minimum supported physical devices and exact release versions. |

## U — Member experience, Admin and public web: 10 open

**Responsible roles:** Product/design owner, mobile/web engineers and accessibility QA.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| U01 | P1 | Partial | Review all material mobile/Admin/public routes and loading, empty, failure, geography, membership, responsive and accessibility states against verified applicable references. Resolve differences and obtain owner review on the exact build. |
| U02 | P1 | Partial | Test compact 320×568 layouts, 2× text and real keyboards through validation and submission; retain focus and reachability of every required action. |
| U03 | P1 | Partial | Complete actual TalkBack, VoiceOver and desktop keyboard tasks, including labels, focus, errors, dialogs, tables and sensitive/destructive controls. |
| U04 | P1 | Partial | Finish consistent Kinyarwanda/English financial terminology on every visual and spoken route; distinguish pending, observed, confirmed, unavailable, stale and genuine zero. |
| U05 | P1 | Partial | Review rendered offline/recovery states using real data/queue conditions. Failed refresh must remain truthful, retry must work and persistent receipt attention must remain visible. Validate the implemented notification registration recovery on installed devices, actual OS permission changes and session replacement. |
| U06 | P1 | Unverified | Walk every declared Admin route and operation with its intended role, actual data source and authorization; preserve necessary audit, health, import and support tools. |
| U07 | P1 | Partial | Verify deployed public/Admin entrypoints, bundles, environments, authentication, security headers and old caches; public content must not expose private account data. |
| U08 | P1 | Partial | Test deployed PWA warm upgrade, failed updates, offline behavior, multiple tabs, logout, revocation and account switching without stale private content. |
| U09 | P2 | Unverified | Run representative Rwanda-member comprehension tests in Kinyarwanda and English for money destination, status and recovery; document findings and corrections or approved deferral. |
| U10 | P1 | Unverified | Profile layout/rebuild/raster/compositing costs on representative minimum devices; fix measured hotspots and verify lazy rendering before further structural redesign. |

## P — Privacy and legal readiness: 10 open

**Responsible roles:** Responsible entity, privacy/security owner and qualified legal reviewer.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| P01 | P0 | External | Obtain a reviewed regulatory classification, partner-role assessment and permitted claims for the actual Rwanda money/receipt/credit-readiness flows; record required authorizations or supported scope decisions. |
| P02 | P0 | External | Establish and evidence responsible entity, controller/processor roles, registration status, privacy/DPO contacts and a complete processing inventory. |
| P03 | P0 | External | Verify actual hosting, backup, logs and AI processing locations; obtain the required transfer/storage determination and supporting grounds. |
| P04 | P1 | External | Complete processor/vendor and subprocessor diligence, agreements, purpose limits, retention and incident obligations for cloud, messaging, AI and support services. |
| P05 | P1 | Partial | Approve and implement minimization, retention, deletion and legal holds by data class, including raw receipts, hashes, journals, evidence, caches and analytics. |
| P06 | P0 | External | Complete evidence-led exposure and reportability assessment, timeline and required actions with accountable security/privacy review. Open sharing alone is not proof of data access. |
| P07 | P1 | Partial | Verify deployed migration-141/Auth integration and concurrent session revocation/replacement. Complete signed Android/iOS locked, foreground/background/killed preview, permission recovery, cancellation and tap tests with actual APNS/FCM delivery. Verify caches, clipboard and exports across logout/switch without losing recoverable financial evidence. Rerun the integrated release candidate after freeze. |
| P08 | P1 | Partial | Demonstrate account deletion from reauthentication and status tracking through server/vendor/device cleanup, with a truthful explanation and controlled access for lawfully retained records. |
| P09 | P1 | External | Reconcile consent, SMS/payer-data disclosures, AI use and store privacy declarations with exact signed behavior and the approved legal basis. |
| P10 | P1 | Partial | Approve and rehearse auditable disputes, correction entries, support, legal-hold and deletion-exception procedures; distinguish app records from provider funds. |

## Q — Builds, QA and provenance: 10 open

**Responsible roles:** Engineering/release lead, QA, signing owner and supply-chain owner.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| Q01 | P0 | Partial | Resolve committed locks on exact pinned runtimes from a frozen clean checkout; finish native/iOS/Edge locking, fork provenance and distribution-rights review. Reconcile the stale candidate inventory and rerun integrated resolution after all dependency declaration changes. |
| Q02 | P0 | Partial | Repeat non-writing formatting and full Flutter/native/generated-source/release-variant analysis on the frozen candidate; resolve or explicitly disposition all warnings, including the 40 recorded Android lint warnings. |
| Q03 | P0 | Partial | Resolve the five visual failures through reviewed references, then run complete Flutter, native, Edge, database and installed/browser integration suites on one frozen candidate. Retain exclusions and actual logs. |
| Q04 | P0 | External | Produce signed production AAB/APK and scoped iOS archive; verify configuration, version, signatures, merged permissions and hashes, then install/test those exact bytes. Resolve missing signing material through its owner. |
| Q05 | P0 | Partial | Build clean public and Admin release artifacts with correct public configuration and fresh required screenshots; verify candidate hashes, deployed auth/route separation, headers, warm update and offline/logout behavior. |
| Q06 | P1 | Partial | Define and measure critical-path negative/concurrency coverage and mutation expectations for auth, receipt ACK, allocation/finality/reversal and account switching. An aggregate coverage floor alone is insufficient. |
| Q07 | P1 | Partial | Reconcile and regenerate the currently stale candidate inventory from reviewed frozen source; finish iOS/Edge/native graphs and signed-artifact SBOMs. Review advisories, licenses, image/font redistribution and fork provenance; validate the resulting inventory. |
| Q08 | P1 | External | Verify hosted production-readiness workflow execution, trusted refs, isolated PR credentials, protected environments, reviewer requirements and retained build/check evidence. |
| Q09 | P1 | Partial | Bind signed artifacts to the protected commit, locks, toolchain and actual test runs with independently retained provenance and hash readback. |
| Q10 | P0 | External | Rehearse high-risk member/Admin/receipt-to-ledger journeys and app/backend rollback or roll-forward using the exact signed candidate; preserve pending receipts, balances and compatibility. |

## O — Operations and production release: 10 open

**Responsible roles:** Platform/SRE owner, support/reconciliation operators and release owner.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| O01 | P0 | External | Read back the authorized target project, migrations, function versions, grants/RLS, advisors and configuration with timestamps; resolve drift before deploying or relying on behavior. |
| O02 | P0 | External | Approve RPO/RTO and demonstrate isolated recovery of the actual database, roles/grants, Auth, configuration and receipt/ledger evidence; reconcile balances and measure recovery time. |
| O03 | P1 | External | Demonstrate Storage-object and external-evidence backup/version recovery separately from database restore, including manifests and effective access policies. |
| O04 | P1 | External | Configure and test actual OTP bot controls for valid, absent, expired and failed challenges without breaking supported WhatsApp/Supabase journeys. |
| O05 | P1 | Partial | Execute the strengthened notification-session concurrency fixture, including logout/replacement, newer-session precedence, claim/preflight/completion, audited retry and mixed Auth-transaction cases. Rerun the frozen integrated candidate. Configure, deploy and activate the recurring scheduler; prove unattended retry/stale-lease recovery, real provider/scheduler failures, duplicate/dead-letter support and representative capacity. |
| O06 | P1 | Partial | Wire redacted receipt/financial metrics and alerts for queue age, ACK/parse failures, unmatched evidence, reconciliation age and reversals. Add native push queue-age, lease-loss, completion-pending and scheduler-health monitoring; the existing SMS-outbox health function does not cover those push controls. Rehearse operator response. |
| O07 | P1 | External | Run representative user/history/receipt/provider/notification load tests; approve measured p95/p99, capacity, backlog-drain and availability objectives before pilot. |
| O08 | P1 | External | Approve and test OTP, notification, storage and AI cost budgets, per-account/global limits and alerts using measured retry/traffic assumptions. |
| O09 | P1 | Partial | Assign on-call/escalation roles and rehearse provider outage, stuck queue, compromise, corrupt cache, wrong allocation and rollback procedures. |
| O10 | P0 | External | Run a bounded authorized pilot with daily independent reconciliation, support, monitoring and stop/rollback criteria; obtain an evidence-backed accountable GO decision before expansion. |

## A — AI, assets and administration: 10 open

**Responsible roles:** Admin/backend engineer, privacy/security owner, asset owner and release lead.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| A01 | P1 | Partial | Finish and integrate migration 142, Edge and typed Admin receipts: original-byte source hash, pre-provider consent/model metadata, immutable candidate and parent-linked human review, latest-reviewed-revision-only create/add commit, and exact stable-request ACK. Close both raw-row bypasses; preserve all rows and lineage through edits, response loss and account/session replacement. Run SQL upgrade/replay/adversarial/race, Edge and Dart workflow tests on frozen source, then deployed provider/operator acceptance. |
| A02 | P1 | Unverified | Build a ground-truth evaluation covering scans, multilingual text, duplicate/ambiguous identities and prompt injection; measure error classes and prove safe rejection/correction. |
| A03 | P1 | Partial | Complete bounded image/PDF decoding and page/animation expansion controls or a validated sandbox; enforce durable concurrent per-account/global resource and cost budgets. Validate representative inputs, browser/device worst-case memory/latency and deployed/vendor behavior. Preserve the now-passing XLSX pre-allocation controls through integrated regression. Retain original XLSX provenance while separately identifying client-derived TSV; complete its transformation validation without claiming server verification from a source hash alone. |
| A04 | P1 | External | Verify actual AI vendor retention/store settings, processing geography, consent/legal basis and minimization; obtain vendor/privacy evidence rather than inferring it from request flags. |
| A05 | P2 | Partial | Trace every active asset, font and icon through all builds/references and licenses, including font redistribution rights. Reconcile the seven indexed local asset deletions with the reviewed Git/manifest inventory; establish reachability before further removals. |
| A06 | P2 | Unverified | Resolve the current asset-check failure from seven indexed files deleted locally; 174 approved file hashes match. Verify all approved bytes and dimensions against independent trusted provenance and document intended removals or changed artwork without automatic restoration. |
| A07 | P2 | Unverified | Identify proven unused code/dependencies and prepare a reviewed deletion-only change; run Android/iOS/Admin/public build and route regression before removal is accepted. |
| A08 | P1 | Partial | Inventory mutable runtime settings and product copy; test permissions, validation, versions and audit. Keep stable application strings distinct from governed operator settings. |
| A09 | P1 | Partial | Validate representative Excel/LibreOffice workbooks and worst-case browser/device memory/latency. Test imports/exports for formula injection, bounds and redaction; test consent/reasons, permission failures and durable server audit receipts for imports, grants, retries and sensitive reveals. Preserve XLSX preflight protection in the full workflow. Complete reference-bound create and existing-group imports with all-row review, exact ACK and lost-response retries; rerun the drifted XLSX packet from preserved test inputs. |
| A10 | P1 | Partial | Publish one candidate-bound handover identifying source, deployment, signed artifact hashes, exact tests/exclusions, contacts, approved exceptions and accountable decision. Retain all logs and manifests in the reviewed deliverable or a verified archive; reconcile dependency/asset inventories and historical versus current evidence. |

## X — Crosscutting acceptance checks: 2 open

**Responsible roles:** Product/design owner and accountable release owner.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| X01 | Crosscutting | Partial | Resolve all five retained visual differences; obtain valid reference coverage or explicitly reviewed adaptations, then bind route/state, interaction, accessibility and owner annotations to the exact installed/browser build. Missing original references remain an evidence gap. |
| X02 | Crosscutting | Partial | Verify Rwanda-only RWF/MTN/Airtel MoMo scope across deployed routes, public/support/privacy/store material and historical-data access. Prove representative upgrade retention without restoring retired capabilities to the active product. |

## Dependency order and closure rule

1. **Accountability and source:** G01–G04,G09–G10,P06; identify the authorized environment for O01 and store/provider/privacy/legal owners.
2. **Policies and behavior:** S01–S10,F01–F10 and immediate engineering above. Finality, expiry, queue, retention, MFA and cost decisions must support the implementation.
3. **Integrated data and source:** D01–D10,A01–A09, realistic upgrades/restores and compatibility. Freeze G05; resolve/build Q01–Q03/Q05 and update Q07 from that candidate.
4. **Actual release surfaces:** signed Q04, installed M01–M10, U01–U10,X01/X02, approved P01–P10 and hosted O01/O03–O09/Q08 acceptance.
5. **Rehearsal and release:** Q10,O02,O09; bounded reconciled O10 pilot; G07/Q09/A10 evidence and an accountable GO/NO-GO decision.

Every closure needs integrated source, passing stated cases in the required environment, retained source/configuration/artifact/date evidence, and accountable acceptance of policy or permitted deferral. Source changes require affected reruns. External cases can proceed in parallel with engineering.

## Evidence index and preserved definitions

- [Machine-readable register](production-remaining-tasks-2026-09-30.json): all 102 IDs, original criteria, current evidence, remaining work, priorities, roles and dated evidence history.
- [Original acceptance definitions](PRODUCTION_READINESS_REMAINING_TASKS_2026-09-28.md) and [dated implementation audit](PRODUCTION_TASK_IMPLEMENTATION_AUDIT_2026-09-28.md).
- [Reconciliation UI packet](reconciliation-ui-2026-09-30/README.md) and [validation manifest](reconciliation-ui-2026-09-30/validation.json).
- [Reconciliation 140 upgrade](governed-reconciliation-2026-09-30/upgrade140.json), [58-case UAT](governed-reconciliation-2026-09-30/rollback140.json) and [both 140 deployment orders](governed-reconciliation-2026-09-30/deployment-order140.json).
- [Protocol 139 upgrade](notification-protocol2-2026-09-29/upgrade139.json), [claim race](notification-protocol2-2026-09-29/concurrency139.json) and [scoped code validation](notification-protocol2-2026-09-29/CODE_VALIDATION.md).
- [Current notification recovery packet](notification-recovery-ui-2026-09-30/README.md): 181 passing tests, clean analysis and 15 source/manifest fingerprints.
- [Dated repository session-fencing packet](repository-session-fencing-2026-09-30/README.md): historical 35-test scope, followed by the current 181-test rerun.
- [97 notification SQL assertions](notification-session-fencing-2026-09-30/rollback141.json), [five reconciliation races](governed-reconciliation-2026-09-30/concurrency141.json) and [post-141 refusal/integrated assertions](governed-reconciliation-2026-09-30/post141-deployment-result.json).
- [Read-only Realtime trace](notification-session-fencing-2026-09-30/telemetry-trace141.json): phase attribution/disposition still open.
- [Explicit 141 diagnostic](notification-session-fencing-2026-09-30/upgrade141-diagnostic.json) and [notification scoped code checks](notification-session-fencing-2026-09-30/CODE_VALIDATION.md).
- [XLSX packet with source/log drift requiring a fresh run](roster-xlsx-hardening-2026-09-30/README.md) and [previous29 September snapshot](PRODUCTION_REMAINING_TASKS_2026-09-29.md).

The sole UI/UX authority is `revolut-design`, applied through shared tokens/components on mobile, Admin and public web. Appropriate native, Business/operator and marketing references require distinct route/state, interaction, accessibility and owner evidence. No surface is asserted fully matched. The implementation goal remains active.
