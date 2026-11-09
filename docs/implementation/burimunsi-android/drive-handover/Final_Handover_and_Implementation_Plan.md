# Final engineering handover

BuriMunsi / M-Money / Collect • Critical review and implementation plan • 9 November 2026 • Africa/Kigali

Decision: hand over the verified engineering package for controlled integration. Do not designate the applications production-ready or activate live financial operations on the strength of the current source, local tests or upload receipts.

The folder contains substantial implemented engineering work—not merely a visual prototype. It does not yet establish one latest, fully integrated, dependency-complete, device-qualified and operationally accepted release. The central remaining work is integration and qualification, together with real production adapters, bank commissioning and accountable business acceptance. [S01–S16]

| Handover measure | Observed position |
|---|---|
| Original production action groups | 25 retained; zero closed by the engineering delivery. |
| Master engineering actions | 36 preserved with separate source, local-verification and external-acceptance fields. |
| Original detailed task contracts | 66 M-Money + 65 BuriMunsi = 131; preserved in full JSON and readable workbook tabs. |
| Current review execution | 2,909 manifest files verified; 210 toolkit tests passed; product groups 46 passed / 4 blocked; overall exit 2. |
| Receiving environment | Selected hosted Collect project remains healthy but uncommissioned in the inspected application tables; direct observation at 14:26:31 Kigali. |
| Additional work breakdown | 12 integration and 8 business rows decompose the master actions. These overlap and are not 20 additional unique production requirements. |

Receiving package: this report; an editable implementation workbook; machine-readable actions and source references; unchanged original task contracts; archive identities; fresh verification logs; and the read-only environment observation. It does not replace, merge or modify the existing application source archives. The current r3 source remains at the source link recorded as S01.

## 1. Review scope and evidence discipline

The review examined the main engineering r3 archive, the previous production audit, the complete recovery.3 archive, the SMS R4 archive, the latest available continuation reports for API, storage, presentation, release safeguards, safe import, API routing and unified regression, the MoU export, and both tabs of the BNR reporting workbook. Four downloaded ZIPs were inventoried and safely extracted. Critical implementation contracts and selected call-site boundaries were inspected; this is not a line-by-line security audit of every historical archive or every file in Drive. [S01–S14]

The 24-workstream index inside r3 is a preserved historical coverage record. The workbook’s 12-row latest-workstream matrix is this review’s decision-oriented summary, not a claim that the underlying file population contains only twelve workstreams. Source uploads, archive membership and conversation inventories provide useful traceability, but unavailable full transcripts, the actual local workstation checkout and unpublished files cannot be certified as included. No private-key or operational credential was retrieved. [S01,S02,S11]

Evidence is classified as directly executed here, directly observed through a read-only connector, reported in a reviewed source, or proposed work. A successful integrity verifier means the recorded bytes agree; it is not independent publisher identity, successful native compilation, a passed financial test, regulator approval or receiving-team acceptance. Counts of test cases, assertion loops, repeated executions and suite groups are kept separate. [S01,S04,S10,S16]

The applicable snapshot is 9 November 2026. The latest source versions reviewed are listed explicitly; later uploads require a new delta review. The BNR workbook covers 1 October–4 November and must not be interpreted as November-to-date live operating performance. Public technical documentation was consulted only to check platform distinctions; it supplies no evidence that this particular deployment is accepted. [S14,W01–W03]

## 2. Verification performed in this review

| Check | Fresh result | Interpretation |
|---|---|---|
| Engineering r3 integrity | Passed; 2,909 manifest files | Payload SHA-256: 0162d031b3f1ab3f83925872239ea8d950b786be399fad886ffdb3e6b91aa17c. |
| Fresh source assembly and delivery tests | 210 tests passed; zero reported test failures | Exact package verified again after execution; source trees remained bound to the issued manifests. |
| BuriMunsi selected product plan | 6 groups passed; 1 blocked | The native-prerequisite group is blocked. The child process returned 0; the enclosing verifier correctly retained blocked status. |
| M-Money selected product plan | 40 groups passed; 3 blocked | pg, PGlite and pinned TypeScript checks lack required dependencies. Child exit 2. |
| M-Money evidence-binding validator | Exit 0 | Source/plan/log consistency valid, not external acceptance. |
| Combined delivery result | BLOCKED; exit 2 | Completed 12:30:36 UTC / 14:30:36 Kigali. No production acceptance inferred. |

This reproduction corroborates the scoped r3 results. It does not replace the wider unified-r3 runner report, which records 79 passed and 16 blocked groups. Those plans have different scope and missing executors; comparing 46/4 with 79/16 as a reduction of defects would be misleading. Nor should the repeated Node/Python/Kotlin counts be combined into a unique business-scenario total. [S01,S04,S16]

Downstream CI must inspect structured mandatory-check status rather than equating every child exit 0 with complete qualification. The fresh BuriMunsi invocation demonstrates why: its native prerequisite remains blocked even though the child process succeeds. The enclosing delivery tool handled this distinction correctly. Preserve that gate when adopting or changing runners. [S16]

## 3. Current Collect environment: direct observation

The connected project rrlduytparvsjfmegalh is named Collect, reports ACTIVE_HEALTHY, and runs PostgreSQL 17.11. A read-only aggregate query at 2026-11-09 12:26:31 UTC found zero public mm_ prefixed tables and zero burimunsi-prefixed tables in non-system schemas. Its latest recorded migration is 20261023174000_collect_stopped_admission_lifecycle. [S15]

All ten selected relations returned zero rows: collections, memberships, receiving accounts, gateway bindings, gateway credentials, SMS receipts, MoMo transactions, payments, ledger entries and contribution-posting snapshots. This supports the conclusion that the inspected application path has not been commissioned in this selected hosted target. It does not establish the state of every other project, the local Supabase instance, bank records or an uninspected deployment. A healthy database service is not a functioning or accepted application. [S15]

No schema, migration, financial record, service configuration or user account was changed. The actual dirty local Collect checkout, current Cloudflare account configuration, deployed origin/handler parity and installed devices remain unverified. A historical remote Git commit is not a substitute for a receiving working-tree snapshot. Those identities are first-class inputs to A01, A05, A06 and A12, not details to infer from archive names. [S01,S02,S12,S15]

## 4. Critical findings and required dispositions

### F01 — No complete latest integration baseline

P0 • Engineering r3 deliberately integrates only the release-safeguard slice. Its financial, SMS, storage and recovery runtime paths are unchanged from the selected A03.3/A04.1 baselines. Newer runtime continuations remain separate. “Latest ZIP” is therefore not “all latest work included.” Refresh the merge matrix and issue one new source candidate only after every affected path has an explicit decision.

Disposition: A03,A04,A29; I01,I02. Evidence: [S01,S05–S10].

### F02 — Historical merge counts are easily misread

P0 • Nine of the original 153 path occurrences were integrated. The remaining 144 are non-release records requiring review, not 144 conflicts or 144 defects. They span historical comparisons and are no longer a complete count of the newest changes. Do not reuse that denominator as a current completeness metric.

Disposition: A02,A29. Evidence: [S01].

### F03 — Release authenticity is not yet commissioned

P0 • r3 includes the older r2 release guard; standalone r4 introduces independently pinned Ed25519 producer statements. r4 was exercised against historical application inputs, not these consolidated trees. Rebase semantically, preserve current workflow guards, and provision real independent trust and producer credentials outside source/evidence. No real signer approval is established.

Disposition: A19,A25,A34; I10. Evidence: [S01,S10].

### F04 — Secure SMS persistence still lacks production components

P0 • SMS R4 implements encrypted journal and two-phase checkpoint logic with synthetic durable ports. It explicitly does not implement/deploy the trusted checkpoint backend or production Android CiphertextBlobPort. Restoring both ciphertext and a locally restorable checkpoint defeats rollback detection. Offline intake/quarantine must retain SMS before checkpoint-dependent queue admission.

Disposition: A16,A17; I03,I04. Evidence: [S08].

### F05 — Storage factories are not application adoption

P0 • Storage R3 supplies authenticated journals, adoption protocol and factory entry points, but real legacy decoding, key/directory provisioning, durable writer cutover, immutable archive copies and application/worker wiring remain open. Authentication alone does not detect deletion of a complete valid history suffix; an independent monotonic checkpoint and retention/capacity policy are still required.

Disposition: A17,A23; I05,I06. Evidence: [S06].

### F06 — Recovery guarantees are local and bounded

P0 • Recovery.3 preserves immutable command identity and introduces bounded read-only status retries and process-local single-flight coordination. Its retry budget is opt-in and process-local, not durable/global rate limiting; no automatic lifecycle polling service was installed. Locks, transport liveness and ownership/commit consistency still require real integration. Never resolve uncertainty by issuing a fresh financial operation.

Disposition: A08,A14,A18; I07. Evidence: [S07].

### F07 — Actual network and financial behavior remains unqualified

P0 • Strict response framing and timing checks are implemented, but platform header normalization and non-cooperative blocking streams/cleanup remain explicit limitations. Local stubs, fake HttpURLConnection, host SQLite and PGlite are not real hosted/Android/PostgreSQL acceptance. Qualify commit-then-disconnect, ownership rotation and independent concurrent database sessions.

Disposition: A06–A14; I08. Evidence: [S05,S07,S12].

### F08 — Native and installed UX acceptance is still open

P0 • The source has controller/presentation tests, including twelve journeys, but no pinned final merged Android build/device evidence was established here. Presentation.3 restores positions within 16 pages/2,000 rows; it does not guarantee restoration to the identical record after data changes. Installed list geometry, process death, TalkBack, keyboard/IME and fluent localization remain required.

Disposition: A15,A18; I09. Evidence: [S09,W02].

### F09 — Dependencies and executor gaps remain real blockers

P0 • A03.3 has three dependency-backed blocked groups. Unified runner r3 reports seventeen missing tarballs of eighteen and sixteen blocked groups including full JVM/browser and separate external gates. A synthetic offline install tests transport, not the missing application suites. Use exact packages and correct artifacts; do not substitute looser versions or an unrelated browser prototype.

Disposition: A30,A33; I12. Evidence: [S03,S04].

### F10 — Credential-like findings need classification

P0 • Release r4 reports 33 unresolved credential-like files on its historical full-application inputs. This is neither proof of 33 live exposed secrets nor proof that current r3 has the same findings. Classify without printing secret values, rotate genuine exposed credentials, preserve audit evidence and rescan the final candidate. Heuristic exceptions are not universal security clearance.

Disposition: A19,A34; I11. Evidence: [S10].

### F11 — Organisational acceptance is not encoded by technical success

P0 • The engineering register leaves named owners UNASSIGNED, retains all 25 original production actions open, and does not establish receiving-team, BSM, independent security or operational acceptance. Assign people and evidence-producing responsibilities rather than only functional labels; preserve the 131 original acceptance contracts during consolidation.

Disposition: A01,A20–A27; B01,B04,B07. Evidence: [S01,S02,S13].

### F12 — Business targets and a finished MoU are not operating authority

P0 • The reporting workbook remains pre-launch and labels rates/credit terms as working or subject to BSM terms. The MoU requires execution conditions and distinct savings/credit acceptance. Actual signature, regulator-specific permission and activation evidence were not established. The January 1,000-member ambition and planned roadshows do not override approved scope or readiness.

Disposition: A24,A25; B01–B08. Evidence: [S13,S14].

## 5. Source handover and merge strategy

Use engineering r3 as a verified receiving baseline, not a final all-workstream release. It contains BuriMunsi logical version 0.20.0-a04.1 and M-Money 0.2.12-a03.3 (engineering versionCode 17), plus exact inputs, overlays, patches and merge decisions. Keep all baseline archives immutable. Issue a new engineering revision and hashes for the next combined result; a logical version label cannot identify changed bytes on its own. [S01,S03]

| Workstream | Latest reviewed | Integration / remaining boundary |
|---|---|---|
| M-Money consolidation | A03.3 + r3 release slice | Included in S01. Missing real dependencies and all external gates |
| BuriMunsi consolidation | A04.1 + r3 release slice | Included in S01. Latest parallel runtime continuations not merged |
| Command recovery | 0.19.0-recovery.3 | Separate source; not consolidated. Lifecycle adapter and real PostgreSQL/device qualification |
| SMS queue | R4 | Separate source; not consolidated. Trusted checkpoint backend, Android blob port, offline quarantine, worker wiring |
| Storage lifecycle | R3 | Separate implementation report reviewed. Real legacy decoders/cutover, monotonic checkpoint, native adapters |
| API contracts | r3 | Separate implementation report reviewed. Combined merge and actual platform/service transport qualification |
| Presentation/UI | 0.19.0-presentation.3 | Separate implementation report reviewed. Combined merge; installed all-journey/accessibility/localization acceptance |
| Safe repository intake | v1.2.0 | Standalone tooling. Actual receiver binding/import/commit not performed |
| Local API routing | v1.2.0 | Standalone harness/composition. Actual Collect handlers, Cloudflare and hosted acceptance |
| Unified regression | r3 | Standalone runner; different plan from S01. 17 of 18 real pinned tarballs absent in its report; 16 blocked groups |
| Release safeguards | r4 | Not included: S01 uses r2 guard input. Rebase on final candidates and commission independent trust/producers |
| Engineering package/traceability | r3 | Byte verified and local reproduction during review. 144 historical residual occurrences need refresh; receiving/external closure |

Recommended merge order: freeze inputs and receiving contracts; reconcile source/runtime overlap; integrate storage and SMS durability adapters with recovery and authority fences; integrate API and presentation call sites; then update import, runner and release-provenance tooling around the resulting trees. This is a dependency proposal, not a claim the merge was executed. Avoid treating any single continuation’s full-tree archive as a replacement for the consolidated product. [A29; I01–I12]

For every changed path, record the upstream input ID/hash, before hash/mode, competing change, chosen resolution, reason, after hash/mode, focused regression and final manifest entry. Preserve compatible improvements and explicitly explain omissions. Re-run old and new tests together, particularly OperationJournal/NativeRepository, ViewModel restoration, ApiClient/CloudClient and worker/store/importer interactions. The original 316 M-Money decisions and historical A29 dispositions remain provenance, not proof of latest integration. [S01,S03,S05–S09]

## 6. Collect, database and Admin implementation handover

Preserve the two-product boundary. M-Money is personal, read-only financial tracking; BuriMunsi supports group operations through canonical financial authority. Sharing infrastructure does not authorize shared user identity, raw SMS access, payment authority or automatic cross-posting. Choose and record the deployment/data-isolation model before importing schemas or configuring public clients. [S01,S13]

Receiver intake: snapshot the actual checkout’s HEAD, branch, index and working tree, including unrelated local edits. Stage verified archives outside that checkout. Use the v1.2 safe importer to bind exact receiver files and a reviewed plan. Revalidate immediately before an authorised apply under exclusive ownership. Review the full diff and commit to a protected review branch. Per-file atomic publication is not a transactional whole-repository import; power-loss recovery and unknown edits must remain evidence-preserving. [S11]

Database/authentication: rehearse migrations on an explicitly selected disposable or staging target. Connect genuine PIN/managed sessions, current owner/group identities, worker grants, token rotation/revocation and canonical transaction context. Test row-level authorization using actual client/runtime roles rather than privileged service credentials. Supabase’s official documentation confirms that service-role/secret keys bypass RLS and are not public-client credentials; a permissive service-role test would not prove member isolation. [S01,S07,S15,W01]

Financial path: retain original evidence, map authentic provider/receipt identity to the correct member, and distinguish capture, retention, reconciliation and bank-credit states. Connect the actual canonical writer and scheduler with the existing authority and execution fences. Qualify lost acknowledgements after commit, status recovery, reversals, duplicate submissions, concurrently created/changed identities, token/grant changes and bank reconciliation. An uncertain result is unresolved work, not permission for another operation. [S01,S07,S13]

Admin and hosted preview: deliver scoped operational queues, unknown-outcome/status checks, exception review, membership/account diagnostics, device/session revocation, reconciliation and audit records. Register existing JSON handlers without overriding protected namespaces. Verify real Cloudflare route precedence, assets behavior, TLS/CORS, forwarded methods/body/query/auth and JSON error behavior. The local v1.2 harness is a useful component, not proof of the account’s deployed bindings or a completed Admin application. [S01,S12,W03]

## 7. Native, durability and security handover

Native build acceptance starts with the exact final merged commit, authentic pinned dependencies and intended variants. Compile/lint Staff and receiving builds, inspect final manifests and DEX/permissions, install the resulting APKs and execute instrumentation. Device-dependent storage, lifecycle, UI and receiver behavior cannot be inferred from host Kotlin or source parsing; Android’s official testing documentation explicitly places instrumented tests on physical/emulated Android devices. [S01,S09,W02]

SMS R4 requires a trusted, durable, authenticated, independently rollback-resistant linearizable checkpoint implementation with enforced transitions. A checkpoint beside the encrypted blob or in the same restorable local database is not equivalent. The offline receiver must retain encrypted evidence even when the checkpoint service is unavailable, before advancing intake state. Implement the real encrypted-blob port, migration and lifecycle fences; do not wire the plaintext host adapter into the app. [S08]

Storage R3 requires actual legacy decoders, a full artifact inventory, frozen old writers and a persistent cutover gate; missing keys/directories must not trigger silent provisioning. Explicit fresh-store provisioning, non-exportable key custody, immutable archive readback, deletion absence checks, tombstones, replacement intent and retained operation identities must be tested through failure boundaries. Decide retention/compaction and anti-rollback authority before capacity exhaustion becomes an operational incident. [S06]

Recovery and presentation must be qualified together: an offline or recreated screen must not erase the pending command, change its original owner/ID/body, fabricate a successful balance or submit a second mutation. Test late HTTP responses across session-generation changes, failed cache/journal cleanup, wrong-key state, SIM replacement and restored positional bookmarks. Complete twelve installed journeys, large text, TalkBack/Switch Access, keyboard/IME, exports and bilingual operator review. [S07,S09]

Commission the r4 release-provenance trust separately from build output. Approved external trust-policy digests, producer identities, roles, thresholds and revocation must be protected outside the candidate evidence. A build system that chooses its own approving key from its own archive is not independent attestation. Sign actual evidence only after the relevant native, database, security and operations qualification exists. [S10]

## 8. Business, legal and operating handover

The MoU assigns authoritative financial records and customer funds-control responsibilities to BSM, with IKANISA providing technology, staff, mobilisation and support within its approved role. It requires pre-execution particulars/permissions and distinct written Savings Activation and Credit Activation. This review did not establish executed signatures, actual approval letters or signed activation certificates. That is an evidence gap—not a legal finding that no such approval exists. Regulatory classification and actual permission scope must be verified by the responsible compliance/legal owners. [S13]

Create one approved terms matrix before printing, training or activation. The reviewed MoU states a standard RWF 1,000 contribution minimum, voluntary contribution timing, ordinary 4% annual savings interest subject to product approval, and an additional one percentage point only on eligible pledged amounts for blocked days. It distinguishes individual full exit from dissolution of the group or resignation of BSM membership, and allows approved hardship exceptions/mandatory rights. These are source terms to reconcile and approve, not financial promises newly certified by this report. [S13]

The BNR workbook’s working credit terms and outreach ambitions must not silently become launch commitments. Keep credit disabled until BSM separately approves tariff, affordability/capacity, loan agreements, individual pledge/debit mandates, perfection/release/enforcement rules and applicable insurance/guarantee arrangements. Savings readiness and lending readiness are different gates. [S13,S14]

Privacy and operating controls must distinguish personal-app deletion from retention of canonical financial records. Approve controller/processor responsibilities, hosting and transfers, access/retention, incident escalation, restore procedures and staff use of customer information. The reviewed MoU restricts use of customer SMS/restricted material in general AI accounts; ordinary technical support must not become uncontrolled evidence export. The phone/SIM, recovery process and transactional credentials remain under the approved custody model. [S13]

The commercial basis also requires an explicit decision: the reviewed MoU allocates implementation/launch/mobilisation costs to IKANISA and does not create an interparty fee, retainer, commission or revenue share without a separate signed commercial amendment. Do not build a business case that assumes such income. Obtain a funded budget, trained staffing, daily reconciliation responsibilities, complaints/redress owners, support roster and tested escalation contacts. [S13,S14]

The reporting workbook records October numeric zeros for users/contributions and “Pre-launch” for 1–4 November; “none reported” incidents are not measured zero-risk performance. It records a November–January programme, planned roadshows on 14 November 2026 (Muhoza), 12 December 2026 (Busogo) and 16 January 2027 (Kinigi), and a 1,000-member ambition by 31 January 2027 subject to BNR limits. These are plans, not verified bookings, approved population limits or achievements. Confirm four-centre permissions, local authorities, radio/influencer arrangements and budgets; do not collect live funds merely because the 14 November date is close. The source-stated continuity milestone before 5 February 2027 must be checked against the actual approval. [S14]

## 9. Dependency-ordered implementation plan

The phase sequence below is a proposed receiving-team plan. It intentionally uses evidence-based exit gates rather than invented completion dates. Assign named owners and estimate effort after the real checkout, authentic dependencies, target devices and operational approvals are available. Legal/operating work can progress alongside engineering; live activation cannot bypass either path.

### P0 — Authority, scope and ownership

Accountable roles: Product owner; BSM; compliance. Dependencies: None. Actions: A01,A02,A27,B01,B02,B03,B06,B07.

Exit evidence: Named accountable owners; target/environment decisions; approved operating and product scope. Engineering can proceed safely without live funds. Hold: No production activation or financial commissioning inferred.

### P1 — One complete source and reproducible local evidence

Accountable roles: Collect/Android/build leads. Dependencies: P0 scope. Actions: A03,A04,A26,A28–A36,I01,I02,I11,I12.

Exit evidence: All latest workstreams dispositioned; exact pins/manifests; mandatory local checks completed on same source. Hold: Do not overwrite unknown receiver edits or use old evidence for new source.

### P2 — Real repository, storage and authority integration

Accountable roles: Collect/backend/Android/security leads. Dependencies: P1 baseline; P0 target approval. Actions: A05–A08,I03–I07.

Exit evidence: Protected receiving commit; real migration/auth/RLS rehearsal; production adapters and preserved-state cutover. Hold: No service-role client shortcut, silent empty-store recreation or new ID for uncertainty.

### P3 — Canonical services, Admin and preview end-to-end

Accountable roles: Backend/Admin/DevOps; BSM reconciliation. Dependencies: P2. Actions: A09–A14,I08.

Exit evidence: Actual hosted route/auth/processor/Admin and PostgreSQL reconciliation evidence. Hold: Stub success is not hosted acceptance; captured SMS is not credited savings.

### P4 — Native, physical reliability and independent assurance

Accountable roles: Android/QA/security/release leads. Dependencies: Frozen P2/P3 candidate. Actions: A15–A19,A22,I09,I10.

Exit evidence: Pinned builds, APK inspection, real device/SIM/storage/accessibility tests, security and signed provenance. Hold: Host JVM and syntax checks cannot replace Android instrumentation.

### P5 — Operational commissioning and savings acceptance

Accountable roles: BSM operations; joint sponsors. Dependencies: P3,P4; P0 legal conditions. Actions: A20,A21,A23,B04,B08.

Exit evidence: Custody, on-call, monitoring, restore/stop rehearsals and signed savings activation. Hold: Outreach date is not go-live authority.

### P6 — Bounded authorised pilot

Accountable roles: BSM and IKANISA operations/compliance. Dependencies: P5. Actions: A24; B05 only for credit activation.

Exit evidence: Consented pilot in approved limits; daily reconciliation, complaints and stop controls evidenced. Hold: Credit remains disabled without its separate acceptance.

### P7 — Attributable release and receiving closure

Accountable roles: Release owner; BSM; security; operations. Dependencies: P6 and all mandatory gate evidence. Actions: A25; final A26/A27/A36 closure.

Exit evidence: One signed release with exact commit/APK/deployment/evidence identities and accountable acceptance. Hold: No automatic promotion on valid-but-blocked evidence.

Critical path: freeze approved scope → merge every chosen continuation → complete exact dependencies and production adapters → import into the real review branch → prove real auth/database/hosted behavior → qualify the same native artifacts and independent security → commission BSM operations and savings acceptance → run the authorised pilot → promote an attributable release. Bank/legal approval, checkpoint design, real-device access and external trust provisioning can each independently block that path.

## 10. Complete master-action handover index

The workbook contains all 36 master actions with source status, named-owner field, role, dependency, implementation steps, acceptance evidence and source URL. The original 25 production actions remain open. Rows A26–A36 describe bounded engineering delivery/provenance progress and cannot close product criteria by implication. The index below identifies the next action; the full machine-readable register and original task contracts are included in registers/.

| ID / phase | Master action | Next closure focus |
|---|---|---|
| A01 / P0 | Freeze two product boundaries and target environments | Signed environment and product decision record; receiving team and rollback owner named. |
| A02 / P0 | Close conversation-to-artifact traceability | One dated coverage index; no unexplained missing requested workstream; exclusions named. |
| A03 / P1 | Merge M-Money parallel branches from v0.2.10 | Reviewed merge ledger and regenerated candidate manifest; all relevant old and new tests pass. |
| A04 / P1 | Reconcile BuriMunsi canonical and four continuations | One new immutable BuriMunsi candidate; changed-path disposition and cross-workstream tests. |
| A05 / P2 | Import into a protected Collect review branch | Receiving commit, complete diff, preserved unrelated edits and fresh CI; synthetic fixtures alone do not close this action. |
| A06 / P2 | Rehearse migrations and runtime authorization | Migration ledger plus real PostgreSQL allow/deny results for each principal, product and scope. |
| A07 / P2 | Wire M-Money Auth and identity-preserving recovery | Hosted authenticated acceptance for correct/wrong/expired owner and re-login; no cross-user admission. |
| A08 / P2 | Wire Buri managed-session and worker authority | Real host/database tests demonstrate authentic user/worker authority; no fabricated principal or unfenced side connection. |
| A09 / P3 | Connect M-Money processor and quotas | Actual hosted rejection/acceptance, quota and privacy tests bound to deployed version. |
| A10 / P3 | Connect canonical receipt adoption and financial posting | Receipt-to-canonical-ledger proof with one valid financial outcome; ambiguous identity never auto-posted. |
| A11 / P3 | Build scoped Collect Admin operational surfaces | Role-by-role end-to-end demonstration; no mock balances, unauthorized cross-group access or raw-SMS leakage. |
| A12 / P3 | Deploy preview API routing without SPA interception | Preview deployment ID plus real positive/negative requests; unknown API routes never return HTML. |
| A13 / P3 | Execute hosted M-Money acceptance | Source-bound hosted logs, target identity and all mandatory contracts satisfied. |
| A14 / P3 | Qualify SQL concurrency and bank reconciliation | SQL outcomes, ledger invariants and BSM reconciliation evidence; PGlite/SQLite/test doubles are not substitutes. |
| A15 / P4 | Build and bind native artifacts from merged commit | APK hashes, package/variant identity, toolchain pins, build logs and installed test evidence; Staff excludes receiver capabilities. |
| A16 / P4 | Approve authentic corpus and physical SMS matrix | Physical-device/carrier matrix preserving original evidence, rejecting ambiguity and demonstrating no loss or duplicate monetary action. |
| A17 / P4 | Qualify encrypted storage, deletion and restore | Real Room/SQLCipher/Keystore/storage-pressure/process-death/reboot/power-interruption results with evidence retained. |
| A18 / P4 | Accept native UI, accessibility and exports | Installed journey checklist and recordings; all 246 paired resources reviewed; restoration never clears unresolved commands. |

| ID / phase | Master action | Next closure focus |
|---|---|---|
| A19 / P4 | Complete independent security and distribution review | Threat-model closure, independent findings disposition, licence/SBOM inventory and release-key custody. |
| A20 / P5 | Commission real Buri group and receiving custody | Signed custody/access register and controlled end-to-end BSM ledger acceptance. |
| A21 / P5 | Deploy monitoring, alerts and support ownership | Live alert delivery, acknowledged escalation, privacy-safe logs and service ownership record. |
| A22 / P4 | Measure device and service budgets | Measured report against stated budgets with failure thresholds and containment behavior. |
| A23 / P5 | Exercise backup, restore, stop and rollback | Witnessed rehearsal with RPO/RTO approved by operators; no reset, silent recreation or duplicate posting. |
| A24 / P6 | Run bounded consented pilot | Dated pilot observations, reconciled balances, consent and incident records; zero unresolved critical safety defects. |
| A25 / P7 | Release one signed, attributable candidate | Signed release record and rollback package; public gates reject absent/stale/wrong-version evidence. |
| A26 / P1 | Deliver byte-verified engineering archive and reproducible tooling | Receipted handover keyed to immutable archive and commit; upload alone is not receiving acceptance. |
| A27 / P0 | Separate completion, verification and acceptance in traceability | Updated master register and evidence catalogue with no production closure inferred from tool success. |
| A28 / P1 | Replay baseline patches and preserve merge decisions | Every changed path has original and resulting hashes and an explicit decision; no unexplained omission. |
| A29 / P1 | Integrate post-consolidation continuations deliberately | No unexplained changed-path occurrence; latest guarded runtime and tooling in one candidate, verified together. |
| A30 / P1 | Close candidate dependency and pinned-toolchain gaps | Zero mandatory dependency/toolchain blocks for the selected plan; all missing inputs explicitly recorded until then. |
| A31 / P1 | Deliver r2 source intake, lineage and reproduction tools | Updated provenance index with directly resolvable archive members and hashes. |
| A32 / P1 | Register and test the A04 Kotlin result-format adapter | Source-bound adapter selftests and final plan accounting after runner changes. |
| A33 / P1 | Repeat standalone continuation and tooling checks | Named suite inventory reconciled across candidates and continuations; no unexplained missing required suite. |
| A34 / P1 | Integrate release-safeguard slice without runtime regressions | Cross-workstream tests plus real signed producer statements; unsigned/mismatched/self-supplied trust fails closed. |
| A35 / P1 | Reproduce scoped source merges and byte-check both patches | Independent receiving reproduction and final manifests; previous r3 success does not certify new source. |
| A36 / P1 | Account for and upload available conversation artifacts | Readback receipt plus coverage exceptions; do not claim unprovided full transcripts or local workstation files were reviewed. |

## 11. Explicit integration and business work breakdown

These twenty rows are actionable decompositions of the master actions, not a separate additive backlog. Each has full implementation steps, accountable role, parent actions and acceptance evidence in the workbook. I01–I12 preserve the latest technical limitations; B01–B08 close the non-code handover requirements.

| ID / parents | Work item | Required evidence |
|---|---|---|
| I01 / A29 | Refresh latest-version merge matrix | Updated path-level ledger; no blind whole-tree replacement. |
| I02 / A04,A29 | Resolve shared runtime call-site overlap | Integrated tests preserve authentication, original IDs and financial-authority boundaries. |
| I03 / A16,A17 | Implement trusted SMS checkpoint service | Restoring both handset ciphertext and local data cannot rewind trusted state; concurrent writers and outage tests pass. |
| I04 / A16,A17 | Implement encrypted offline intake and blob transactions | No SMS evidence loss or intake-cursor advance before durable retention; device power-interruption proof. |
| I05 / A17 | Implement legacy storage adoption and writer cutover | Original IDs, pending operations, tombstones and archived generations survive restart; old writers cannot restart. |
| I06 / A17,A22,A23 | Close storage anti-rollback and capacity policy | Valid-suffix truncation detected or safely blocked; approved retention and measured storage exhaustion behavior. |
| I07 / A08,A14,A18 | Wire recovery lifecycle scheduling deliberately | Manual and scheduled GET recovery preserve original command; five-read local policy is not misrepresented as global durable limit. |
| I08 / A12,A13,A15 | Qualify actual HTTP framing and strict-version rollout | No malformed acknowledgement admitted; compatible versions and actual timeout behavior measured. |
| I09 / A18 | Accept bounded positional restoration semantics | Product accepts positional rather than guaranteed same-record restoration; installed accessibility/journeys pass. |
| I10 / A19,A25,A34 | Commission independent signing/provenance trust | Independently authenticated evidence accepted; missing/revoked/wrong-role signatures rejected. |
| I11 / A19,A34 | Triage historical credential-like findings | Every finding disposition evidenced; no assumption that 33 findings are 33 current leaked secrets. |
| I12 / A30,A33 | Close exact missing-executor inventory | All required current plan entries executed or explicitly excluded by documented scope decision; no inherited pass. |
| B01 / A01,A20,A25 | Execute MoU and governance particulars | Authorised signatures and applicable conditions recorded; final document title alone is not execution. |
| B02 / A01,A24,A25 | Verify actual sandbox and regulatory authority | Written scope permits intended pilot; no inference from public framework, publicity or an application/report. |
| B03 / A18,A20,A24 | Approve one product terms and disclosure matrix | BSM-approved bilingual version; no contradiction between any-amount claims, minimums or conditional credit promises. |
| B04 / A14,A20,A24 | Sign savings activation acceptance | Dated savings activation certificate with attached evidence; source/test-tool completion is not sufficient. |
| B05 / A24,A25 | Keep credit separately gated | Separate credit acceptance; savings can be evaluated without representing credit as active. |
| B06 / A01,A17,A19,A23 | Approve privacy, retention and hosting controls | Approved policies and tested technical enforcement; no uncontrolled customer SMS in general AI accounts. |
| B07 / A20,A21,A23 | Fund and staff the operating model | Funded budget, staffing/training, signed operating responsibility and contact matrix. |
| B08 / A21,A24 | Gate outreach and reporting programme | Verified venues/dates/permissions; measured report replaces targets; continuity plan before source-stated 5 February 2027 milestone subject to actual approval. |

## 12. Receiving-team protocol and reproduction

The receiving lead should acknowledge the exact source archive/hash, obtain access to the review repository and target environments, assign the open owners, and accept the evidence boundary. Record publisher/signing/operations custodians and escalation contacts separately from ordinary source access. Do not place secrets in the handover workbook, examples or Drive source archives. Receiving access and acknowledgement have not been inferred from a successful upload. [S01,S11,S13]

Reproduce engineering r3 from a fresh extracted archive outside the actual checkout. Preserve executable modes and use a new output directory. The package verifier and source assembly do not require operational credentials. Current full reproduction is expected to remain blocked until prerequisites and external acceptance are supplied. [S01,S16]

```sh
# Run from the verified Engineering_Delivery_2026-11-09_r3 archive root.
PYTHONDONTWRITEBYTECODE=1 python3 -B tools/verify_delivery.py
PYTHONDONTWRITEBYTECODE=1 python3 -B tools/assemble.py
PYTHONDONTWRITEBYTECODE=1 python3 -B tools/verify_delivery.py --results ../fresh-r3-handover-run
# Preserve the actual exit code and structured summary. Do not reuse the output directory.
```

Fresh review evidence is included under evidence/r3_fresh/. The reproduced assembled application trees are not duplicated in this handover ZIP; recover them from the unchanged S01 source archive and the recorded assembly instructions. Product evidence may refer to paths from this review environment; use source hashes and relative manifest entries, not absolute workstation names, as identity. Full original task histories are included without rewriting their historical statuses.

The source archives have independent SHA-256 records in evidence/inputs.json. The handover package itself has a non-circular CONTENTS_SHA256.json, with a separately supplied checksum for the final ZIP. File hashes prove consistency relative to those records; authenticity still depends on the trusted channel, independently controlled producer identity and receiving acceptance.

Prohibited shortcuts: do not bypass the receiving upload hold; treat a missing acknowledgement as failure permission; generate a new financial ID for an uncertain outcome; delete or recreate a corrupt store; install the test-only plaintext adapter; accept a locally restored checkpoint as independent rollback protection; apply patches to unknown preimages; replace current tests with historical logs; or label valid blocked evidence as production passed. [S01,S06–S12]

## 13. Completion and acceptance criteria

Engineering handover is complete only when the receiver can reconstruct the declared source, locate every retained contract and omission decision, run the documented plan, identify every blocked check, and name accountable implementers. This report and workbook deliver the decision/evidence package; actual receiving acknowledgement, latest-source merge and production acceptance remain open.

Production requires a single final candidate and deployment identity with no unapproved omissions, authentic dependencies, completed mandatory real-device/hosted/PostgreSQL qualification, independent security findings closed or explicitly accepted by an authorised risk owner, protected provenance/signing, BSM custody and reconciliation, tested support/backup/stop procedures, actual regulatory scope and signed savings acceptance. Credit needs its separate activation. No percentage-complete score is substituted for these gates. [S01,S10,S13]

The correct immediate decision is to appoint the receiving integration lead and BSM operational owner, freeze the latest input matrix, and execute P0/P1 while commissioning access for P2–P4. Do not begin another sequence of isolated source continuations without feeding each one back into the same canonical merge ledger and acceptance plan.

## 14. Evidence register and limits

S01 — Engineering delivery r3. Full archive extracted; 2,909 manifest files independently byte-verified; local reproduction executed. Locator: source/; START_HERE.md; traceability/action-register.json; config/merge-plan.json. Source: https://drive.google.com/file/d/1m4jvIKRSpReuxRG3-svfiS0DSBt3F2Qa/view

S02 — Previous production audit and Collect handover. Historical archive inspected; original 131 task contracts retained, not new acceptance. Locator: Production_Readiness_Report.md; evidence/; implementation-actions.json. Source: https://drive.google.com/file/d/10b4Zt2Qz0-6iQNh8pa-PuWAvgNmJHT6j/view

S03 — M-Money A03.3 continuation. Implementation report read; candidate also present in S01. Locator: 0.2.12-a03.3; offline dependency transport; 316 original merge decisions. Source: https://drive.google.com/file/d/1FE87zENXD4o9F4jVRJ0PPJ2RAzD2FdBr/view

S04 — Unified regression r3. Implementation report read; reported run not independently rerun here. Locator: 79 passed / 16 blocked; exact A03/A04 scope, not final all-continuation merge. Source: https://drive.google.com/file/d/1Yg5CA4EgDYoaZABJyMc6GrDrr87S84c8/view

S05 — API contracts r3. Implementation report read; reported results retained as source claims. Locator: Strict request/response and transport; 19 changed code/test/tool paths. Source: https://drive.google.com/file/d/1QK16bAbRrEEs5Wk0KabmHa_awn_zuPUa/view

S06 — Storage policies R3. Implementation report read; runtime adoption expressly open. Locator: Authenticated journal; legacy adoption protocol; native cutover remains. Source: https://drive.google.com/file/d/1_5nr_2s8m3BxKZbW7ahEDIM8MrHZOYf5/view

S07 — Command recovery .3 complete source. 780 archive entries inventoried; focused implementation/limitations inspected. Locator: docs/56_Read_Only_Recovery_Retry_v0.19.0-recovery.3.md. Source: https://drive.google.com/file/d/1pjGkCJkpxFQaTrM0ga1-XlXD4WKnN6UP/view

S08 — SMS policies R4 complete source. 135 entries inventoried; focused code/contracts and README inspected. Locator: README.md; TASK_STATUS.json; trusted checkpoint and encrypted blob ports. Source: https://drive.google.com/file/d/1MpBN7wi3FpgdoICUtmfTOo6Yrrh-3r_t/view

S09 — Presentation .3. Implementation report read; reported local checks not device qualification. Locator: Bounded paged restoration; 12 controller journeys; 246 strings per language. Source: https://drive.google.com/file/d/1L2FXKKiUy1385HixLcXw3kF1cPhE0Ys4/view

S10 — Release safeguards r4. README read; historical-input and real-signer limitations identified. Locator: Ed25519 producer provenance; 33 historical credential-like file findings. Source: https://drive.google.com/file/d/1kfsGEGo_qOcMtsHn9U1q0cUIrbJTGuyg/view

S11 — Safe Collect intake v1.2.0. Delivery summary read; synthetic receiver tests distinguished from real import. Locator: Pinned archive intake, HEAD/branch/receiver binding, unknown-edit refusal. Source: https://drive.google.com/file/d/10jGvXCK5E7aRwt5z0oksziTi6UYYQXpn/view

S12 — Local API routing v1.2.0. Implementation report read; live routing remains unverified. Locator: Combined registered JSON handlers; read-only intake planner. Source: https://drive.google.com/file/d/1a9t2YiTBUytzkn6BByS1u0CskhcJkduO/view

S13 — Full MoU before launch and fees review. DOCX export read; no executed signature/activation evidence established. Locator: Clauses 3, 8, 9, commercial terms; Schedules 1 and 7. Source: https://drive.google.com/file/d/1oxp4Aykfh0i3KZzccLFqcqsb55IUakQjxVQsTSYLygo/view

S14 — BNR report: 1 October–4 November 2026. Both workbook tabs read; reported period not current performance. Locator: BNR Return; Activities; pre-launch KPIs, programme and targets. Source: https://drive.google.com/file/d/1bSEeGT_ATEXC4NJYCRRR90ufcEUySVMwh07kQwXAM0U/view

S15 — Collect read-only environment observation. Direct connector metadata and aggregate SQL at 2026-11-09 12:26:31 UTC (14:26:31 Kigali); no rows or credentials exported. Locator: evidence/collect_environment_2026-11-09.json; evidence/collect_readonly.sql. Source: https://supabase.com/dashboard/project/rrlduytparvsjfmegalh

S16 — Fresh handover verification. This review: original r3 integrity, 210 toolkit tests, scoped product runners; no native/service/financial acceptance. Locator: evidence/r3_fresh/summary.json and logs.

W01 — Supabase: securing data. External official technical reference accessed 9 November 2026; not project evidence. Locator: Secret/service-role keys bypass RLS; not safe for public clients. Source: https://supabase.com/docs/guides/database/secure-data

W02 — Android: instrumented tests. External official technical reference accessed 9 November 2026; not execution evidence. Locator: Instrumented tests exercise physical or emulated Android framework. Source: https://developer.android.com/training/testing/instrumented-tests

W03 — Cloudflare: HTML handling. External official routing reference accessed 9 November 2026; not account verification. Locator: Evaluate real routing and assets configuration; local stub is not deployed evidence. Source: https://developers.cloudflare.com/workers/static-assets/routing/advanced/html-handling/

Limits: this review did not execute a native build, device/carrier test, live financial transaction, deployed API acceptance, repository import, security penetration test or regulatory certification. The exact supplied continuation reports support the stated implementation boundaries; tests reported by those workstreams are not presented as newly rerun here. The direct database observation covers only the selected target and inspected relations. No claim is made that every file or private approval outside the inspected materials was unavailable or absent.

