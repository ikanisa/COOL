# BuriMunsi — remaining implementation and acceptance tasks, v0.17.0

8 November 2026. **All 65 production acceptance criteria remain OPEN (51 P0, 14 P1).** One web-only audit item closed in its original scope; 19 audit items have partial implementation and 10 are open. Audit and production registers overlap.

## Next execution order

1. **Real native builds.** Supply the pinned Gradle distribution, licensed Android SDK and actual dependencies. Compile both Staff and receiving flavors, inspect merged manifests/APKs, run instrumentation, then install/test on approved devices.
2. **Original-principal financial reconciliation.** Integrate the real canonical retained-command status reader and atomic writer; test read-after-write timing, 401/429, network loss, reauthentication and principal/token migration. Never replay unknown commands.
3. **Managed identity/admission.** Implement the genuine phone/PIN session, independently authorized automatic worker, operator/member/identity/source bridges and scheduler, with server-side group/role checks.
4. **Real PostgreSQL/ledger qualification.** Verify RLS, locks, canonical posting, duplicate prevention, history joins, reversals, reconciliation and BSM account balances on staging under concurrency.
5. **Receiving device and SMS reliability.** Confirm lawful facility/SIM authority, phone enrollment/replacement, durable queue, provider fixtures, Doze, reboot, backlog drain and no double posting.
6. **Full prototype handoff.** Complete typography/contrast, animation/transitions, locale, notification responsibilities, eight routes, every contextual panel, keyboard/back handling, TalkBack and 12 operational journeys.
7. **Security, operations, signing and acceptance.** Independent privacy/security, incident/reconciliation procedures, bank acceptance, performance, QA signing, distribution, migration/restore, incident monitoring and final promotion evidence.

## All 30 original audit findings

### A01 — Financial state labels can imply the wrong outcome
**Critical | PARTIALLY_IMPLEMENTED | Handoff** — Owner: Android + Design | Related original tasks: T031–T038; T046–T047

**Implemented in v0.17.0:** Removed auto-resend of unresolved financial commands and ensured a POST success is not presented as canonical success without matching authenticated retained-command outcome.

**Remaining:** Verify exact canonical server result and full state mapping on installed Android with real PostgreSQL/provider admission and rollback tests.

**Acceptance:** Every supported state has truthful icon, accessible name, permitted actions and balance effect; reversed, processing, conflict and unknown states never render as allocated.

### A02 — Large amounts break into misleading digit lines
**High | PARTIALLY_IMPLEMENTED | Handoff** — Owner: Design + Android | Related original tasks: T044; T047

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Qualify native measurement, all amounts in contextual panels, system font/display scaling and very large balances on devices.

**Acceptance:** At supported widths and Android font/display settings, zero, refunds, ordinary balances and agreed maximum amounts are readable in full with no arbitrary digit splits.

### A03 — Back navigation loses the actual originating screen
**High | PARTIALLY_IMPLEMENTED | Handoff** — Owner: Android | Related original tasks: T043; T045

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Test Back, keyboard dismissal, nested panels and process recreation on installed Android; verify the refreshed parent does not restore stale financial or staff data.

**Acceptance:** Home/recent, payment list, member ledger and raw SMS each open a detail and return to the exact origin with one Back; a sheet closes before its underlying route.

### A04 — Search and list context disappear after inspecting a record
**High | PARTIALLY_IMPLEMENTED | Handoff** — Owner: Android | Related original tasks: T041; T045

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Verify actual LazyColumn scroll and refresh-after-write behavior on installed Android, including process recreation.

**Acceptance:** A filtered, paginated list returns with the same query, filter, scroll anchor and selected record after detail/Back and safe recreation.

### A05 — Closing a web dialog loses keyboard focus
**High | CLOSED_WEB_VERIFIED | Handoff** — Owner: Prototype + Accessibility QA | Related original tasks: T045; T047

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** None for the original web focus-restoration defect. Native accessibility is tracked separately in A18.

**Acceptance:** Escape, close icon and successful submit place focus predictably; Tab never escapes an open modal or lands under it.

### A06 — Unsaved form data lacks a defined dismissal/recreation policy
**High | PARTIALLY_IMPLEMENTED | Handoff** — Owner: Design + Android | Related original tasks: T045; T054

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Run actual Compose disposal, IME, rotation, multi-window, background and process-death tests. Review the requirement to reselect a beneficiary/reopen a staff account after returning.

**Acceptance:** Rotation, process death, background/foreground and accidental dismissal retain or deliberately discard drafts according to a documented rule; no credential leaks or duplicate writes.

### A07 — Form validation differs between prototype and implementation
**High | PARTIALLY_IMPLEMENTED | Handoff** — Owner: Design + Backend + Android | Related original tasks: T034; T039; T046

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Execute device/API form boundaries and confirm policy decisions with product/security owners; verify every remaining form.

**Acceptance:** Prototype, Android and API accept/reject the same boundary cases; helper text explains requirements before a disabled action or error.

### A08 — Full-name disclosure must work for sighted touch users
**Medium | PARTIALLY_IMPLEMENTED | Handoff** — Owner: Design + Accessibility QA | Related original tasks: T044; T047

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Test longest names, real translations and native assistive-technology output on devices.

**Acceptance:** Long and similar names can be distinguished visually and with TalkBack; selection/confirmation always exposes the complete beneficiary identity.

### A09 — Native typography and contextual surface tokens are not equivalent
**High | OPEN | Handoff** — Owner: Design system + Android | Related original tasks: T006; T044

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Create a versioned dp/sp token contract with licensed Android fonts, weights, line heights, numeric styles, surfaces, states and contrast-safe route foregrounds. Acceptance: Native screenshot comparisons pass at target sizes; full font metrics and gradient-backed text/icon contrast are measured in rendered states, not inferred from hex colors alone.

**Acceptance:** Native screenshot comparisons pass at target sizes; full font metrics and gradient-backed text/icon contrast are measured in rendered states, not inferred from hex colors alone.

### A10 — Icon-only navigation and actions need task-comprehension evidence
**Medium | OPEN | Handoff** — Owner: Design + Operations | Related original tasks: T043; T047; T056

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Preserve the four destinations. Test recognition with actual staff; add approved teaching/selected-label/context cues only where evidence shows confusion. Acceptance: Operators find Messages, member ledger, unallocated payments and support without coaching; no confusion between viewing a receipt and confirming a credit.

**Acceptance:** Operators find Messages, member ledger, unallocated payments and support without coaching; no confusion between viewing a receipt and confirming a credit.

### A11 — Native SMS screen loses queue and duplicate distinctions
**High | PARTIALLY_IMPLEMENTED | Handoff** — Owner: Android + Design | Related original tasks: T023; T041; T043–T046

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Implement/qualify real source-reader filtering and cursor semantics on PostgreSQL; verify native route and raw source rendering.

**Acceptance:** Queued, duplicate, synced, rejected and unknown receipts remain distinguishable visually and in semantics; none falsely signals a ledger credit.

### A12 — Native history and activity lack the evidence detail shown or needed
**High | PARTIALLY_IMPLEMENTED | Handoff** — Owner: Android + Backend + Operations | Related original tasks: T037; T045; T061

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Qualify the existing canonical schema, timestamp semantics and financial-link joins on real PostgreSQL. Complete actor/reason/source/correction coverage with authoritative evidence; separately linked compensations are not claimed. Compile and test the native history panel, large histories and accessible reading on devices.

**Acceptance:** An operator can explain received versus posted versus reversed, find the relevant source reference and escalation path without editing the financial record.

### A13 — Several native panels only expose the first returned page
**High | PARTIALLY_IMPLEMENTED | Integration** — Owner: Android + Backend | Related original tasks: T010; T041; T045

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Qualify real API paging and snapshot contracts, cursor expiry, large lists and all installed-native load-more controls. Verify no valid provider response is rejected and history overflow escalates rather than truncates.

**Acceptance:** Seed more than one API page; the last staff account, audit event and eligible member can be reached without omissions, duplicates or choosing an inactive member.

### A14 — Offline provenance is not propagated consistently into native detail UI
**High | PARTIALLY_IMPLEMENTED | Integration** — Owner: Android | Related original tasks: T035; T042; T045

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Qualify encrypted storage, active-screen expiry, clock changes, lifecycle ordering and offline cache on devices. UI hiding is not memory zeroization.

**Acceptance:** Drop connectivity between list and detail: cached data is marked read-only with truthful age; all mutation affordances and result checks remain consistent.

### A15 — Error, stale, pending and empty states lack complete recovery contracts
**High | PARTIALLY_IMPLEMENTED | Handoff** — Owner: Design + Android + Backend | Related original tasks: T033; T038; T042; T045

**Implemented in v0.17.0:** An operator’s Check previous action now performs an authenticated read only. Pending/rejected outcomes receive distinct copy and the original unresolved journal is retained.

**Remaining:** Complete remaining UI error states and validate real offline, slow response, process death, session rotation and accessibility behavior.

**Acceptance:** Each state explains what is known, whether money changed, what the user can do and how recovery returns to the correct screen. Unknown outcome reconciles the original operation ID.

### A16 — Receiver setup, SIM changes and replacement need a complete operator journey
**High | PARTIALLY_IMPLEMENTED | Handoff** — Owner: Android + Operations | Related original tasks: T013–T016; T021–T023; T062

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Complete real administrator provisioning, singleton pairing, SIM change, lost-phone revocation, source-preserving replacement and queue recovery. New work is local diagnosis, not a complete replacement implementation.

**Acceptance:** A trained operator can provision, deny/regrant permission, detect SIM change, retire a lost receiver and recover the retained queue with no second active gateway or duplicate credit.

### A17 — Role and lifecycle behavior is not fully reconciled
**High | PARTIALLY_IMPLEMENTED | Handoff** — Owner: Product + Security + Android | Related original tasks: T010–T012; T039–T040

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Verify installed roles and deployed server capabilities, live revocation and staff lifecycle behavior under concurrency.

**Acceptance:** Every UI and API action matches the agreed matrix; disabled staff and inactive members are visible and cannot be confused with eligible actors/beneficiaries.

### A18 — Native accessibility needs semantic and device qualification
**High | PARTIALLY_IMPLEMENTED | Integration** — Owner: Accessibility QA + Android | Related original tasks: T047; T056

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Compile and execute instrumentation, TalkBack, keyboard/switch access, large-font and focus restoration tests on both APK variants.

**Acceptance:** TalkBack and switch/keyboard users complete login, locate a payment, identify a member, allocate, inspect state and obtain support with no unlabeled/duplicate/confusing nodes.

### A19 — Motion and screen transitions are only partially specified
**Medium | OPEN | Handoff** — Owner: Motion design + Android | Related original tasks: T044–T047

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Specify hierarchy-aware enter/exit, Back cancellation, sheet dismissal, loading and restrained confirmation feedback. Retain no-motion equivalents; never animate a queued receipt into a confirmed balance. Acceptance: Normal/reduced/no-animation modes preserve task meaning, respect system settings and do not block input or communicate false financial success.

**Acceptance:** Normal/reduced/no-animation modes preserve task meaning, respect system settings and do not block input or communicate false financial success.

### A20 — Language, date/time and notification scope remain decisions
**Medium | OPEN | Handoff** — Owner: Product + Operations + Android | Related original tasks: T048

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Choose supported languages and release scope, externalize strings, specify Kigali/local versus provider timestamps and RWF formatting. Keep original SMS body immutable; do not invent notification behavior. Acceptance: Approved translations fit long-text layouts; times have unambiguous provenance/zone; receipt evidence is untouched; member-notification responsibility is explicit.

**Acceptance:** Approved translations fit long-text layouts; times have unambiguous provenance/zone; receipt evidence is untouched; member-notification responsibility is explicit.

### A21 — No reproducible native test artifact has been demonstrated
**High | PARTIALLY_IMPLEMENTED | Integration** — Owner: Android + Release engineering | Related original tasks: T001; T003; T043; T057–T059

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Provide the checksum-pinned Gradle distribution, licensed SDK and dependencies. Compile both variants, run lint/instrumentation, inspect manifests/APKs, then install and test. No APK or native layout evidence exists for this release.

**Acceptance:** A developer follows the documented setup on a clean environment and obtains identifiable runnable Staff and receiving artifacts with logs, checksums and no demo secrets.

### A22 — Release-build gating creates a qualification-order dependency
**High | PARTIALLY_IMPLEMENTED | Integration** — Owner: Release engineering + Security | Related original tasks: T055; T057–T060; T063–T064

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Execute Gradle builds to verify merged manifests/task dependencies and inspect real candidate artifacts. Prove production promotion refuses incomplete evidence in the real pipeline; complete signing and distribution evidence. Source/unit gates do not establish compiled isolation.

**Acceptance:** An optimized non-production candidate can be tested safely before final promotion; missing production evidence still prevents production distribution and activation.

### A23 — Canonical identity and operational bridges remain integration work
**Critical | OPEN | Integration** — Owner: Backend + Technical lead | Related original tasks: T001; T007–T012; T024–T032; T060

**Implemented in v0.17.0:** Repository now checks original session token before any operation-status read or command send. New principal-scoped cross-token recovery remains intentionally fail-closed.

**Remaining:** Implement and independently verify principal-scoped command reconciliation across session renewal and operator lifecycle with backend evidence; do not replay historical requests.

**Acceptance:** The real Admin and a separately authorized automatic worker process receipts against the correct group; wrong principal, revoked grants and cross-group actions fail without side effects.

### A24 — Real database isolation and security boundaries are not proven
**Critical | OPEN | Pilot** — Owner: Backend + Security QA | Related original tasks: T025; T029; T032–T038; T052; T054; T060

**Implemented in v0.17.0:** Mutation completion now requires the authenticated retained-command status with an exact request ID. Status lookup failures after HTTP success remain UNKNOWN and block another mutation.

**Remaining:** Qualify real PostgreSQL retained-command atomicity, response read-after-write, 401/429/race behaviors and canonical ledger effects under concurrency.

**Acceptance:** Crash/race/commit-loss tests yield exactly one canonical effect, consistent balances and an auditable refusal for invalid scope; rollback and reconciliation are evidenced.

### A25 — The actual SMS-to-ledger lifecycle remains unqualified
**Critical | OPEN | Pilot** — Owner: Android + Backend + Field QA | Related original tasks: T013–T030; T053–T054

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Use the selected business-SIM devices and consented provider fixtures; qualify capture, filtering, durable encrypted queue, deduplication, ACK, recovery and canonical posting before opening the hold. Acceptance: Offline, reboot, dual-SIM changes, force-stop/relaunch, full storage, multipart SMS, duplicates and long backlog preserve evidence and do not credit twice; truthful limits are documented.

**Acceptance:** Offline, reboot, dual-SIM changes, force-stop/relaunch, full storage, multipart SMS, duplicates and long backlog preserve evidence and do not credit twice; truthful limits are documented.

### A26 — Security/privacy controls need independent end-to-end evidence
**High | OPEN | Pilot** — Owner: Security + Privacy owner | Related original tasks: T008; T011; T016; T049–T051

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Test PIN abuse/lockout and recovery, credential revocation, installation binding, data-at-rest/transit, exports, logs, retention, support escalation and least privilege. Review the applicable privacy basis with the responsible owner. Acceptance: Independent evidence covers relevant MASVS groups and server authorization; no Staff SMS assets/permissions or unintended source-message exposure; retention and incident ownership are recorded.

**Acceptance:** Independent evidence covers relevant MASVS groups and server authorization; no Staff SMS assets/permissions or unintended source-message exposure; retention and incident ownership are recorded.

### A27 — Native responsiveness and performance have not been measured
**High | OPEN | Pilot** — Owner: Android performance + QA | Related original tasks: T004; T044–T045; T055

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Test small/large fonts and displays, short landscape, cutouts, gesture/three-button navigation and supported large screens. Benchmark optimized candidates on the chosen low-end receiver and Staff devices. Acceptance: Agree measured budgets for startup, scrolling/frame percentiles, memory, APK size, battery/network use and backlog drain. Show no cut-off actions or blocked input under the keyboard.

**Acceptance:** Agree measured budgets for startup, scrolling/frame percentiles, memory, APK size, battery/network use and backlog drain. Show no cut-off actions or blocked input under the keyboard.

### A28 — Operational monitoring and recovery ownership remain incomplete
**High | OPEN | Pilot** — Owner: Operations + SRE + Backend | Related original tasks: T023; T061–T065

**Implemented in v0.17.0:** No new changes; previous implementation retained.

**Remaining:** Define capture/upload/parse/match/post/reconcile checkpoints and thresholds, ownership, emergency pause, receiver replacement, restore and escalation. Redact diagnostic data. Acceptance: Simulated capture gap, parser failure, long queue and ledger drift trigger actionable alerts; drills prove recovery without duplicate money or lost evidence.

**Acceptance:** Simulated capture gap, parser failure, long queue and ledger drift trigger actionable alerts; drills prove recovery without duplicate money or lost evidence.

### A29 — The prototype’s state and usability coverage is not complete
**High | PARTIALLY_IMPLEMENTED | Handoff** — Owner: Design QA + Operations | Related original tasks: T043–T048; T053–T056

**Implemented in v0.17.0:** New JVM/core, repository and controller scenarios cover pending, repeated taps, POST success plus pending/401 status, mismatched request ID and non-replay behavior.

**Remaining:** Run actual Android, real provider/database fault injection and all twelve operator journeys; do not count synthetic tests as production acceptance.

**Acceptance:** All mandatory journeys and state families in the report have runnable fixtures and evidence; no critical/high handoff issue remains unexplained or silently deferred.

### A30 — A single versioned handoff contract and explicit scope decisions are needed
**High | PARTIALLY_IMPLEMENTED | Handoff** — Owner: Product + Technical lead + Design | Related original tasks: T006; T043–T048; T056; T064

**Implemented in v0.17.0:** Versioned exact-byte 0.16 upgrade provenance, reconciliation contract, verification evidence and remaining-task register delivered.

**Remaining:** Finish original handoff decisions, native APK/toolchain/visual qualification and legal/operational owner acceptance.

**Acceptance:** The dev team can identify the authoritative design, run it, find all assets/contracts, trace each acceptance test and understand all deferred production gates without guessing.

## All 65 original production acceptance criteria

### T001 — Revalidate the current Collect source and deployed environment
**P0 | OPEN | G1** — Owner: Technical lead | Dependencies: None

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Remote default head was rechecked and matches the pinned commit; all 386 v0.11.0 manifest entries passed integrity verification. Reconcile the actual working checkout, migration/schema state and deployed endpoints. Remote pin and archive integrity do not establish deployed parity. v0.15.0 acceptance: Reconcile actual table/column types, timezones, scope/link uniqueness and deployed adapter compatibility before use.

**Acceptance:** Record repository commit plus working-tree snapshot, schema/migration versions, deployed function versions and actual API behavior. Recheck every 5 Nov finding before treating it as current. Preserve unrelated working changes.

### T002 — Confirm the production group, wallet, SIM, roster and administrator
**P0 | OPEN | G1** — Owner: Product owner + operations | Dependencies: T001

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Supply the real BuriMunsi group ID, receiving-account ID, business wallet/SIM, member roster, Admin phone, and device custodian. Confirm ownership and operation of WhatsApp support **0780025501**.

**Acceptance:** Supply authoritative BuriMunsi group ID, canonical receiving-account ID, authorized wallet/SIM route, complete roster, admin login phone and named device custodian. Confirm +250780025501 as the operated WhatsApp support destination. No demonstration values enter production.

### T003 — Choose native packaging and record receiver reuse boundaries
**P0 | OPEN | G1** — Owner: Android lead | Dependencies: T001

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Compile and qualify both native flavors in an SDK-equipped environment; verify dependencies and reused receiver boundaries against the working Collect checkout.

**Acceptance:** Select a fully native Kotlin UI implementation and document whether the existing receiver is extended or extracted into a slim native module. Reuse queue/acknowledgement controls; do not replace them with a WebView or an unintegrated OpenSMS fork.

### T004 — Select devices and the internal distribution route
**P0 | OPEN | G1** — Owner: Android lead + operations | Dependencies: T002, T003

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Select the receiving phone, supported staff phones, Android versions, and internal distribution method. Confirm the provisional SDK and application-ID configuration against those choices.

**Acceptance:** Record managed receiving phone, staff device range, supported Android versions, minimum SDK, target SDK and installer/distribution method. Verify current requirements at release. No assumption that an internal gateway automatically qualifies for Play SMS access.

### T005 — Approve a safe automatic member-matching policy
**P0 | OPEN | G1** — Owner: Backend lead + product owner | Dependencies: T002

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Approve and demonstrate the trusted unique identity rule using actual payment evidence. Masked suffixes or names alone must not authorize credit.

**Acceptance:** Demonstrate a unique trusted full payment identity or supported authenticated member reference. Names or masked suffixes alone never authorize credit. The supplied *********816 receipt remains unallocated without independent identity evidence; no fabricated digits. If intended receipts cannot meet this rule, document the limitation and resolve it before claiming full automatic allocation.

### T006 — Confirm branding and reusable-asset rights
**P1 | OPEN | G3** — Owner: Product owner + design lead | Dependencies: T003

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Confirm asset rights and the native font mapping. Compare the rendered native application against the frozen BuriMunsi prototype. Current remediation: A30: Finalize missing typography/motion/locale/gateway/notification decisions and native build proof before final development-handoff acceptance.

**Acceptance:** Use the approved BuriMunsi identity; verify icon and font licenses and the exact native font mapping. Package no source-brand artwork or font binaries from the reference library. Compare native outputs against the frozen BuriMunsi HTML, not a claim of universal Revolut parity.

### T007 — Implement server-validated phone and four-digit passcode sign-in
**P0 | OPEN | G2** — Owner: Backend lead | Dependencies: T001, T002

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Complete genuine managed PIN-to-canonical session integration and real TLS/PostgreSQL/device qualification; fixture compilation is not a server integration.

**Acceptance:** Normalize Rwanda phone inputs; enforce exactly four digits, preserving leading zeroes. Verify credentials on the server over TLS, with a reviewed password/PIN hashing and server-side secret strategy. No email login, OTP or public registration; no frontend account array in production. Qualify a scoped native authentication design compatible with existing Collect services; do not weaken global shared password/security settings to fit the short code.

### T008 — Mitigate the four-digit passcode threat
**P0 | OPEN | G4** — Owner: Security lead | Dependencies: T004, T007

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Session identity/lifetime validation and canonical-principal checks are hardened. Still qualify distributed PIN throttling, lockout/recovery, device restrictions and credential storage on the actual database and devices; these are not resolved by component tests.

**Acceptance:** Approve a threat model acknowledging only 10,000 possible codes. Enforce distributed per-account and risk-based throttling, bounded lockout/recovery, generic failures, audit alerts and managed-device/session restrictions. Test online guessing, distributed attempts and stolen credential material. Four digits alone is not treated as a strong internet-facing secret.

### T009 — Provision the Admin without shipping a master credential
**P0 | OPEN | G2** — Owner: Backend lead + operations | Dependencies: T002, T007

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Implement the admitted operator-principal and device-grant provisioning commands using the real Admin phone. Deliver the initial passcode securely without embedding a master credential in the app.

**Acceptance:** Provision the authorized Admin phone through trusted release configuration and server administration. Deliver initial secret out of band. An app constant or editable request never grants Admin. Define recovery that does not require adding email/OTP to the frozen UI.

### T010 — Implement staff lifecycle and passcode changes
**P0 | OPEN | G3** — Owner: Backend lead + Android lead | Dependencies: T007, T009

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Native account/session identity-immutability schema proposal and active canonical-user checks are added. Implement actual operator provisioning and staff lifecycle commands, including deactivation/removal/reset and canonical revocation; rehearse the proposal and installed-device interactions. Current remediation: A13: Qualify real server cursors, empty intermediate pages, refresh/search races and large native lists.; A17: Deploy only through controlled integration and test every role/capability endpoint, revocation race and installed variant.

**Acceptance:** Admin can add/edit/disable/re-enable/remove staff and assign/reset initial passcodes. Staff can change their own passcode with current/new/confirm, but not their phone or rights. Reject duplicate login numbers; revoke affected sessions on reset/removal and retain audit history.

### T011 — Enforce group, role and action capabilities on every endpoint
**P0 | OPEN | G2** — Owner: Backend lead | Dependencies: T001, T007, T009

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Concrete native financial-authority verification now joins native capability to an already genuine same-principal canonical Admin session and the existing mutation guard. Implement managed-context admission and genuine worker authority; qualify all endpoint/group/role controls and Staff SMS denial against deployed services. Current remediation: A17: Deploy only through controlled integration and test every role/capability endpoint, revocation race and installed variant. v0.15.0 acceptance: Qualify history, every other endpoint and actual role/capability revocation on deployed services.

**Acceptance:** Deny out-of-scope list/detail/search/totals/exports/update channels and mutations. Staff cannot read raw SMS, enroll a gateway or manage staff. Enforce enroll/allocate capabilities independently. Negative tests tamper with IDs, group, role and client flags.

### T012 — Implement native sessions and independent capture authority
**P0 | OPEN | G2** — Owner: Android lead + backend lead | Dependencies: T007, T011

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Qualify real native/canonical session expiry, revocation, background/resume and role changes. Preserve independently authenticated receiving credentials/queue.

**Acceptance:** Use secure revocable native sessions, lifecycle expiry and reauthentication; qualify the transport rather than assuming browser cookies/CSRF work natively. Clear protected operator cache on sign-out without deleting the capture outbox. A revoked operator is not a revoked gateway and vice versa.

### T013 — Enforce exactly one active receiving installation
**P0 | OPEN | G2** — Owner: Backend lead | Dependencies: T002, T011

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Connect the singleton-binding logic to actual pairing and ingestion. Enforce it atomically; reject concurrent enrollment and second-phone uploads. Device replacement must revoke its predecessor.

**Acceptance:** Use an atomic server constraint/transaction for the active BuriMunsi gateway and receiving account. Reject concurrent enrollment and second-phone ingestion. Replacing the device revokes its predecessor without creating a new wallet identity.

### T014 — Qualify business-SIM enrollment and subscription changes
**P0 | OPEN | G2** — Owner: Android lead + backend lead | Dependencies: T004, T013

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Test subscription-to-SIM mapping on the real phone, including missing metadata, SIM replacement, and dual-SIM conditions. Never relabel queued receipts after a binding change.

**Acceptance:** Test actual subscription-to-business-SIM mapping and credential binding. Treat missing/changed subscription metadata as uncertain; do not assume ICCID/IMEI/phone number are always readable or stable. Never relabel already queued sources after a SIM change.

### T015 — Create SMS-free Staff and receiving Admin variants
**P0 | OPEN | G3** — Owner: Android lead | Dependencies: T003, T004, T013

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Compile/inspect/install both variants. Verify merged manifests, executable contents and real Staff zero-SMS access; current check is source only.

**Acceptance:** Use one codebase with isolated source sets. Staff final APK excludes SMS permissions, receiving components, recovery jobs and any notification-listener substitute. Inspect merged manifests and packaged components; Admin role on a non-bound device cannot bypass the gateway boundary.

### T016 — Secure device secrets and replacement recovery
**P0 | OPEN | G4** — Owner: Android lead + security lead | Dependencies: T012, T013, T014

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Qualify protected keys, token rotation, lost-device revocation, backup exclusion, and replacement reconciliation. Restoring an app backup must not clone gateway authority.

**Acceptance:** Use protected installation keys/tokens, rotation and explicit lost-device revocation. Document queue/evidence reconciliation during replacement. Exclude transferable gateway tokens from backups; restoring an app backup must not clone gateway authority.

### T017 — Reuse and qualify the incoming SMS receiver
**P0 | OPEN | G2** — Owner: Android lead | Dependencies: T003, T014, T015

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Receiver extraction and pinned inputs are available. Compile the Android receiver and test actual carrier sender IDs, multipart messages and bounded broadcasts on the selected phone.

**Acceptance:** Capture complete M-Money incoming receipts, including alphanumeric sender IDs and multipart reconstruction. Keep receiver work bounded: no network or financial posting in the broadcast handler. Test actual device and intended sender formats.

### T018 — Filter unrelated and secret-bearing SMS before retention/upload
**P0 | OPEN | G2** — Owner: Android lead + security lead | Dependencies: T017

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Validate the native filtering hook against approved real messages. Prove OTPs, promotions, unrelated SIM traffic, and personal messages never enter the cloud receipt queue.

**Acceptance:** Permit only the intended business receiving route and supported financial receipt class. OTPs, promotions, personal messages and unrelated SIM traffic never enter the cloud receipt queue. Ambiguous provider-like messages do not become contributions.

### T019 — Implement encrypted, owner-bound durable outbox
**P0 | OPEN | G2** — Owner: Android lead | Dependencies: T016, T017

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Prove local commit, encryption, ownership, and immutable capture/binding metadata survive process death, reboot, retries, corruption, and storage failures.

**Acceptance:** Commit source and binding version locally before scheduling upload. Preserve raw body, sender, multipart metadata, capture time and immutable local source identity across process death, reboot-after-unlock and retries. Do not encrypt the queue with the four-digit login code.

### T020 — Implement durable acknowledgement and idempotent retry recovery
**P0 | OPEN | G2** — Owner: Android lead + backend lead | Dependencies: T019, T024

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Exercise the real ingress and queue-retirement path, including server commit followed by lost acknowledgement, partial acknowledgements, reconnects, and repeated uploads.

**Acceptance:** Delete/retire local upload work only after matching durable server acknowledgement. Simulate timeout after server commit, duplicate batch items, partial acknowledgement and reconnect. Preserve stable keys and fetch outcome instead of making a second economic transaction.

### T021 — Qualify scheduling, battery and stopped-state behavior
**P0 | OPEN | G4** — Owner: Android lead + QA | Dependencies: T019, T020

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Measure background capture/recovery under Doze, battery saver, manufacturer restrictions, denied permissions, reboot, and force-stop. Document required unlock/reopen behavior.

**Acceptance:** Measure normal background, Doze, battery saver, OEM restrictions, denied permissions, reboot-before/after-unlock and force-stop. Document explicit user reopen after force-stop. Reuse the existing scheduler unless a measured migration warrants a change; no promise of continuous capture through all OS states.

### T022 — Implement backfill and queue-capacity recovery
**P0 | OPEN | G4** — Owner: Android lead + backend lead | Dependencies: T018, T020, T028

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Complete the authorized historical-release/backfill path. Test overlapping scans, deduplication, cutoffs, uncertain sources, queue saturation, disk-full behavior, and recovery alerts.

**Acceptance:** Use bounded authorized inbox scans with overlap/deduplication, historical cutoffs and retained capture context. Test capacity/disk-full behavior and oldest-pending alerts. Revalidate reported 1,000-record/20-upload/200-scan limits instead of treating them as safe capacity or latency promises.

### T023 — Provide truthful gateway health and incident diagnostics
**P1 | OPEN | G3** — Owner: Android lead + operations | Dependencies: T020, T021, T022

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Verify genuine health timestamps, retained queue count/age, permissions/SIM/network signals, heartbeat and redacted support diagnostics on the receiving phone.

**Acceptance:** Show the frozen gateway panel with actual last capture/upload, pending age/count and permission/SIM/network state. A heartbeat is not processing success. Redacted support diagnostics contain no passcodes, tokens, OTPs or unnecessary raw SMS.

### T024 — Qualify the fixed production API origin
**P0 | OPEN | G2** — Owner: Backend lead + DevOps | Dependencies: T001, T011, T013

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Qualify authenticated pairing, upload, status, heartbeat, and revocation at one fixed TLS origin. Verify expected JSON and durable outcomes—not merely an HTTP 200 response.

**Acceptance:** Pair/upload/status/heartbeat/revocation return expected JSON, authorization and durable outcomes at one fixed TLS origin. Test explicit routes; reject HTML fallbacks despite HTTP 200. Recheck the 5 Nov proxy finding rather than assuming it persists.

### T025 — Validate source provenance and admission at ingress
**P0 | OPEN | G2** — Owner: Backend lead + security lead | Dependencies: T013, T018, T024

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Connect authenticated binding, group/wallet scope, source hashes, and policy versions to existing ingress. Test forged claims, stale credentials, wrong-wallet uploads, and replay.

**Acceptance:** Resolve scope from authenticated binding, not claimed group/phone/user fields. Retain source hashes and policy versions. Test spoofed body, forged sender claims, stale credentials, wrong wallet and replay; document SMS authenticity limitations and reconciliation controls.

### T026 — Collect approved real provider fixtures
**P0 | OPEN | G2** — Owner: QA + operations + backend lead | Dependencies: T002, T005

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Obtain authorized examples from the intended wallet: full/masked numbers, FT Ids, numeric formats, languages, failed/pending messages, reversals, and multipart cases. Keep private fixtures out of public repositories.

**Acceptance:** Capture authorized examples from the intended wallet: masked/full numbers, real FT Id, numeric formats, languages, pending/failed receipts, reversals and multipart cases. Keep consented private fixtures outside public repositories. Distinguish owner-supplied example from synthetic fixtures.

### T027 — Implement deterministic M-Money parsing and validation
**P0 | OPEN | G2** — Owner: Backend lead | Dependencies: T025, T026

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Validate the implemented English receipt parser against the approved corpus. Add only required supported formats, preserving exact source facts and rejecting unsupported or invalid messages.

**Acceptance:** Preserve amount, RWF, original payer name, original phone mask, source timestamp, wallet Balance and FT Id; validate positive integer RWF and timestamp syntax/timezone policy. Unsupported formats fail closed. A model may assist extraction only under separately qualified controls; it cannot invent identity or post balances.

### T028 — Enforce canonical transaction identity and conflict handling
**P0 | OPEN | G2** — Owner: Backend lead | Dependencies: T024, T027

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Connect the transaction/source adapter to PostgreSQL. Prove duplicate observations create one economic transaction and conflicting references cannot produce additional credits.

**Acceptance:** Deduplicate by provider, receiving account, event kind and provider transaction ID. Preserve multiple source observations without multiple credits; conflicting amount/payer facts for the same reference are blocked and diagnosed. Keep internal stable keys hidden in the UI.

### T029 — Replace or qualify the maintenance-only processing admission
**P0 | OPEN | G2** — Owner: Backend lead + DevOps | Dependencies: T001, T024, T027, T028

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Connect the new admitted worker factory to the actual Collect scheduler and supply genuine receipt/rematch admission, source and canonical-ingestion bridges. Qualify leases, retries, backlog processing and alerts on PostgreSQL; no scheduler was activated.

**Acceptance:** Prove scheduled work consumes retained receipts and creates canonical transactions. Implement a processing-capable handler if the reported maintenance gate still exists. Changing MOMO_PROCESSING_PAUSED alone is not accepted as proof. Test leases, retries, poison messages, dead-letter alerts and bounded jobs.

### T030 — Preserve any supported routing reference end to end
**P1 | OPEN | G2** — Owner: Backend lead | Dependencies: T005, T027, T028

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Decide whether a real supported member/payment reference exists. When used, preserve it through storage, matching, and audit; otherwise document full-identity matching. Do not introduce invented `BM` codes.

**Acceptance:** Decide whether a supported provider/member reference exists. When used, retain payment_reference_raw through extraction, canonical storage, matching and audit. Do not manufacture or display a new BM member code. If unused, document the decision and test full-identity matching instead.

### T031 — Implement unique existing-member matching
**P0 | OPEN | G2** — Owner: Backend lead | Dependencies: T005, T028, T030

**This release:** Financial UI status now requires authoritative retained-command outcome, not HTTP success or receipt presence.

**Remaining:** Connect verified, effective-dated payment identities and active memberships to actual transaction data. Validate unknown, ambiguous, and third-party payer cases without guessing beneficiaries. Current remediation: A01: Install native variants and inspect every financial state, TalkBack announcement and server outcome. v0.17 requirement: Financial UI status now requires authoritative retained-command outcome, not HTTP success or receipt presence. Verify on deployed services and real Android before closure.

**Acceptance:** Match only an active eligible membership via the approved unique trusted payment identity/reference rule. Payer name and masked suffix are evidence, never sufficient matching authority. Unknown, ambiguous and third-party payer cases remain named unallocated receipts.

### T032 — Implement atomic automatic posting through the canonical writer
**P0 | OPEN | G2** — Owner: Backend lead | Dependencies: T029, T031

**This release:** Explicit original request reconciliation after mutation POST; pending/401/unknown remain unresolved.

**Remaining:** Connected preparation/allocation/custody/shared posting now has a concrete native-side authority verifier requiring an existing same-principal managed Admin context. The PIN-to-managed context integration and real worker principal are still code work. Qualify real PostgreSQL guards/RLS, canonical session mapping, concurrent revocation, storage/retry behavior and scrubbed-reservation/orphan recovery. No second ledger or manual approval fallback. v0.17 requirement: Explicit original request reconciliation after mutation POST; pending/401/unknown remain unresolved. Verify on deployed services and real Android before closure.

**Acceptance:** For an eligible valid receipt, atomically create allocation, immutable contribution entry, canonical balance result and audit event. Handle concurrency/retries with an idempotency key. No proposal/reviewer/approver wait; no mobile balance writer or second ledger.

### T033 — Implement single-step exception allocation
**P0 | OPEN | G3** — Owner: Backend lead + Android lead | Dependencies: T011, T032

**This release:** Prevent automatic replay of unresolved financial commands, including identical payloads or a read-only pending check.

**Remaining:** Existing native exception HTTP orchestration is connected in source; new native/canonical authority is exercised through synthetic prepared-flow tests. Complete real managed-context admission and native installation, then qualify PostgreSQL authorization/retries and physical-device behavior. Current remediation: A15: Complete route-by-route error/empty/stale/pending matrix and uncertain-operation recovery; verify retry/focus/announcements. v0.17 requirement: Prevent automatic replay of unresolved financial commands, including identical payloads or a read-only pending check. Verify on deployed services and real Android before closure.

**Acceptance:** Authorized user selects an existing member for an unallocated receipt and confirms once. Server checks latest version/status/eligibility then posts via the same atomic writer. Racing staff, stale state and timeout reconciliation cannot double-credit. No independent approval stage is added.

### T034 — Make enrollment-triggered rematching safe
**P1 | OPEN | G3** — Owner: Backend lead | Dependencies: T031, T032, T039

**This release:** Preserve original request UUID and token-bound status scope; principal-scoped cross-session recovery remains open.

**Remaining:** The persistent rematch queue/store/worker and prepared worker composition exist in source. Connect actual enrollment, identity, canonical-outcome, financial-authority and rematch-admission bridges; qualify schema, leases, checkpoints and scheduler activation on PostgreSQL. Current remediation: A07: Execute device/API form boundaries and confirm policy decisions with product/security owners; verify every remaining form. v0.17 requirement: Preserve original request UUID and token-bound status scope; principal-scoped cross-session recovery remains open. Verify on deployed services and real Android before closure.

**Acceptance:** After a valid Direct-member enrollment, reprocess only eligible unallocated receipts using the same trusted identity rule. Enrolling a name/suffix cannot retroactively claim receipts. Demonstrate one credit per receipt even under repeated events.

### T035 — Implement authoritative balances and ledger reads
**P0 | OPEN | G2** — Owner: Backend lead | Dependencies: T032

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Qualify real ledger and balance SQL/snapshots, complete pagination and history semantics, and App/Admin parity. The new executor is source-tested with canonical readback but not the production database. Current remediation: A14: Test real encrypted-cache expiry, reconnection, pending operations, restoration and all detail routes on devices. v0.15.0 acceptance: Validate actual PostgreSQL history projection, canonical links, timestamp meaning, ledger signs, App/Admin parity and correction coverage. No live balances were read.

**Acceptance:** Use the canonical ledger and balance snapshots for Home/member/group totals and pagination. Preserve all real ledger rows and FT Id links. Never use SMS receiving-wallet Balance as a member balance or create fabricated brought-forward entries. Define correction/reversal signs and as-of semantics.

### T036 — Define and qualify reversals, corrections and late events
**P0 | OPEN | G4** — Owner: Backend lead + product owner | Dependencies: T028, T032, T035

**This release:** Transaction error paths distinguish authoritative accepted/rejected from pending/unknown; no speculative credit.

**Remaining:** Agree supported rules and implement immutable compensating entries through the actual writer. Test duplicates, conflicts, and late events; unsupported events must fail safely. v0.17 requirement: Transaction error paths distinguish authoritative accepted/rejected from pending/unknown; no speculative credit. Verify on deployed services and real Android before closure.

**Acceptance:** Decide supported reversal/correction formats and safe automatic rules; retain immutable compensating entries and original lineage. Duplicate or conflicting reversal cannot erase/recredit funds. Unsupported events fail closed with operational incident handling, not a new manual payment-approval journey. Scope and pilot handling require sign-off.

### T037 — Reconcile gateway, Collect Admin and financial evidence
**P0 | OPEN | G4** — Owner: QA + operations | Dependencies: T032, T035, T036

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Execute controlled deposits and confirm identical native App and Collect Admin results for the same group, member, filters, and time basis, with receipt-to-ledger evidence. Current remediation: A12: Implement authoritative event-history feed with actor, timestamps, reasons, original source and compensating ledger links. Current-state summary is not a complete audit history.

**Acceptance:** For the same group/member/filters/as-of basis, native app and Collect Admin agree exactly. Reconcile real controlled deposits with authorized provider evidence; queued/failed/unallocated items never inflate balances. Keep data lineage from SMS to ledger.

### T038 — Measure ingestion and ledger concurrency under load
**P1 | OPEN | G4** — Owner: Backend lead + QA | Dependencies: T029, T032

**This release:** No implicit idempotent replay after unknown result; real concurrency and database locking tests still required.

**Remaining:** Measure real PostgreSQL contention, peak receipt load, and outage recovery. Establish measured processing and backlog-drain targets rather than relying on test-adapter concurrency results. Current remediation: A01: Install native variants and inspect every financial state, TalkBack announcement and server outcome.; A15: Complete route-by-route error/empty/stale/pending matrix and uncertain-operation recovery; verify retry/focus/announcements. v0.17 requirement: No implicit idempotent replay after unknown result; real concurrency and database locking tests still required. Verify on deployed services and real Android before closure.

**Acceptance:** Test projected daily/peak receipts, queue drain after outage and transaction lock contention. Set measured capacity and latency targets with alert thresholds; no invented throughput guarantee from a single advisory lock or 15-minute schedule.

### T039 — Implement scoped Direct-member onboarding and duplicates
**P0 | OPEN | G3** — Owner: Backend lead + Android lead | Dependencies: T002, T011, T031

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Connect existing Collect person/Direct-member creation and membership commands. Verify normalized MoMo numbers, duplicate detection, and enrollment without a member-app account. Current remediation: A07: Execute device/API form boundaries and confirm policy decisions with product/security owners; verify every remaining form.; A17: Deploy only through controlled integration and test every role/capability endpoint, revocation race and installed variant.

**Acceptance:** Enroll a person/membership with MoMo identity without member-app credentials. Normalize full numbers; detect existing person/member; display MoMo number as the identifier. Do not create an identity solely from an SMS name or suffix.

### T040 — Protect membership and shared person edits
**P0 | OPEN | G3** — Owner: Backend lead | Dependencies: T011, T039

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Implement the group-local command adapter and rules for deactivation, identity changes, and number recycling. Preserve historical links and prevent unintended changes to people in other groups. Current remediation: A17: Deploy only through controlled integration and test every role/capability endpoint, revocation race and installed variant.

**Acceptance:** BuriMunsi actions cannot silently change a shared person in another Collect group. Qualify deactivation, identity changes/number recycling and audit/version rules. Admin/staff capabilities follow the approved scope; historical ledger links survive identity changes.

### T041 — Implement full transaction lists, search and authorized exports
**P1 | OPEN | G3** — Owner: Backend lead + Android lead | Dependencies: T028, T035, T039

**This release:** Read-only status now reports pending distinctly without redispatch.

**Remaining:** Execute real authorized export, pagination, CSV handling, document-provider cancellation/write failure and large exports. Verify empty placeholders are handled by operations. v0.17 requirement: Read-only status now reports pending distinctly without redispatch. Verify on deployed services and real Android before closure.

**Acceptance:** Serve all relevant transactions with source amount, date/time and FT Id using stable pagination/filter contracts. Maintain original payer name even when unallocated. Export complete authorized data with CSV-injection safeguards and controlled Android document sharing. No invented BM display reference.

### T042 — Implement refresh, offline cache and stale-data reconciliation
**P0 | OPEN | G3** — Owner: Android lead + backend lead | Dependencies: T012, T035, T041

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Qualify real encrypted caches, lifecycle, clocks, connectivity and uncertain operations; the display guard does not replace server authorization.

**Acceptance:** Display server snapshots; offline records are read-only and truthfully stale without restoring the removed Home timestamp. Test pagination, realtime/poll updates, cache expiry and reconnection. A local receipt queue does not change a server savings balance before posting.

### T043 — Implement native shell and eight frozen routes
**P0 | OPEN | G3** — Owner: Android lead | Dependencies: T003, T006, T012

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Compile both variants; install and exercise all routes and four-icon navigation. No APK was built in this pass.

**Acceptance:** Build Kotlin native screens (Compose recommended) for Sign in, Home, Payments, Payment detail, Members, Member ledger, SMS and Settings. Four icon navigation destinations; Staff has seven core routes. Do not ship the HTML/review workspace as production UI.

### T044 — Port exact tokens, typography, icon controls and truncation
**P1 | OPEN | G3** — Owner: Android lead + design lead | Dependencies: T006, T043

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Compare native colours, geometry, typography, icon controls, and single-line ellipses against the frozen prototype. Test 320–430px-equivalent widths and 200% text scaling without truncating financial identifiers. Current remediation: A02: Qualify native measurement, all amounts in contextual panels, system font/display scaling and very large balances on devices.; A08: Test longest names, real translations and native assistive-technology output on devices.

**Acceptance:** Translate the frozen CSS/geometry into native dp/sp adapters with licensed fonts. Preserve route colors, large values, icon-first controls, single-line name ellipses and full accessible names. Amounts/FT Id/full known phones remain complete; test 320–430 widths and 200% font scale.

### T045 — Implement contextual panels and Android navigation behavior
**P1 | OPEN | G3** — Owner: Android lead | Dependencies: T010, T033, T039, T043

**This release:** Pending status and rejection copy are explicit in controller; all financial mutation buttons guarded by pending state.

**Remaining:** Test native Back/keyboard, dialog focus, safe areas, unsaved changes, process recreation and post-pause reentry across all panels. v0.17 requirement: Pending status and rejection copy are explicit in controller; all financial mutation buttons guarded by pending state. Verify on deployed services and real Android before closure.

**Acceptance:** Implement allocation/onboarding/profile/passcode/staff/gateway/raw-SMS/history/help/filter panels without extra approval screens. Test Android back, keyboard/IME, safe areas, scrolling, state restoration and process recreation.

### T046 — Preserve all approved text and receipt semantics
**P1 | OPEN | G3** — Owner: Android lead + QA | Dependencies: T027, T041, T044

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Run native assertions and visual checks for all approved changes: phone-only/four-digit login; no invented IDs or removed labels; correct Messages shortcut; unchanged original SMS. Current remediation: A01: Install native variants and inspect every financial state, TalkBack announcement and server outcome.; A07: Execute device/API form boundaries and confirm policy decisions with product/security owners; verify every remaining form.; A11: Implement/qualify real source-reader filtering and cursor semantics on PostgreSQL; verify native route and raw source rendering. v0.15.0 acceptance: Verify approved wording in rendered native screens and confirm required provider/source reference and correction details.

**Acceptance:** Confirm phone-only and four digits; no email/OTP; no visible BM IDs, brought-forward/net-contribution or Home Automatic/time subtitle; Messages is the fourth Admin Home shortcut with no duplicate header icon. Full names remain recoverable when ellipsized; original SMS is unmodified.

### T047 — Qualify accessibility and support handoff
**P1 | OPEN | G4** — Owner: Android lead + QA | Dependencies: T044, T045

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Execute TalkBack and alternative input tests, including restored focus, enlarged text and sensitive-content removal on real Android.

**Acceptance:** Test TalkBack, focus traversal, non-color status, touch targets, large fonts, reduced motion and financial confirmation. WhatsApp support uses +250780025501, with verified destination ownership and a practical fallback when unavailable. No source message is auto-shared with support.

### T048 — Complete locale and notification scope decisions
**P1 | OPEN | G3** — Owner: Product owner + Android lead | Dependencies: T004, T026, T043

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Confirm release languages, timezone/display conventions, number formatting, and member-notification scope. Implement approved localization without translating original receipt evidence. Current remediation: A29: Complete all 12 operational journeys, errors, interruptions, real-user usability and device scenarios; not all acceptance cases covered.; A30: Finalize missing typography/motion/locale/gateway/notification decisions and native build proof before final development-handoff acceptance.

**Acceptance:** Confirm release UI language(s), timestamp timezone/display and number formatting. Localize approved labels without translating original receipt evidence. Decide whether member confirmations use existing Collect notifications; no SEND_SMS added solely for inbound capture.

### T049 — Review data retention and regulated operating obligations
**P0 | OPEN | G4** — Owner: Product owner + privacy/legal lead | Dependencies: T002, T004, T025

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Have the responsible owners confirm SMS-processing authority, staff/member access, hosting/processors, retention/deletion, incident procedures, and applicable Rwanda/BNR or sandbox obligations.

**Acceptance:** Confirm authority/notice for business-SIM processing, staff/member access, hosting and processors, retention/deletion, incident handling and applicable Rwanda/BNR or sandbox terms with qualified owners. Record the applicable obligations rather than claiming compliance from this package. No bank-core work is added by default.

### T050 — Harden storage, transport, backups and exported components
**P0 | OPEN | G4** — Owner: Android lead + security lead | Dependencies: T016, T019, T042

**This release:** Untrusted status/duplicate IDs cannot close a pending journal; actual device security remains to verify.

**Remaining:** Independent assessment of actual APK storage, backups, screen capture, logs, TLS, exported components and foreground privacy remains required. v0.17 requirement: Untrusted status/duplicate IDs cannot close a pending journal; actual device security remains to verify. Verify on deployed services and real Android before closure.

**Acceptance:** Use TLS validation, Keystore-protected secrets and encrypted sensitive stores; restrict backup, logs, clipboard/screenshots as policy requires and component exports. Verify no sensitive intent/provider leak, debug endpoint or cleartext path. Never package Supabase service-role credentials.

### T051 — Run independent authorization and abuse testing
**P0 | OPEN | G4** — Owner: Security lead | Dependencies: T008, T011, T013, T033, T050

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Added negative tests for canonical mismatch, disabled/reassigned principals, grant revocation, expired authority and missing worker authority. These use synthetic SQL/provider boundaries. Run independent assessment on deployed backend and installed variants and resolve findings. v0.15.0 acceptance: Run independent assessment on real backend and both installed variants; no penetration-test acceptance is claimed.

**Acceptance:** Test staff on gateway/non-gateway devices, raw-SMS denial, cross-group IDs/exports, replay, revocation races, forged sender/receipts, PIN spraying, cache leakage and credential reset abuse. Resolve critical/high findings and retain reproducible evidence.

### T052 — Build parser and financial invariant unit/contract suites
**P0 | OPEN | G4** — Owner: Backend lead + QA | Dependencies: T027, T028, T031, T032, T036

**This release:** Added repository/core and controller command-state tests; provider/database qualification still absent.

**Remaining:** Run actual PostgreSQL, protected storage, managed authentication and provider integration; test-only platform/JSON/transport boundaries are not production acceptance. v0.15.0 acceptance: Run actual PostgreSQL/provider, native framework and full integration acceptance. SQL recorder and platform doubles are not production evidence. v0.17 requirement: Added repository/core and controller command-state tests; provider/database qualification still absent. Verify on deployed services and real Android before closure.

**Acceptance:** Fixtures prove exact extraction and explicit rejection; properties prove no double credit, no balance from wallet field, no amount loss, no incorrect member inference and atomic rollback. Include reference conflicts and timestamp/currency edge cases.

### T053 — Test real physical-device receipt journeys
**P0 | OPEN | G4** — Owner: QA + operations | Dependencies: T017, T020, T021, T033, T037, T043

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Run authorized contributions through the actual carrier, SIM, receiving phone, backend, ledger, and Collect Admin. Include a Staff phone proving zero SMS access. Current remediation: A29: Complete all 12 operational journeys, errors, interruptions, real-user usability and device scenarios; not all acceptance cases covered.

**Acceptance:** Execute authorized controlled contributions on the intended carrier/SIM/phone. Retain anonymized evidence for delivery, capture, acknowledgement, allocation, ledger and Collect Admin. Include a Staff phone proving zero SMS access. Emulator/browser mocks alone do not close this task.

### T054 — Run interruption and upgrade fault-injection tests
**P0 | OPEN | G4** — Owner: Android lead + QA | Dependencies: T016, T020, T022, T036, T042

**This release:** Tested lost status after successful POST, repeated tap, mismatch, revoked token and durable unresolved state.

**Remaining:** Rehearse real process death, device interruption, provider unknown outcomes, upgrades and database restoration. v0.17 requirement: Tested lost status after successful POST, repeated tap, mismatch, revoked token and durable unresolved state. Verify on deployed services and real Android before closure.

**Acceptance:** Cover capture commit interruption, upload-ack loss, processing/posting timeout, offline, wrong SIM, revoked session/device, disk/queue saturation, historical replay, reboot/force-stop and app update with pending items. No silent loss, reassignment or duplicate financial effect.

### T055 — Measure native performance on the release build
**P1 | OPEN | G4** — Owner: Android lead + QA | Dependencies: T043, T044, T054

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Build and measure on selected devices. Offline qualification does not qualify live-network/SIM/battery/backlog performance; those require separately controlled connected tests.

**Acceptance:** Measure install size, cold/warm start, scrolling/jank, memory, battery, network and backlog drain on the selected low-end device. Agree budgets from measured needs and test minified/shrunk release artifacts rather than the historical large debug APK.

### T056 — Perform final native visual and operational acceptance
**P0 | OPEN | G4** — Owner: Product owner + QA | Dependencies: T044, T046, T047, T052, T053, T054, T055

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Compile/install and run visual, accessibility and operational acceptance with responsible owners; no source-only closure.

**Acceptance:** Compare native screenshots and interactions with frozen baseline across Admin/Staff, states and sizes. Apply only documented accessibility/platform adaptations. Record explicit sign-off by actual owners; no visual parity or production acceptance inferred from generated test counts.

### T057 — Set up CI and reproducible release build records
**P1 | OPEN | G4** — Owner: DevOps + Android lead | Dependencies: T003, T015, T052

**This release:** Updated exact v0.16 source-upgrade acceptance; no reproducible native APK build.

**Remaining:** Obtain pinned Gradle/SDK/dependencies and run real local/CI Android builds, APK boundary checks, SBOM and reproducibility. v0.17 requirement: Updated exact v0.16 source-upgrade acceptance; no reproducible native APK build. Verify on deployed services and real Android before closure.

**Acceptance:** Pin Gradle/Kotlin/Android dependencies, record source commits, run tests/lint/manifest permission gates and secret/dependency checks; produce SBOM and a reproducible artifact recipe. Exclude fixtures, BMDemo/BMReview/review controls and demonstration credentials from native production.

### T058 — Manage signing keys and release identities
**P0 | OPEN | G5** — Owner: Release owner + DevOps | Dependencies: T004, T057

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Confirm production IDs, version codes, key custody/recovery and signing implementation; sign QA and production candidates only through their separate controlled processes.

**Acceptance:** Establish package IDs, version codes, signing custody/recovery and update trust. Build signed non-debuggable optimized Admin-gateway and Staff artifacts; test upgrade from installed versions with credentials and queues intact. Never place signing keys in this handoff repository.

### T059 — Complete the chosen distribution and permission requirements
**P0 | OPEN | G5** — Owner: Release owner | Dependencies: T004, T015, T049, T058

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Qualify the selected installer/device-management/permission route and signed updates. Never distribute qualification artifacts as production.

**Acceptance:** For controlled distribution, qualify installer, grants, device management, revocation and signed updates. For Play, obtain applicable SMS use/declaration acceptance and current target-policy/privacy/data-safety clearance before release. Do not assume permission exemption.

### T060 — Prepare production migrations, worker activation and rollback
**P0 | OPEN | G5** — Owner: Backend lead + DevOps | Dependencies: T024, T029, T032, T036, T051, T057

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Reconcile and generate a normal migration from the additive native-principal/session-immutability proposal; apply after the unchanged base schema and coordinate backend rollout. Rehearse revoking old sessions without historical backfill, trigger permissions, rollback and actual worker activation. Nothing was applied.

**Acceptance:** Apply reviewed additive migrations in rehearsal/staging, validate backups and activation settings, then deploy a versioned backend. Rollback stops unsafe processing without losing sources or deleting committed ledger entries; retain compatibility for existing Collect clients.

### T061 — Instrument processing and financial operations
**P0 | OPEN | G5** — Owner: DevOps + operations | Dependencies: T023, T029, T032, T038

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Deploy redacted monitoring for capture gaps, queue/job age, unallocated backlog, parser failures, reference conflicts, ledger drift, and rejected access. Set thresholds and test actual escalation. Current remediation: A12: Implement authoritative event-history feed with actor, timestamps, reasons, original source and compensating ledger links. Current-state summary is not a complete audit history.

**Acceptance:** Alert on no recent capture where expected, oldest queue/job age, unallocated backlog, parser failure, duplicate conflict, ledger drift and rejected sessions/bindings. Validate alerts, escalation owners and redacted dashboards with actual failures.

### T062 — Rehearse restore, lost-phone and emergency-stop runbooks
**P0 | OPEN | G5** — Owner: Operations + DevOps | Dependencies: T016, T054, T060, T061

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Finalize named operators, provisioning/replacement, incident and support procedures; test with actual devices and services.

**Acceptance:** Perform a restore/reconciliation rehearsal, replacement of the sole receiver, emergency processing pause, token revocation and safe recovery. Prove stopped workers retain evidence and no restore creates a second active gateway or double credits.

### T063 — Run an explicitly bounded production pilot
**P0 | OPEN | G5** — Owner: Product owner + operations + QA | Dependencies: T056, T059, T060, T061, T062

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Authorize participants, transaction limits, monitoring period, success/stop criteria, and on-call ownership. Reconcile every controlled receipt before expanding rollout.

**Acceptance:** Define authorized participants, transaction/volume bounds, monitoring window, success/stop criteria and responsible on-call personnel. Reconcile each controlled receipt through App/Admin/ledger and authorized wallet evidence before expanding rollout. No arbitrary launch estimate replaces evidence.

### T064 — Hand over operations and authorize the production release
**P0 | OPEN | G5** — Owner: Product owner + release owner | Dependencies: T063

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Complete source, changed code/schema/test files, verification evidence, exact-source upgrade metadata and the current 65-task register are delivered. Signed artifacts, real managed-session/worker integration, deployed identity, training and operational release authorization remain. Current remediation: A30: Finalize missing typography/motion/locale/gateway/notification decisions and native build proof before final development-handoff acceptance.

**Acceptance:** Deliver final signed artifact checksums, backend release identity, trained Admin/staff, support/escalation contacts, recovery instructions, rights/retention record and release decision. Close all required tasks or formally document permitted non-blocking exclusions; no critical financial/access issue remains.

### T065 — Establish ongoing patch and reconciliation ownership
**P1 | OPEN | G5** — Owner: Operations + release owner | Dependencies: T061, T063

**This release:** No new change; original task and prior component progress preserved.

**Remaining:** Close all applicable acceptance criteria with real artifacts and responsible-owner authorization before controlled production promotion/activation.

**Acceptance:** Assign owners and cadence for OS/app dependencies, credential rotation, device health, daily reconciliation, incident triage, backup restore drills and future review changes. Keep the frozen design baseline immutable; change native UI through a versioned decision record.

