# Collect — exhaustive remaining production tasks

**Snapshot: 30 September 2026 (Africa/Kigali), revision4. Release decision: NO-GO.**

**101 acceptance checks remain open:99 of100 original tasks, plus X01 and X02.** G06 is locally closed. This is an acceptance count; substantial implementation exists within open tasks. Crosscutting checks overlap other tasks.

| Priority | Open | Required disposition |
| --- | ---: | --- |
| P0 |24| Critical release blockers; acceptance before production |
| P1 |71| Required implementation and production acceptance |
| P2 |4| Complete or record a specific accountable deferral |
| Crosscutting |2| Exact-build visual and Rwanda-only scope acceptance |
| **Total** |**101**| All declared task IDs retained |

**Evidence state:**67 Partial,27 External,7 Unverified. Partial means implementation/evidence exists but acceptance is incomplete. External means decisive proof/access/decisions remain external. Unverified means required coverage has not been established. O01 and S08 move to Partial after hosted metadata readback; neither is closed. Named accountable owners remain unverified; responsible roles appear below.

**Source:** HEAD `c2569a47c7f87de68a60c4a247b5c5e3ca640f06` plus 635 working-tree entries; capture `2026-09-29T23:19:46.844766+00:00`. No release candidate is frozen. 143 migration source files are present; isolated registry reaches142, last complete clean replay141. Correction143 is source work in progress.

## Latest verified progress and evidence limits

- **D09/O05/S10:** complete clean141 replay and strengthened notification-session concurrency pass. All124 scoped table/control fingerprints are restored after the race. Reviewed141 telemetry disposition preserves560 original events and financial evidence; original phase-XID attribution remains an explicit limitation.
- **A01/A09/D09:** corrected142 applies on clean141 and96 SQL assertions pass with129 table fingerprints restored. The first142 concurrency attempt failed cleanup; eight synthetic sources/five commits remain on the isolated fixture. Backup, failed source and logs are preserved; guarded recovery, corrected rerun and actual SQL-to-Dart receipt testing remain.
- **A01/A03/A09:** current Admin130 tests and13-file analysis pass, with23 source inputs matching. Current Edge125 Deno plus55 separate HTTP tests pass with37 source inputs matching. These scopes overlap other checks and are not summed as whole-system coverage. Admin golden updates capture synthetic states; they do not establish reference parity.
- **O01/S08/X02:** read-only hosted Supabase metadata verifies124 migrations. The retained comparison covered142 local versions (18 missing); current source now includes unfinished143, making19 local versions absent from the retained hosted readback. There are11 deployed functions and no reconciliation-finalize.139 tables,151 policies,282 routines and238 advisor findings are retained. This is metadata/static triage; exact hosted bodies, API schema settings and negative-role acceptance remain.
- **X02/O01:** hosted daily bank reconciliation remains active. Client-bank grant revocation in127 does not retire owner-run cron. Correction143 must be reviewed, tested and deployed while preserving historical evidence; no hosted changes have occurred.
- **A03/A09/P07:** full codec expansion/resource budgets, XLSX transformation verification and browser-reload draft recovery remain. The roster draft is private but memory-only; no cross-reload recovery is claimed.
- **Q01/Q03/Q07/A05/A06:** seven indexed asset deletions and stale dependency inventory remain from the retained checks.174 present approved asset hashes matched at that check. The older XLSX packet has source and two log-hash drift; current source/lock/log-matched integration and freeze remain.
- **F10/S09:** retained five reconciliation races and integrated58 assertions remain local synthetic evidence. Current reconciliation UI source drift in Admin runtime/repository files requires an affected integrated rerun; its48 artifacts remain intact.

No new Drive permission, legal/store, provider or signed physical-device acceptance was obtained. PostgreSQL sequence allocations are not restored by rollback. Original populated financial fixtures are preserved in verified backups; clean141/142 is not representative customer data.

## Immediate engineering and validation queue

- **A01, A09, D09:** Review/rehearse/apply exact failed142 fixture recovery; prove baseline restoration; rerun corrected concurrent roster tests and actual SQL-to-Dart receipts. Preserve failed source/logs and original backup.
- **X02, D09, O01:** Finish correction143, prove canonical bank cron inactive with unrelated jobs/history preserved, then include it in final clean/populated upgrade testing and authorized deployment.
- **O01, S08, F03, F10:** Review full hosted124-to-current rollout; complete body/configuration/privilege readback, realistic upgrade, compatible Edge/client pairing and post-deployment negative tests.
- **A01, P07, A09, U06, U08, S09:** Complete browser-reload roster recovery and actionable terminal errors; extend same-user session-generation fencing and operation-specific ACK validation across generic Admin operations.
- **F10, S09, S08:** Validate authentic evidence intake, deployed MFA/role/session/GoTrue semantics, disputes/reversals and operator acceptance; rerun passing local races after freeze.
- **O05, S10, P07, M08, U05:** Configure/prove unattended hosted notification scheduling, actual APNS/FCM delivery, permission/lifecycle changes, duplicate/dead-letter and session recovery.
- **S03, O04, O08:** Complete trusted end-user bot/network controls, concurrent phone/account/global quotas and approved spend limits.
- **S04:** Complete evidence-based uncertain OTP-send recovery without blind resend.
- **A02, A03, A09:** Build multilingual/scan/prompt-injection ground truth; finish full codec expansion controls, durable budgets, XLSX transformation validation and realistic resource/workbook acceptance.
- **O06:** Complete redacted push/receipt/financial queue, lease, ACK, completion and scheduler metrics/alerts; rehearse operator response.
- **Q01, Q03, Q07, A05, A06, A10:** Resolve seven indexed asset deletions and stale dependency inventory; retain fresh integrated source/lock/log-matched evidence without promoting drifted historical packets.
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
| G05 | P0 | Partial | Finish representative compatibility validation of the selected Increment 11/v2 changes, preserve all merge decisions, integrate remaining corrections and freeze one reviewed release commit. Repeat full validation on that commit. Include reviewed roster provenance142 and legacy-bank-scheduler retirement143 corrections before the candidate freeze. |
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
| D09 | P1 | Partial | Recover the exact failed142 synthetic graph from the preserved baseline using the reviewed rollback-first recovery; verify all table/control fingerprints, then rerun the corrected concurrent roster harness and actual SQL-to-Dart receipt fixture. Complete one clean replay through the final frozen migration set (last complete replay:141), representative populated124-to-current upgrades, incompatible-client behavior and rollback/roll-forward. Preserve historical financial evidence and verify authorized hosted restore. |
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
| O01 | P0 | Partial | Resolve the verified hosted124 versus local142 migration drift through a reviewed, backed-up and rehearsed coordinated rollout. Obtain exact hosted function/Edge bodies and configuration, effective column/schema grants, exposed API schemas, Auth settings and cron owners/database. Re-read all versions, hashes, ACL/RLS, protocol values and schedules after deployment; execute authorized negative/smoke cases. |
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
| A01 | P1 | Partial | Complete guarded142 fixture recovery and concurrent/adversarial rerun, then decode actual PostgreSQL receipts through the Dart workflow. Add actionable handling for revision limits, request conflicts, already-committed imports and permission/feature revocation. Pair frozen SQL/Edge/Admin contracts in staging; verify human approval, source/approver audit, both raw-writer closures, exact ACK/replay and session revocation under real operator use. Resolve browser-reload draft recovery through a session-bound server reference or an explicitly accepted recovery policy; retain private-data isolation and stable retries. |
| A02 | P1 | Unverified | Build a ground-truth evaluation covering scans, multilingual text, duplicate/ambiguous identities and prompt injection; measure error classes and prove safe rejection/correction. |
| A03 | P1 | Partial | Implement bounded full image/PDF decoding and page/object/animation expansion controls or a validated sandbox; enforce durable concurrent actor/global resource and cost budgets. Verify original XLSX-to-derived-TSV transformation, representative corrupt/spoofed/page-heavy inputs and worst-case browser/device memory and latency before vendor calls. Rerun integrated protection after freeze. |
| A04 | P1 | External | Verify actual AI vendor retention/store settings, processing geography, consent/legal basis and minimization; obtain vendor/privacy evidence rather than inferring it from request flags. |
| A05 | P2 | Partial | Trace every active asset, font and icon through all builds/references and licenses, including font redistribution rights. Reconcile the seven indexed local asset deletions with the reviewed Git/manifest inventory; establish reachability before further removals. |
| A06 | P2 | Unverified | Resolve the current asset-check failure from seven indexed files deleted locally; 174 approved file hashes match. Verify all approved bytes and dimensions against independent trusted provenance and document intended removals or changed artwork without automatic restoration. |
| A07 | P2 | Unverified | Identify proven unused code/dependencies and prepare a reviewed deletion-only change; run Android/iOS/Admin/public build and route regression before removal is accepted. |
| A08 | P1 | Partial | Inventory mutable runtime settings and product copy; test permissions, validation, versions and audit. Keep stable application strings distinct from governed operator settings. |
| A09 | P1 | Partial | Exercise representative Excel/LibreOffice import/export workflows for formula injection, row/resource limits and redaction. Verify consent/reasons, permission denial and durable server audit for imports, grants, retries and sensitive reveals. Complete actual SQL-to-Dart receipt and142 concurrency checks; validate reference-bound create/add imports and lost-response/session behavior with deployed operators, then retain a frozen integrated source/log-matched packet. |
| A10 | P1 | Partial | Publish one candidate-bound handover identifying source, deployment, signed artifact hashes, exact tests/exclusions, contacts, approved exceptions and accountable decision. Retain all logs and manifests in the reviewed deliverable or a verified archive; reconcile dependency/asset inventories and historical versus current evidence. |

## X — Crosscutting acceptance checks: 2 open

**Responsible roles:** Product/design owner and accountable release owner.

| ID | Priority | Evidence | Work and proof required for closure |
| --- | --- | --- | --- |
| X01 | Crosscutting | Partial | Resolve all five retained visual differences; obtain valid reference coverage or explicitly reviewed adaptations, then bind route/state, interaction, accessibility and owner annotations to the exact installed/browser build. Missing original references remain an evidence gap. |
| X02 | Crosscutting | Partial | Retire the verified active owner-run legacy bank cron with immutable bounded retirement evidence while preserving historical bank/financial rows; review, apply and test correction143. Verify retirement of deployed bank handlers and external schedules, Rwanda-only RWF/MTN/Airtel routes, public/support/privacy/store wording and approved historical audit access. Rehearse representative hosted upgrades and verify post-deployment scope. |

## Dependency order and closure rule

1. **Source/accountability:** G01–G04,G09–G10,P06; assign named environment, signing, store, legal, finance and operations owners.
2. **Security/financial policy:** S01–S10,F01–F10; approve finality, expiry, queue capacity, retention, MFA and budgets.
3. **Integrated data/source:** recover142 fixture, finish143, rehearse124-to-current upgrade; D01–D10,A01–A09,O01/S08. Freeze G05 and resolve/build Q01–Q03/Q05; regenerate Q07 from that candidate.
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
- [142 guarded recovery source handoff](roster-import-provenance-2026-09-30/RECOVERY_SOURCE.md): source/syntax checks only; no recovery execution claimed.
- [Admin scope and limitations](admin-roster-provenance-2026-09-30/README.md) and [Edge scope and limitations](roster-provenance-edge-postreview-2026-09-30/README.md).
- [Historical drifted XLSX packet](roster-xlsx-hardening-2026-09-30/README.md).

The sole UI/UX authority is `revolut-design`, implemented through shared tokens/components across mobile, Admin and public web. Native, Business/operator and marketing comparators require their applicable route/state, interaction, accessibility and owner evidence. No surface is asserted fully matched. The full implementation goal remains active.
