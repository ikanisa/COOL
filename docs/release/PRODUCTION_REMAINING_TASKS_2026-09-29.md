# Collect — all remaining production tasks

**Snapshot: 29 September 2026. Release decision: NO-GO.** This reconciles all 100 original task IDs and both crosscutting checks against the current implementation audit and subsequent source review. **99 original tasks remain open, plus X01 and X02: 101 open acceptance checks.** G06 is locally complete. The current checkout is based on `c2569a47c7f87de68a60c4a247b5c5e3ca640f06` with extensive uncommitted work; that commit alone does not identify the implementation reviewed here.

| Open priority | Count | Meaning |
| --- | ---: | --- |
| P0 | 24 | Critical release requirements |
| P1 | 71 | Required before production unless an accountable scope decision explicitly permits otherwise |
| P2 | 4 | Complete or obtain an accountable, recorded deferral |
| Crosscutting | 2 | Overlapping acceptance checks, not additional original task IDs |
| **Total** | **101** | Open until closure evidence is accepted |

**Evidence census:** 65 Partial, 29 External and seven Unverified, including X01/X02. Across the original 100 rows alone: 63 Partial, 29 External, seven Unverified and one Local. The older goal attachment's nine-unverified split is superseded by this census.

- **Partial:** local code, tests or documentation exist; required implementation or acceptance evidence remains incomplete.
- **External:** decisive evidence needs authorized infrastructure access, signed artifacts, supported devices, provider/store evidence or an accountable decision. This does not mean all associated local work is finished.
- **Unverified:** the available evidence does not establish the required behavior.
- **Local:** the requested repository change is present; this label alone does not approve production.

These are acceptance counts, not a percentage of engineering left to implement. Responsibilities below name the roles needed; they are not claims that named people have accepted assignments. G10 must supply accountable names and dates.

## What has progressed, and what remains exposed

The earlier [financial concurrency packet](financial-concurrency-2026-09-29/README.md) was followed by a [content-binding correction](financial-content-binding-2026-09-29/README.md): three defects were reproduced on migration 135, migration 136 corrected normalized replay and rejection identity, and 78 adversarial checks passed. A new **138/138 clean replay**, duplicate SMS, identical finality and balanced reversal races passed. A separate same-confirmation/different-evidence race on 137 produced one winner and one rejected conflict. These remain synthetic local results.

The [latest full Flutter packet](full-flutter-check-2026-09-29/README.md) still records **1,378 passed and five failed historical visual comparisons**; device integration tests were excluded. The five differences concern authentication, contribution entry, connection recovery, public home and Admin overview. No new full Flutter or signed-device run is claimed by the subsequent backend work.

The [notification recovery packet](notification-fencing-2026-09-29/README.md) now records migrations 137–138, versioned claims, token/attempt fencing, token-owner protection, exhaustion recovery and aligned Admin retry eligibility. **52 rollback SQL checks**, a real two-session claim/reassignment test, and **22 focused tests under pinned Deno 2.5.6** passed. Provider-specific backoff, real outages, scheduler/device/provider evidence and operating acceptance remain open.

The [roster packet](roster-input-response-hardening-2026-09-29/README.md) records bounded input framing, bounded upstream responses, strict AI output validation and preview-only behavior. **51 tests and entrypoint type checking passed under pinned Deno 2.5.6.** Full codec/PDF/animation expansion controls, durable account quotas, real vendor validation, model evaluation and source/approver audit remain open. No live provider call or hosted mutation was made.

The last recorded release gate has seven blockers: current approval evidence, mobile release validation, Android artifacts, Android signing review, Admin PWA live validation, linked Supabase SMS-first UAT and release-owner signoff. This report did not refresh hosted, Drive-permission, store or provider state. The wider 101-item register remains applicable even if that narrower gate later passes.

## Current register review

The 29 September source review reconciled all 102 IDs and rechecked 86 financial, notification and roster manifest entries with no hash differences. It also identified explicit implementation work in S03/S04/F10, notification wake-up deadlines and recurring dispatch, and XLSX expansion limits before workbook decoding. The supply-chain inventory check currently fails because its generated inventory is stale. The asset checker reports 174 matching approved hashes and seven indexed files deleted locally, so its inventory check also fails; reconcile intended deletions through review. These findings remain within existing IDs and do not increase the task count. Ignored test logs need deliberate inclusion in the final candidate or a verified evidence archive. No new full test suite or external-service verification was performed for this register refresh.

## Implementation findings and remaining acceptance

These are subrequirements of existing IDs, not extra tasks added to the count. The financial defects were reproduced before correction; the notification draft failure was retained, corrected and followed by clean replay. Passing local checks do not close their parent acceptance tasks.

| Task | Current correction | Remaining acceptance |
| --- | --- | --- |
| F08 | Confirmation replay now compares transaction, receiver, amount, event time and evidence; sequential adversarial cases and a same-ID conflicting-evidence race pass. | Representative historical/provider scenarios and deployed readback. |
| F08 | A server-computed normalized input digest binds request replay; historical missing digests fail closed without invented backfill. | Coordinate real service callers and governed legacy-request reconciliation. |
| F08/F10 | Rejections now bind the full candidate identity and immutable rejection record; compensation cannot masquerade as rejection replay. | Real evidence authenticity, historical variants and complete operational workflow. |
| F10/D09/S08 | Staged finalizer lock ordering and nonfinite evidence times are corrected in source; migration 136 preserves existing execution revocations. | Execute full maker/checker, actor revocation, wrapper/direct concurrency and deployment-order ACL scenarios. |
| O05/S09/P07 | Token-owner checks and live-claim reassignment protection pass SQL and two-session tests. | Installed account switching, real push delivery and in-flight privacy behavior. |
| O05/S10 | Completion requires the exact claim token/attempt; old workers fail at the required claim protocol. | Coordinated hosted rollout, actual delayed workers and provider outages. |
| O05 | Exhausted stale claims become terminal; authenticated Admin retry preserves attempt history and counts only eligible deliveries. | Scheduler/dead-letter operations, support drills and representative workload. |
| O05/S10 | Accepted FCM response-body failures no longer automatically become send retries. | Provider Retry-After, jitter, real acceptance uncertainty and throughput policy. |
| A03/O08 | File framing/byte limits, strict AI schema and preview-only output pass 51 pinned-runtime tests. | Full decoding/page/animation expansion limits, durable concurrent account budgets and actual vendor validation. |

See the [financial](financial-content-binding-2026-09-29/README.md), [notification](notification-fencing-2026-09-29/README.md) and [roster](roster-input-response-hardening-2026-09-29/README.md) packets for exact sources, results and limitations.

## G — Source and governance: nine open

**Responsible roles:** repository/release owner, security owner and engineering lead. Source protection can proceed alongside local implementation; freeze the release candidate after its selected corrections are integrated.

| ID | Priority | Evidence | Remaining work and closure proof |
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

**G06 — locally complete:** the retired repository design rule was removed and `revolut-design` is the sole UI/UX authority. U01 and X01 remain open; no extra scoring rule is to be reintroduced.

## S — Authentication and security: ten open

**Responsible roles:** security lead, backend/authentication engineer and Admin owner. Deployed closure depends on O01 and the signed candidate where applicable.

| ID | Priority | Evidence | Remaining work and closure proof |
| --- | --- | --- | --- |
| S01 | P0 | Partial | Obtain security, finance and operations review of the complete receipt-to-ledger threat model, including the newly found finality and notification boundaries; verify deployed functions, callers and provider trust. |
| S02 | P1 | Partial | Stage the real OTP hook and prove malformed, unsupported-country and invalid Rwanda numbers fail before reservation/provider calls; valid supported numbers must authenticate. |
| S03 | P1 | Partial | Implement or configure trusted end-user source/network and bot controls before the signed OTP hook; the hook caller IP is not the end-user IP. Approve per-phone/global spend limits and test concurrent reservations, bypasses and safe throttling. |
| S04 | P1 | Partial | Implement evidence-based recovery for reserved-but-unresolved OTP sends without blindly resending an uncertain delivery. Verify actual signed hook configuration, signature checks, stale/replayed requests and the complete recovery procedure. |
| S05 | P1 | External | Read production Auth/hook settings and exact release configuration; prove reusable test OTP mappings, bypasses and unbounded review accounts are disabled. |
| S06 | P1 | Partial | Test Play Integrity on certificate/version-bound builds: replay, expiry, redemption, quota, outages and unsupported-device behavior, with approved expected outcomes. |
| S07 | P1 | Partial | Extend stable-error verification to deployed gateways, logs, exports and SDK failures. Test a corpus containing secrets, phone data, provider responses and SQL details for leakage. |
| S08 | P1 | External | Export actual hosted grants, RLS and security-definer functions; test every role, cross-group ID, receiver/operator/service action and concurrent revocation. Verify finality helper grants and migration-order effects. |
| S09 | P1 | Partial | Complete the deployed Admin role/action matrix, step-up policy and sensitive-action audit; prove approval/role/session revocation takes effect during concurrent UI and server actions. |
| S10 | P1 | Partial | Add explicit deadlines to notification enqueue/wake-up calls and reject dispatch redirects; implement provider Retry-After and jitter. Rehearse OTP, Integrity, parsing and push outages, bounded side effects, quotas, throughput and coordinated hosted rollout. |

## F — Financial correctness and receipt custody: ten open

**Responsible roles:** financial-control owner, backend/ledger engineer, Android engineer and reconciliation operator. Independent provider evidence and approved policy are required for finality.

| ID | Priority | Evidence | Remaining work and closure proof |
| --- | --- | --- | --- |
| F01 | P0 | Partial | Approve requested, handed-off, SMS-observed, reconciled and final meanings; align DB, Edge, Android, Dart and all financial wording. Test the coordinated rollout and commit-timeout/account-switch boundaries. |
| F02 | P0 | External | Prove an authorized independent provider/statement reconciliation path or an explicitly approved constrained finality policy, including exceptions, corrections and reversals. Verify source authenticity before final posting claims. |
| F03 | P0 | Partial | Run missing/null/unsupported/future receipt-contract cases against deployed handlers and mixed client versions; verify no mutation, actionable alerts and safe coordinated rollout. |
| F04 | P0 | Partial | On installed devices, prove only an exact durable, current-owner server ACK deletes the corresponding envelope; test no-op/malformed success, wrong owner, transport/commit timeout and consent/account-switch races. |
| F05 | P1 | Partial | Exercise transient/permanent Keystore failure, corrupt ciphertext, quarantine, reinstall and support recovery on physical devices; transient faults must retain recoverable evidence. |
| F06 | P1 | Partial | Approve queue capacity and overflow policy; test 100/101 boundaries, bursts and prolonged offline use with persistent attention signals and recoverable evidence. |
| F07 | P1 | Partial | Decide late-upload/expired-intent/grace and clock-skew policy; align SQL and operator wording, then test before/at/after expiry, delayed upload and concurrent workers without device-only final credit. |
| F08 | P1 | Partial | Extend the locally verified replay/rejection correction to representative historical and authenticated provider cases, cross-payment duplicate references, delayed events and reversal variants; verify deployed definitions and balanced journals. |
| F09 | P1 | Partial | Extend exact confirmed-payer matching to concurrent candidates, duplicate memberships and deployed/provider identity; ambiguous or conflicting evidence must enter the governed exception process without automatic credit. Validate historical remediation. |
| F10 | P1 | Partial | Implement and wire the operator maker/checker UI, immutable evidence audit and trusted finalization runner. Execute full-schema proposal/approval, independent actors, expiry/revocation, wrapper/gateway lock order, both deployment-order ACL scenarios, finite evidence times and Admin dispute flows; authenticate real evidence. |

## D — Database and data integrity: ten open

**Responsible roles:** database/backend engineer and data/QA lead. Use representative isolated data before authorized deployment and readback.

| ID | Priority | Evidence | Remaining work and closure proof |
| --- | --- | --- | --- |
| D01 | P1 | Partial | Capture representative history plans for all sorts, scopes and first/middle/deep pages; compare old/new paths and repeated p95/p99, buffers and scan growth against approved limits. |
| D02 | P1 | Partial | Finish relational keyset performance/authorization validation and hosted RPC/index readback. Verify page depth avoids whole-history JSON reconstruction; measure remaining total/revision scans. |
| D03 | P1 | Partial | Test client and installed-app handling of posting, governed reversal, privacy/membership changes and concurrent reads; require consistent totals/revisions or explicit refresh, including hosted RLS. |
| D04 | P1 | Partial | Validate bounded recent-intent and notification work at representative multi-actor/receiver volumes; compare previous paths, measure exact totals and migration/index timing, and read back deployed definitions. |
| D05 | P1 | Partial | Test all ownership totals against server-authored immutable identity, forged labels, name/phone-suffix collisions and cached payloads. |
| D06 | P1 | Partial | Exercise every history/group/ledger consumer with complete, absent, stale and zero server summaries; a partial page must never be presented as a complete financial total. |
| D07 | P1 | Partial | Run every Admin paged RPC through client/database contracts: boundaries, filters, exact totals, last-page shrink, deterministic concurrent ordering, country scope and role denial. |
| D08 | P1 | Partial | Audit all modern/legacy financial inputs and actual RPC/cache payloads for exact integer bounds, aliases, identifiers, timezone/calendar validity and preserved valid historical values. |
| D09 | P1 | Partial | Rehearse representative historical data through all 138 current migrations; validate staged reconciliation, old installed clients, rollback/roll-forward and authorized hosted recovery while preserving balances, receipts and effective grants. |
| D10 | P1 | Partial | Test deployed Realtime reconnect/missed/duplicate messages, offline revocation and account switches under load; verify bounded refresh and no wrong-account cached data. |

## M — Native app, devices and stores: ten open

**Responsible roles:** mobile engineer, device QA and store account owner. Installed acceptance depends on Q04; provider cases require real supported networks.

| ID | Priority | Evidence | Remaining work and closure proof |
| --- | --- | --- | --- |
| M01 | P0 | External | Obtain the exact Android package/version restricted-SMS permission decision, release disclosure and core-use evidence; retain actual Play readback tied to signed artifact hashes. |
| M02 | P1 | Partial | Verify real SMS capture and authenticated drain through process death, reboot, Doze, offline recovery and force stop; record OS limits and retained pending evidence. |
| M03 | P1 | Partial | Run one valid/malformed multipart/provider SMS corpus against native capture and server receipt bounds; prove matching decisions at each boundary. |
| M04 | P1 | Partial | Test sign-out and account-switch races at every async native queue/permission boundary on devices; retain old-owner ciphertext and prevent cross-account drain. |
| M05 | P1 | Unverified | Exercise release-build backup, restore, reinstall, permanent key loss and consent revocation; prove no raw-SMS leakage and documented recovery behavior. |
| M06 | P1 | Partial | Validate truthful Android/iOS capabilities and complete group, membership, contribution and receipt journeys; unsupported operations must have useful explanations/recovery. |
| M07 | P1 | External | Inspect the signed iOS archive's merged app/SDK privacy manifests, required-reason APIs, entitlements, APNS environment and associated domains. |
| M08 | P1 | Partial | Run installed links, QR and notification navigation for fresh install, signed-out, wrong account/group, revoked membership, expired and malformed input. Preserve authorization throughout recovery. |
| M09 | P1 | External | Run MTN/Airtel real-SIM USSD tests including dual-SIM, cancellation, route changes, invalid receiver and return to app; launch must never be reported as payment success. |
| M10 | P1 | External | Record crash/ANR, memory-pressure, thermal, long-session and background baselines on minimum supported physical devices and exact release versions. |

## U — Member experience, Admin and public web: ten open

**Responsible roles:** product/design owner, mobile/web engineers and accessibility QA. `revolut-design` is the only design authority; native, public marketing and Admin/operator comparators remain distinct.

| ID | Priority | Evidence | Remaining work and closure proof |
| --- | --- | --- | --- |
| U01 | P1 | Partial | Review all material mobile/Admin/public routes and loading, empty, failure, geography, membership, responsive and accessibility states against verified applicable references. Resolve differences and obtain owner review on the exact build. |
| U02 | P1 | Partial | Test compact 320×568 layouts, 2× text and real keyboards through validation and submission; retain focus and reachability of every required action. |
| U03 | P1 | Partial | Complete actual TalkBack, VoiceOver and desktop keyboard tasks, including labels, focus, errors, dialogs, tables and sensitive/destructive controls. |
| U04 | P1 | Partial | Finish consistent Kinyarwanda/English financial terminology on every visual and spoken route; distinguish pending, observed, confirmed, unavailable, stale and genuine zero. |
| U05 | P1 | Partial | Review rendered offline/recovery states using real data/queue conditions; failed refresh must remain truthful, retry must work and persistent receipt attention must remain visible. |
| U06 | P1 | Unverified | Walk every declared Admin route and operation with its intended role, actual data source and authorization; preserve necessary audit, health, import and support tools. |
| U07 | P1 | Partial | Verify deployed public/Admin entrypoints, bundles, environments, authentication, security headers and old caches; public content must not expose private account data. |
| U08 | P1 | Partial | Test deployed PWA warm upgrade, failed updates, offline behavior, multiple tabs, logout, revocation and account switching without stale private content. |
| U09 | P2 | Unverified | Run representative Rwanda-member comprehension tests in Kinyarwanda and English for money destination, status and recovery; document findings and corrections or approved deferral. |
| U10 | P1 | Unverified | Profile layout/rebuild/raster/compositing costs on representative minimum devices; fix measured hotspots and verify lazy rendering before further structural redesign. |

## P — Privacy and legal readiness: ten open

**Responsible roles:** accountable business owner, qualified counsel/privacy lead and security owner. The following require evidence and decisions about actual product behavior, vendors and data flows.

| ID | Priority | Evidence | Remaining work and closure proof |
| --- | --- | --- | --- |
| P01 | P0 | External | Obtain a reviewed regulatory classification, partner-role assessment and permitted claims for the actual Rwanda money/receipt/credit-readiness flows; record required authorizations or supported scope decisions. |
| P02 | P0 | External | Establish and evidence responsible entity, controller/processor roles, registration status, privacy/DPO contacts and a complete processing inventory. |
| P03 | P0 | External | Verify actual hosting, backup, logs and AI processing locations; obtain the required transfer/storage determination and supporting grounds. |
| P04 | P1 | External | Complete processor/vendor and subprocessor diligence, agreements, purpose limits, retention and incident obligations for cloud, messaging, AI and support services. |
| P05 | P1 | Partial | Approve and implement minimization, retention, deletion and legal holds by data class, including raw receipts, hashes, journals, evidence, caches and analytics. |
| P06 | P0 | External | Complete evidence-led exposure and reportability assessment, timeline and required actions with accountable security/privacy review. Open sharing alone is not proof of data access. |
| P07 | P1 | Partial | Implement current-session/recipient checks before foreground push display and a minimized-payload/cancellation policy; test accepted delayed pushes across account switches on devices. Test native/browser caches, sessions, clipboard, exports and previews through logout, lock and reinstall while preserving recoverable financial evidence. |
| P08 | P1 | Partial | Demonstrate account deletion from reauthentication and status tracking through server/vendor/device cleanup, with a truthful explanation and controlled access for lawfully retained records. |
| P09 | P1 | External | Reconcile consent, SMS/payer-data disclosures, AI use and store privacy declarations with exact signed behavior and the approved legal basis. |
| P10 | P1 | Partial | Approve and rehearse auditable disputes, correction entries, support, legal-hold and deletion-exception procedures; distinguish app records from provider funds. |

## Q — Builds, QA and provenance: ten open

**Responsible roles:** release/build engineer, QA lead and security/supply-chain reviewer. Final runs must share one protected source revision and its exact artifacts.

| ID | Priority | Evidence | Remaining work and closure proof |
| --- | --- | --- | --- |
| Q01 | P0 | Partial | Resolve unchanged locks on the exact pinned SDK from a frozen clean checkout; complete native/iOS/Edge dependency locking and fork provenance/distribution-rights review. Reconcile the currently stale candidate inventory. Pinned Deno 2.5.6 roster verification is already retained locally. |
| Q02 | P0 | Partial | Repeat non-writing formatting and full Flutter/native/generated-source/release-variant analysis on the frozen candidate; resolve or explicitly disposition all warnings, including the 40 recorded Android lint warnings. |
| Q03 | P0 | Partial | Resolve the five visual failures through reviewed references, then run complete Flutter, native, Edge, database and installed/browser integration suites on one candidate. Retain exclusions and actual logs. |
| Q04 | P0 | External | Produce signed production AAB/APK and scoped iOS archive; verify configuration, version, signatures, merged permissions and hashes, then install/test those exact bytes. Resolve missing signing material through its owner. |
| Q05 | P0 | Partial | Build clean public and Admin release artifacts with correct public configuration and fresh required screenshots; verify candidate hashes, deployed auth/route separation, headers, warm update and offline/logout behavior. |
| Q06 | P1 | Partial | Define and measure critical-path negative/concurrency coverage and mutation expectations for auth, receipt ACK, allocation/finality/reversal and account switching. An aggregate coverage floor alone is insufficient. |
| Q07 | P1 | Partial | Reconcile and regenerate the currently stale candidate inventory from reviewed frozen source; finish iOS/Edge/native graphs and signed-artifact SBOMs. Review advisories, licenses, image/font redistribution and fork provenance; validate the resulting inventory. |
| Q08 | P1 | External | Verify hosted production-readiness workflow execution, trusted refs, isolated PR credentials, protected environments, reviewer requirements and retained build/check evidence. |
| Q09 | P1 | Partial | Bind signed artifacts to the protected commit, locks, toolchain and actual test runs with independently retained provenance and hash readback. |
| Q10 | P0 | External | Rehearse high-risk member/Admin/receipt-to-ledger journeys and app/backend rollback or roll-forward using the exact signed candidate; preserve pending receipts, balances and compatibility. |

## O — Operations and release: ten open

**Responsible roles:** platform/SRE owner, support/reconciliation operators and accountable release owner. Pilot requires the applicable financial, legal, store, device and recovery gates.

| ID | Priority | Evidence | Remaining work and closure proof |
| --- | --- | --- | --- |
| O01 | P0 | External | Read back the authorized target project, migrations, function versions, grants/RLS, advisors and configuration with timestamps; resolve drift before deploying or relying on behavior. |
| O02 | P0 | External | Approve RPO/RTO and demonstrate isolated recovery of the actual database, roles/grants, Auth, configuration and receipt/ledger evidence; reconcile balances and measure recovery time. |
| O03 | P1 | External | Demonstrate Storage-object and external-evidence backup/version recovery separately from database restore, including manifests and effective access policies. |
| O04 | P1 | External | Configure and test actual OTP bot controls for valid, absent, expired and failed challenges without breaking supported WhatsApp/Supabase journeys. |
| O05 | P1 | Partial | Establish and verify recurring dispatch so due retries and stale claims recover without a new notification. Validate hosted claim fencing, ownership, scheduler/provider failures and device account changes; complete audited dead-letter support and representative capacity/operating evidence. |
| O06 | P1 | Partial | Wire redacted receipt/financial metrics and alerts for queue age, ACK/parse failures, unmatched evidence, reconciliation age and reversals. Add native push queue-age, lease-loss, completion-pending and scheduler-health monitoring; the existing SMS-outbox health function does not cover those push controls. Rehearse operator response. |
| O07 | P1 | External | Run representative user/history/receipt/provider/notification load tests; approve measured p95/p99, capacity, backlog-drain and availability objectives before pilot. |
| O08 | P1 | External | Approve and test OTP, notification, storage and AI cost budgets, per-account/global limits and alerts using measured retry/traffic assumptions. |
| O09 | P1 | Partial | Assign on-call/escalation roles and rehearse provider outage, stuck queue, compromise, corrupt cache, wrong allocation and rollback procedures. |
| O10 | P0 | External | Run a bounded authorized pilot with daily independent reconciliation, support, monitoring and stop/rollback criteria; obtain an evidence-backed accountable GO decision before expansion. |

## A — AI, assets and administration controls: ten open

**Responsible roles:** Admin/backend engineer, privacy/security owner, asset owner and release lead.

| ID | Priority | Evidence | Remaining work and closure proof |
| --- | --- | --- | --- |
| A01 | P1 | Partial | Verify the full roster preview-to-commit path: validated human approval, immutable source/approver audit, permission checks and no model-authorized membership or money mutation. |
| A02 | P1 | Unverified | Build a ground-truth evaluation covering scans, multilingual text, duplicate/ambiguous identities and prompt injection; measure error classes and prove safe rejection/correction. |
| A03 | P1 | Partial | Complete bounded image/PDF decoding and page/animation expansion controls, plus durable concurrent per-account/global budgets. Add XLSX ZIP/XML/shared-string, sheet/cell and decoded-size limits before workbook allocation. The 51 pinned-runtime roster tests cover existing framing/output controls; actual deployed/vendor validation remains. |
| A04 | P1 | External | Verify actual AI vendor retention/store settings, processing geography, consent/legal basis and minimization; obtain vendor/privacy evidence rather than inferring it from request flags. |
| A05 | P2 | Partial | Trace every active asset, font and icon through all builds/references and licenses, including font redistribution rights. Reconcile the seven indexed local asset deletions with the reviewed Git/manifest inventory; establish reachability before further removals. |
| A06 | P2 | Unverified | Resolve the current asset-check failure from seven indexed files deleted locally; 174 approved file hashes match. Verify all approved bytes and dimensions against independent trusted provenance and document intended removals or changed artwork without automatic restoration. |
| A07 | P2 | Unverified | Identify proven unused code/dependencies and prepare a reviewed deletion-only change; run Android/iOS/Admin/public build and route regression before removal is accepted. |
| A08 | P1 | Partial | Inventory mutable runtime settings and product copy; test permissions, validation, versions and audit. Keep stable application strings distinct from governed operator settings. |
| A09 | P1 | Partial | Bound XLSX ZIP/XML/shared-string expansion and sheet/cell allocation before decoding; the current row limit is applied too late for that protection. Test imports/exports and sensitive reveals for formula injection, limits, redaction, reason/consent, grants, retries and server-side audit. |
| A10 | P1 | Partial | Publish a handover bound to one source/deployment/artifact set with test scope, approved exceptions, contacts and accountable release decision. Deliberately retain ignored test logs in the candidate or verified archive, and reconcile the dependency/asset inventories. |

## X — Crosscutting acceptance: two open

| ID | Priority | Evidence | Remaining work and closure proof |
| --- | --- | --- | --- |
| X01 | Crosscutting | Partial | Resolve all five retained visual differences; obtain valid reference coverage or explicitly reviewed adaptations, then bind route/state, interaction, accessibility and owner annotations to the exact installed/browser build. Missing original references remain an evidence gap. |
| X02 | Crosscutting | Partial | Verify Rwanda-only RWF/MTN/Airtel MoMo scope across deployed routes, public/support/privacy/store material and historical-data access. Prove representative upgrade retention without restoring retired capabilities to the active product. |

## Dependency order and closure rule

1. **Protect source and establish accountability:** G01–G04, G09–G10 and exposure work in P06. Obtain authorized environment access for O01 and identify legal, store, provider and device owners in parallel.
2. **Finish local correctness and product decisions:** resolve the concrete engineering findings above, S01, F01–F10, database/data issues and remaining Admin/AI/privacy controls. Approve policies that determine behavior before final implementation.
3. **Validate the complete integrated candidate:** representative upgrades and restores, mixed-client rollout and authorization; integrate reviewed fixes, freeze G05, and run pinned clean builds and full Q01–Q03/Q05 checks. Any subsequent source correction invalidates affected earlier candidate evidence.
4. **Complete exact-artifact and external acceptance:** signing, stores, real devices/providers, deployed web/Admin/PWA, visual/accessibility review, legal/privacy, operating objectives/budgets and incident drills. Reconcile all evidence to the same candidate.
5. **Pilot and accountable release:** Q10/O10, final G07/Q09/A10 evidence packet and explicit GO/NO-GO. No release claim follows merely from a local test count or populated manifest.

Close a task only when its implementation is integrated, its stated acceptance cases pass in the required environment, evidence identifies source/configuration/artifacts and date, and its accountable owner accepts any required policy or permitted deferral. Keep blocked external cases open while continuing independent engineering work.

## Evidence and scope

- [Original detailed acceptance register](PRODUCTION_READINESS_REMAINING_TASKS_2026-09-28.md): task definitions and acceptance criteria retained.
- [Implementation audit](PRODUCTION_TASK_IMPLEMENTATION_AUDIT_2026-09-28.md): per-ID implementation and evidence history.
- [Machine-readable snapshot](production-remaining-tasks-2026-09-29.json): all 102 IDs, statuses, priorities, closure work and original acceptance criteria.
- [Financial concurrency evidence](financial-concurrency-2026-09-29/README.md) and [full Flutter result](full-flutter-check-2026-09-29/README.md): bounded historical test results, not a claim of new full-suite execution for this report.

This is an exhaustive reconciliation of the declared register and findings available at this snapshot. It does not assert discovery of every possible defect or current external-service state. The broader implementation goal remains active.
