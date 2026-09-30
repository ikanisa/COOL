# Collect — exhaustive remaining production tasks

**Snapshot: 30 September 2026 (Africa/Kigali), revision5. Release decision: NO-GO.**

**101 acceptance checks remain open:99 of100 original tasks, plus X01 and X02.** G06 is locally closed. This is an acceptance count; substantial implementation exists within open tasks. Crosscutting checks overlap other tasks.

| Priority | Open | Required disposition |
| --- | ---: | --- |
| P0 |24| Critical release blockers; acceptance before production |
| P1 |71| Required implementation and production acceptance |
| P2 |4| Complete or record a specific accountable deferral |
| Crosscutting |2| Exact-build visual and Rwanda-only scope acceptance |
| **Total** |**101**| All declared task IDs retained |

**Evidence state:**67 Partial,27 External,7 Unverified. Partial means implementation/evidence exists but acceptance is incomplete. External means decisive proof/access/decisions remain external. Unverified means required coverage has not been established. O01 and S08 move to Partial after hosted metadata readback; neither is closed. Named accountable owners remain unverified; responsible roles appear below.

**Source:** HEAD `c2569a47c7f87de68a60c4a247b5c5e3ca640f06` plus 730 captured working-tree entries; capture `2026-09-30T14:22:10.714805+00:00`. No release candidate is frozen.146 migration source files and isolated registry versions are present;143 local tables. Last complete clean replay remains141.

## Latest verified progress and evidence limits

- **X02/D09:** normal-owner143 retirement is locally complete:32 role/immutability checks,6 canary and9 verification races, separate postcommit verification after71.034822seconds, exact reapply and unchanged unrelated jobs/history. Current isolated canonical bank job is inactive. Original productionX02 remains open.
- **A01/A09/D09:**142 failed-fixture recovery restored131 tables;11 races and actual receipts pass.144 adds reload references/drafts/CAS;6 real races restore136 tables. Actual client packet passes91 roster,57 XLSX and1 Chromium storage adapter tests. Full browser lifecycle remains.
- **S04:** corrected145 passes56 SQL checks,9 legacy-v2 upgrade checks and6 actual races. Invalid256-bound regex and test fixture defects were corrected; original failures and exact139-table recovery are preserved.
- **A02/A03/A09:** five-format decoder passes32 real codec/auth/resource cases (including compressed PDF object streams),8 real signed Deno adapter integrations and155 scoped regressions. Corrected146 passes29 budget/permission checks and7 races, including stale-snapshot40001. Actual workbook preview/review/commit/reload and lost cleanup-ACK repair pass. Final current Edge HTTP integration remains; live provider accuracy is unmeasured.
- **S09/U06/P07:** retained Admin280-test/15-analysis packet has214 stable inputs at its capture. Current browser diagnostics verify shipped CSP, configured-origin Auth rebuild and reference-only bookmarks; lifecycle/PWA final acceptance remains. Dated packets are not a frozen whole-system pass.
- **Q01/Q03/Q07/A05:**174 present approved hashes match;194/194 remaining runtime Dart files are reachable,2 proven unused files removed,95 bundled paths classified used. Current public static build passes with honestly labeled browser interface previews. Final asset/lock/native lint/build gates remain. Exact installed Flutter3.44.4 is available; earlier3.44.3 evidence retains its toolchain limitation.
- **O01/S08/X02:** retained hosted metadata has124 migrations;22 current local versions are absent from that retained readback. No fresh hosted calls occurred for revision5. Retained deployed cron/body/security findings may be stale; fresh exact hosted acceptance remains.

[Scoped database consolidation](local-database-runtime-2026-09-30/attempt1/validation.json) binds21 actual runtime packets and222 inputs. It closes local goalL02. Separate [cleanup acceptance](asset-build-hygiene-2026-09-30/L21-verification.json) closes local goalL21;22 local goals remain open. It does not close productionX02 or establish final clean replay146. No new Drive, provider, legal/store or signed-device acceptance was obtained. Sequences were not reset; generated local fixtures do not establish representative customer acceptance.

## Immediate engineering and validation queue

- **A01, A09, D09:** Finish actual browser reload/tab/session recovery, current Edge pairing and final frozen143–146 migration rehearsals; completed142 fixture recovery/receipts/races remain preserved.
- **X02, D09, O01:** Include locally verified143 scheduler retirement in final clean/populated replay and planned hosted rollout; retain current inactive local readback and unchanged jobs/history.
- **O01, S08, F03, F10:** Review full hosted124-to-current rollout; complete body/configuration/privilege readback, realistic upgrade, compatible Edge/client pairing and post-deployment negative tests.
- **A01, P07, A09, U06, U08, S09:** Complete browser-reload roster recovery and actionable terminal errors; extend same-user session-generation fencing and operation-specific ACK validation across generic Admin operations.
- **F10, S09, S08:** Validate authentic evidence intake, deployed MFA/role/session/GoTrue semantics, disputes/reversals and operator acceptance; rerun passing local races after freeze.
- **O05, S10, P07, M08, U05:** Configure/prove unattended hosted notification scheduling, actual APNS/FCM delivery, permission/lifecycle changes, duplicate/dead-letter and session recovery.
- **S03, O04, O08:** Complete trusted end-user bot/network controls, concurrent phone/account/global quotas and approved spend limits.
- **S04:** Complete current145 Edge HTTP integration and deployed/provider evidence; local56+9SQL checks and6 real races are verified.
- **A02, A03, A09:** Finish current Edge HTTP integration for implemented decoder, trustedXLSX, evaluation harness and146 durable budgets; complete final compatible frozen acceptance.
- **O06:** Complete redacted push/receipt/financial queue, lease, ACK, completion and scheduler metrics/alerts; rehearse operator response.
- **Q01, Q03, Q07, A05, A06, A10:** Finish asset reconciliation/affected regressions, exact3.44.4 lock/native lint/build gates and current resolved dependency evidence; preserve dated source-bound packets.
- **U01, Q03, X01:** Resolve five visual differences and missing comparators; complete applicable Revolut route/state, interaction, accessibility and owner review on exact builds.

These are subtasks within the original IDs, not additional count items.

## G — Source and governance: 9 open

**Responsible roles:** Repository/release owner, security owner and engineering lead.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| G01 | P0 | External | Remove broad Drive write/sharing grants from source, configuration and delivery evidence; retain permission readback proving access is limited to approved collaborators. Recheck the 28 September observation. |
| G02 | P0 | External | Preserve revisions/access evidence and establish the actual exposure window, affected material and personal-data scope. Record findings without inferring access from open sharing alone. |
| G03 | P0 | External | Scan Git history, ignored archives and outputs with redacted results; rotate or disable genuinely exposed credentials and prove old credentials no longer work. |
| G04 | P0 | External | Name the release owner and canonical trusted Git origin; verify protected merges/artifact publication despite the earlier protection-API 403. Bind reviewed imports to the trusted source. |
| G05 | P0 | Partial | Include reviewed143–146 in one final clean/populated replay and frozen release candidate; complete compatibility decisions and full candidate validation. |
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
| S04 | P1 | Partial | Corrected145 uncertain-send recovery passes56 local SQL checks,9 v2 upgrade checks and6 real races. Finish current Edge HTTP integration and deployed signed-hook/provider acceptance without blind resend. |
| S05 | P1 | External | Read production Auth/hook settings and exact release configuration; prove reusable test OTP mappings, bypasses and unbounded review accounts are disabled. |
| S06 | P1 | Partial | Test Play Integrity on certificate/version-bound builds: replay, expiry, redemption, quota, outages and unsupported-device behavior, with approved expected outcomes. |
| S07 | P1 | Partial | Extend stable-error verification to deployed gateways, logs, exports and SDK failures. Test a corpus containing secrets, phone data, provider responses and SQL details for leakage. |
| S08 | P1 | Partial | Complete exact hosted schema/column privileges, view definitions, effective roles and SECURITY DEFINER body/owner readback. Review all238 retained advisor findings by caller reachability; run role-by-role anonymous/member/operator/service, cross-group, raw-SMS and concurrent-revocation negative tests in authorized staging. Verify finality/roster helper grants and post-rollout deployed RLS. |
| S09 | P1 | Partial | Verify every sensitive Admin operation against the deployed role/action/step-up matrix, durable audit and immediate role, approval and session revocation. Validate actual GoTrue transaction and whole-transaction retry behavior, configured MFA factors, installed-browser account switching and accessibility. Repeat passing local reconciliation races on the frozen candidate. Extend session-generation fencing and exact operation-specific acknowledgement validation beyond roster to global Admin providers, notification retries and group actions. |
| S10 | P1 | Partial | Validate coordinated server/client deployment and rerun scoped concurrency checks after freeze. Rehearse actual OTP, Integrity, extraction and APNS/FCM outages, quotas, Retry-After, transport/commit uncertainty and bounded retries under representative load. Verify hosted scheduler secrets/configuration and unattended recovery. |

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
| D09 | P1 | Partial | Scoped142 recovery and143–146 runtime checks pass with complete baseline restoration. Complete final frozen clean replay (last complete:141), representative populated124-to-current upgrades, rollback/roll-forward and incompatible-client behavior; preserve historical finances and verify authorized hosted restore. |
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
| U06 | P1 | Unverified | Complete the Admin role-by-route-by-operation-by-data-source matrix with allowed/denied/revoked, loading/empty/failure and audited-result cases. Review user-ID-only global provider keys against same-user Auth session replacement; replace generic null-to-empty RPC success with operation-specific ACK validation where required, including notification retry and group actions. Preserve audit, health, import and support tools; verify actual deployed/browser behavior. |
| U07 | P1 | Partial | Verify deployed public/Admin entrypoints, bundles, environments, authentication, security headers and old caches; public content must not expose private account data. |
| U08 | P1 | Partial | Test deployed PWA warm upgrade, failed updates, offline behavior, multiple tabs, logout, revocation and account switching without stale private content. Include same-user Auth session replacement across generic Admin providers/actions and real multi-tab invalidation; verify private roster draft recovery without stale session data. |
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
| P07 | P1 | Partial | Verify deployed Auth/session141 integration and browser/native private draft, cache, clipboard and export isolation across reload/logout/account switch. Complete signed Android/iOS locked, foreground/background/killed previews, cancellation/taps, permission recovery and real APNS/FCM delivery. Preserve recoverable financial evidence and rerun the frozen integrated release candidate. |
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
| O01 | P0 | Partial | Retained hosted readback contains124 migrations; current local source/isolated registry reaches146 (22 local versions absent from that retained readback). Rehearse final clean/populated coordinated rollout and obtain fresh exact hosted bodies/configuration/grants/Auth/cron/schema readback and post-deployment negative/smoke evidence. |
| O02 | P0 | External | Approve RPO/RTO and demonstrate isolated recovery of the actual database, roles/grants, Auth, configuration and receipt/ledger evidence; reconcile balances and measure recovery time. |
| O03 | P1 | External | Demonstrate Storage-object and external-evidence backup/version recovery separately from database restore, including manifests and effective access policies. |
| O04 | P1 | External | Configure and test actual OTP bot controls for valid, absent, expired and failed challenges without breaking supported WhatsApp/Supabase journeys. |
| O05 | P1 | Partial | Rerun the passing local session/lease/retry scenarios on the frozen integrated candidate. Configure, deploy and activate one governed recurring notification scheduler; prove unattended stale-lease/retry recovery, real provider failures, lost completion ACKs, duplicate/dead-letter handling and representative capacity with operator acceptance. |
| O06 | P1 | Partial | Wire redacted receipt/financial metrics and alerts for queue age, ACK/parse failures, unmatched evidence, reconciliation age and reversals. Add native push queue-age, lease-loss, completion-pending and scheduler-health monitoring; the existing SMS-outbox health function does not cover those push controls. Rehearse operator response. |
| O07 | P1 | External | Run representative user/history/receipt/provider/notification load tests; approve measured p95/p99, capacity, backlog-drain and availability objectives before pilot. |
| O08 | P1 | External | Approve and test OTP, notification, storage and AI cost budgets, per-account/global limits and alerts using measured retry/traffic assumptions. |
| O09 | P1 | Partial | Assign on-call/escalation roles and rehearse provider outage, stuck queue, compromise, corrupt cache, wrong allocation and rollback procedures. |
| O10 | P0 | External | Run a bounded authorized pilot with daily independent reconciliation, support, monitoring and stop/rollback criteria; obtain an evidence-backed accountable GO decision before expansion. |

## A — AI, assets and administration: 10 open

**Responsible roles:** Admin/backend engineer, privacy/security owner, asset owner and release lead.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| A01 | P1 | Partial | 144 recovery/server references and actualSQL-to-Dart receipts pass locally; finish actual browser reload/tabs/lost-response/session recovery and final compatible Edge/Admin source pairing. Verify deployed operator approval/audit/permissions and immutable ACK/replay. |
| A02 | P1 | Unverified | Build a ground-truth evaluation covering scans, multilingual text, duplicate/ambiguous identities and prompt injection; measure error classes and prove safe rejection/correction. |
| A03 | P1 | Partial | Five-format sandbox codec/XLSX verification and corrected146 budgets pass scoped local checks. Finish current Edge HTTP integration and representative final resource acceptance; configure and verify deployed signed decoder/budget/provider behavior. |
| A04 | P1 | External | Verify actual AI vendor retention/store settings, processing geography, consent/legal basis and minimization; obtain vendor/privacy evidence rather than inferring it from request flags. |
| A05 | P2 | Partial | Trace every active asset, font and icon through all builds/references and licenses, including font redistribution rights. Reconcile the seven indexed local asset deletions with the reviewed Git/manifest inventory; establish reachability before further removals. |
| A06 | P2 | Unverified | Resolve the current asset-check failure from seven indexed files deleted locally; 174 approved file hashes match. Verify all approved bytes and dimensions against independent trusted provenance and document intended removals or changed artwork without automatic restoration. |
| A07 | P2 | Unverified | Identify proven unused code/dependencies and prepare a reviewed deletion-only change; run Android/iOS/Admin/public build and route regression before removal is accepted. |
| A08 | P1 | Partial | Inventory mutable runtime settings and product copy; test permissions, validation, versions and audit. Keep stable application strings distinct from governed operator settings. |
| A09 | P1 | Partial | Verified146 workbook→142 preview/review/commit→144 reload passes locally. Complete all export/reveal/grant/retry formula/bounds/redaction/permissions/reason/audit coverage and actual deployed operator workflows on a frozen compatible set. |
| A10 | P1 | Partial | Publish one candidate-bound handover identifying source, deployment, signed artifact hashes, exact tests/exclusions, contacts, approved exceptions and accountable decision. Retain all logs and manifests in the reviewed deliverable or a verified archive; reconcile dependency/asset inventories and historical versus current evidence. |

## X — Crosscutting acceptance checks: 2 open

**Responsible roles:** Product/design owner and accountable release owner.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| X01 | Crosscutting | Partial | Resolve all five retained visual differences; obtain valid reference coverage or explicitly reviewed adaptations, then bind route/state, interaction, accessibility and owner annotations to the exact installed/browser build. Missing original references remain an evidence gap. |
| X02 | Crosscutting | Partial | Normal-owner143 scheduler retirement passes locally with immutable postcommit evidence,32 checks and15 races; current isolated canonical job is inactive. Verify authorized hosted bank cron/handler/external schedule retirement, Rwanda-only scope, historical audit access, wording and post-deployment upgrades. |

## Dependency order and closure rule

1. **Source/accountability:** G01–G04,G09–G10,P06; assign named environment, signing, store, legal, finance and operations owners.
2. **Security/financial policy:** S01–S10,F01–F10; approve finality, expiry, queue capacity, retention, MFA and budgets.
3. **Integrated data/source:** integrate verified143–146, finish browser/Edge pairing, rehearse124-to-current upgrade; D01–D10,A01–A09,O01/S08. Freeze G05 and resolve/build Q01–Q03/Q05; regenerate Q07 from that candidate.
4. **Actual surfaces:** signed Q04; installed M01–M10; U01–U10/X01/X02; approved P01–P10; deployed O01/O03–O09/Q08.
5. **Rehearsal/release:** Q10,O02,O09; bounded independently reconciled O10 pilot; G07/Q09/A10 provenance and accountable GO/NO-GO.

Every closure requires integrated source, stated cases in the required environment, retained source/configuration/artifact/date evidence and accountable acceptance of policy or a permitted deferral. Source changes require affected reruns. External gates can proceed alongside engineering.

## Evidence index and preserved definitions

- [Machine-readable register](production-remaining-tasks-2026-09-30.json):102 original IDs/criteria,101 open tasks, priorities, roles, remaining work, current evidence and evidence history.
- [Register validation](production-remaining-tasks-2026-09-30.validation.json).
- [Original criteria](PRODUCTION_READINESS_REMAINING_TASKS_2026-09-28.md) and [dated implementation audit](PRODUCTION_TASK_IMPLEMENTATION_AUDIT_2026-09-28.md).
- [notification-session-fencing-2026-09-30/upgrade141-reviewed-verification.json](notification-session-fencing-2026-09-30/upgrade141-reviewed-verification.json).
- [notification-session-fencing-2026-09-30/concurrency141.json](notification-session-fencing-2026-09-30/concurrency141.json).
- [notification-session-fencing-2026-09-30/clean141-verification.json](notification-session-fencing-2026-09-30/clean141-verification.json).
- [roster-import-provenance-2026-09-30/apply142.json](roster-import-provenance-2026-09-30/apply142.json).
- [roster-import-provenance-2026-09-30/rollback142.json](roster-import-provenance-2026-09-30/rollback142.json).
- [roster-import-provenance-2026-09-30/concurrency142-execution.json](roster-import-provenance-2026-09-30/concurrency142-execution.json).
- [admin-roster-provenance-2026-09-30/validation.json](admin-roster-provenance-2026-09-30/validation.json).
- [roster-provenance-edge-postreview-2026-09-30/verification.json](roster-provenance-edge-postreview-2026-09-30/verification.json).
- [hosted-readback-2026-09-30/migration-drift.json](hosted-readback-2026-09-30/migration-drift.json).
- [hosted-readback-2026-09-30/catalog-readback.json](hosted-readback-2026-09-30/catalog-readback.json).
- [hosted-readback-2026-09-30/SECURITY_TRIAGE.md](hosted-readback-2026-09-30/SECURITY_TRIAGE.md).
- [142 guarded recovery source handoff](roster-import-provenance-2026-09-30/RECOVERY_SOURCE.md): historical source handoff; successful runtime recovery is linked in the current consolidation.
- [Admin scope and limitations](admin-roster-provenance-2026-09-30/README.md) and [Edge scope and limitations](roster-provenance-edge-postreview-2026-09-30/README.md).
- [Historical drifted XLSX packet](roster-xlsx-hardening-2026-09-30/README.md).

The sole UI/UX authority is `revolut-design`, implemented through shared tokens/components across mobile, Admin and public web. Native, Business/operator and marketing comparators require their applicable route/state, interaction, accessibility and owner evidence. No surface is asserted fully matched. The full implementation goal remains active.
