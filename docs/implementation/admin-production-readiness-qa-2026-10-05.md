> Historical source-checkout snapshot for publication review. Its prior local and hosted claims do not establish acceptance of this isolated candidate. See the publication-isolation inventory for source bytes and outstanding verification.

# Collect Admin production readiness QA — 5 October 2026

**Decision: NO-GO for production acceptance.** The current candidate has useful security and financial controls, and the focused automated checks pass. It still omits several explicitly requested Admin workflows and fields. Real browser testing also reproduced lost drafts, reset pagination, lost destinations during session restoration, and inaccessible detail values. The production domain serves a different, older application.

This is an Admin-only engineering, functional, access-control, UI/accessibility and release review. It is not a mobile-app review or certification of physical phones, provider delivery, production financial operations, or recovery. Computer Use was successfully resumed on the Mac after the native runtime repair; native Chrome reading, clicks, keyboard input and screenshots were used for the candidate UAT. The earlier Computer Use connection failure is no longer an open finding.

## Tested targets and provenance

| Target | Observed identity | What the evidence establishes |
| --- | --- | --- |
| Production — `https://admin.collect.ikanisa.com` | Version 1.2.4 build 23; source `f0b8b37a0e5c7e97a222127924fb3a7942e74ed2`; main JavaScript SHA-256 `a803d157fe84e44995f54ab9f2bbe7507c52fd2fc4205617f870b02703d552a6` | Native/browser login remains the historical WhatsApp OTP surface. New Cloudflare session, overview, team and gateway APIs return 404. No production login, OTP, mutation or deployment was performed. |
| Hosted candidate — `https://admin-preview.collect.ikanisa.com` | Cloudflare/email authentication; Worker version `780ee26c-2301-451e-be8a-39e7b359b57a` at 100%; main JavaScript SHA-256 `7a8f48621b4036e4908449c56c6fc394a751b3797b93ebaab44237637f5174a8` | JavaScript/bootstrap/version bytes match the local `build/admin-cloudflare` candidate. Anonymous security checks and login validation were tested; authenticated hosted role UAT was not completed. |
| Local full-stack candidate — `http://127.0.0.1:8897` | The same built frontend with the current Admin Worker, native Miniflare ASSETS, disposable D1/R2 and migrations 0001–0007; external email disabled | Actual Owner/Staff sessions and operating API reads, one confirmed payee activation, controlled polling failure and native UI checks. This is isolated full-stack proof, not hosted acceptance. |
| Current working source | HEAD `eed1925260780d079a638603f22837f095f943be`; pre-existing dirty/recovered work preserved | Focused current-source tests and review. This HEAD alone does not identify all uncommitted candidate inputs. |

The candidate source comparison found 815 of 821 captured inputs unchanged and six changed legacy/shared Admin files. The tested frontend bytes are known; the whole current tree has not been certified as a reproducible frozen build. Thirty focused Flutter inputs and thirty backend/test/migration/package inputs were separately hashed and checked for drift. No product source was changed by this QA review.

The local harness restarted after the interrupted turn and generated fresh UUIDs. Its current seed and restart copy describe the second run. The original complete seed manifest was not preserved; this limitation is explicitly recorded in [resume-provenance.json](../../.cache/admin-production-qa-20261005/local-uat/resume-provenance.json). First-run browser/polling/readback evidence remains valid for that run. The earlier successful payee activation does not describe the regenerated seed's current state.

## Verification results

| Layer | Result | Limit |
| --- | --- | --- |
| Focused Flutter tests | **100/100 pass**, 12 Admin/Cloudflare test files | Local tests; existing helpers omit the unchanged-session draft-remount and initial restore races reproduced below. |
| Focused Dart analysis | **No issues**, 11 active Cloudflare/Admin items | Static analysis, not runtime acceptance. |
| Backend syntax check | **Pass**, ten modules | Parsing only. |
| Backend integration/regression | **96/96 pass**: 75 Admin/shared cases, 21 adjacent member backend/migration cases | Ephemeral D1/R2 and fake email services; no mobile UI testing. |
| Additional audit fault injection | **Three reproduced failures**: password change, reset completion, invitation acceptance | Security state commits while its audit fails; ordinary success-path tests do not cover this storage fault. |
| Hosted anonymous API checks | **25/25 pass** | Authentication/origin/cache/header rejection checks only; no signed-in roles or production operating actions. |
| Candidate static hosting gate | **Pass** | Does not establish hosted account activation, data migration or delivery. |
| Existing live PWA gate on candidate | **26 failed expectations from an obsolete target profile** | It expects retired Supabase/referrer/service-worker behavior. These are not 26 demonstrated application defects. |
| Browser/native UAT | Mixed: confirmed passes, reproduced defects and explicit unverified cases below | Desktop Mac Chrome and browser viewport tests; no physical iOS/Android device or spoken screen-reader run. |

Do not sum these layers into a single production pass count. The saved first-run browser file contains 26 snapshots, including intermediate input attempts; it is not 26 independent passing test cases.

Evidence: [Flutter test log](../../.cache/admin-production-qa-20261005/flutter/tests.log), [analysis log](../../.cache/admin-production-qa-20261005/flutter/analyze.log), [backend report](../../.cache/admin-production-qa-20261005/backend/REPORT.md), [release report](../../.cache/admin-production-qa-20261005/release/REPORT.md), [data review](../../.cache/admin-production-qa-20261005/data/REPORT.md).

## Release-blocking findings

P1 means the requested acceptance cannot be met or a major operator workflow fails. P2 means a material defect or control gap requiring correction before release. External acceptance gates are identified separately from reproduced product defects. No demonstrated P0 incident, privilege escalation or double posting was found in this bounded review.

| ID | Priority / basis | Finding and operator impact | Required closure |
| --- | --- | --- | --- |
| ADM-01 | P1 — live deployment | Production serves the historical OTP build while the reviewed Cloudflare implementation is on preview. The new APIs are absent on production. | Bind the exact approved frontend/backend/configuration to the intended production domain, then repeat production acceptance. Preview proof cannot be transferred by assumption. |
| ADM-02 | P1 — reproduced browser/native | An unchanged-session poll disposes page state. An unsaved group name disappeared without navigation; native Users page 26–30 returned to 1–25. This also threatens locally held uncertain-write recovery state, although no duplicate financial effect was demonstrated. | Keep the repository/shell stable across identical actor/session refreshes. Preserve drafts, search, page and request-recovery state. Continue to revoke access on real actor/capability changes. Test through the real application overrides and shell. |
| ADM-03 | P1 — source + native | Users is a Collect profile directory, not all system people. Native local Users showed 30 people while Team showed three additional operators. App/Direct classification is absent. | Define an authoritative system-person identity mapping that includes Admin, Staff, App and Direct without accidental duplication; retain dedicated access management and stable six-digit IDs. |
| ADM-04 | P1 — source + native | User/member MoMo number/code is stored in schema but omitted from list/detail projections and Admin editing input. Core lists mask contacts for every role. Native member detail cannot show the requested payment identity. | Project and render authorized full WhatsApp, MoMo number and optional code in separate columns; show names as registered on MoMo. Direct members must not require WhatsApp/app authentication. |
| ADM-05 | P1 — source | User/member per-group and overall contribution totals are absent. Membership roles alone do not meet the requested detail. | Aggregate authoritative allocated contributions per person/group and overall, with owner/admin/member roles and consistent totals. Do not derive total amounts from truncated detail rows. |
| ADM-06 | P1 — source + browser | Reconciliations and SMS receipts are absent from the Cloudflare router/navigation. Member-submitted receipt review is a separate workflow. | Implement the two requested operational tables and their detail/review journeys, permissions, loading/empty/error states and route tests. |
| ADM-07 | P1 — source + local Staff UAT | Staff is denied every operating write, including the specifically permitted private-group creation and reconciliation proposals. Team denial is appropriately secure. | Add narrowly scoped server-enforced create/propose actions. Staff/app-created groups remain private; only Admin/Owner may publish or approve privileged outcomes. Do not grant broad operating writes. |
| ADM-08 | P1 — source + native | Transactions uses arbitrary provider references and lacks the requested uniform numeric public ID, payer name/last-three, complete payee number/code, extracted MoMo transaction/time facts and payer insights. | Persist the source SMS facts and distinguish the provider reference from a collision-safe, fixed-width public reference containing payer/payee suffixes. Specify unavailable/redacted facts honestly. Render each fact in its own column and complete the detail/payer history. |
| ADM-09 | P1 — reproduced accessibility | User and transaction facts are visually present but absent as readable values in browser/native accessibility output; native exposes field labels without the corresponding actual values. | Supply accessible label/value pairs while retaining copy/selection behavior. Verify keyboard traversal and spoken VoiceOver against the exact built artifact. Framework-level attribution remains source-supported rather than conclusively frozen to the artifact. |
| ADM-10 | P2 — three isolated fault probes | Password change, reset completion and invitation acceptance return 503 after the security change has committed, sessions were deleted and no account audit exists. | Commit the conditional success audit and security mutation atomically. Test audit failure rollback plus successful commit/lost-response recovery. |
| ADM-11 | P2 — source + native | Core lists are actual tables, but generic Record/Description/Status/value columns combine distinct facts. Team and related detail records still use cards. IDs retain labels/prefixes rather than numeric-only cells. | Use dedicated typed columns across all non-Overview data surfaces and subpages, preserving horizontal access on narrow screens. Apply the selected Revolut web/operator reference through shared components; no alternate visual authority. |
| ADM-12 | P2 — source + native | Transaction rows do not open from the body; only Record/Open controls do. Status shows verification rather than solely Allocated/Unallocated, and amount cells retain RWF. | Make the whole row keyboard-accessible and navigable, render allocation status in the requested column, and use numeric amounts in the Rwanda-only listing. Keep distinct verification controls in transaction detail. |
| ADM-13 | P2 — reproduced native + source | Opening details leaves the address at the list URL. Explicit reload under a valid Owner session goes through `/admin/session` and ends at Overview. Shareable detail links and return destinations are lost. | Use URL-reflecting detail navigation and preserve the intended authorized URI during initial session restoration/login. Test cold starts, reload, copy/open, Back and role denial. Do not infer reload behavior solely from the unchanged URL; both failures were separately observed. |
| ADM-14 | P2 — source + local search | Exact public-ID search works. Full phone query `+250788600002` returns zero for the known person. Search is literal matching over a small field set, without normalization, concepts or ranking. | Search ID, normalized phone, MoMo number/code, name, type and relevant group/role fields; add tested intent/filter interpretation and useful relevance. Do not claim semantic search from substring matching. |
| ADM-15 | P2 — source | Allocation member lookup lacks MoMo identity, confirmation prints raw body/UUID values, and unattributed allocation remains available. | Make allocation member-first with MoMo number/code verification, then resolve permitted group membership server-side and confirm the exact person/amount. Preserve current idempotency, receipt lookup and membership checks. |
| ADM-16 | P2 — source + native overview | The seven existing summary cards are clickable, but total collected, unallocated/open reconciliation and receipt summaries are absent. Users metric also excludes operator-only people. | Add authoritative complete summary counts/totals and links to matching filtered tables. |
| ADM-17 | P2 — source | Related detail sections stop at 200 with a truncation warning and no equivalent per-person pageable view. | Page/filter related memberships and history with stable ordering and visible completeness. Current transaction allocation totals are independently aggregated, so this is not a demonstrated total miscalculation. |

### Reproduction details for state and audit defects

**ADM-02:** On `/admin/groups/new`, the group-name input was `POLL-DRAFT-MARKER-20261005` at 08:46:18.525 UTC and empty at 08:47:05.236 UTC. URL and actor/session remained unchanged, with no Owner navigation. Auth polling start times increased from 498970.5 to 558982.6 milliseconds, a 60.012-second interval. [Polling evidence](../../.cache/admin-production-qa-20261005/browser/polling-draft.json) and [native pagination evidence](../../.cache/admin-production-qa-20261005/native/local-user-pagination-poll-reset.txt).

Source chain: [session refresh](../../lib/admin/core/cloudflare_admin_session.dart) lines 221–232 emits new identical-session data; [entry point](../../lib/main_admin_cloudflare.dart) lines 50–54 recreates the repository; [runtime](../../lib/admin/core/admin_runtime.dart) lines 157–161/255–267 reloads identity/configuration; [shell](../../lib/admin/admin_shell.dart) lines 43–49/64–83 replaces the protected child during loading. Form-local initialization then discards the unsaved values. Existing standalone form tests use a fixed repository and bypass this chain.

**ADM-13:** The native transaction detail correctly rendered QA-MOMO-2 with 50,000, while the address remained `/admin/transactions`. A real Cmd+R then showed `/admin/session` before settling at `/admin` under the same Owner. [Detail](../../.cache/admin-production-qa-20261005/native/local-transaction-detail.txt), [reload](../../.cache/admin-production-qa-20261005/native/local-deep-link-reload.txt), [settled state](../../.cache/admin-production-qa-20261005/native/local-deep-link-reload-settled.txt). Same-document Return/hash navigation sometimes preserved history; it is distinct from the full bootstrap failure. The session-loading redirect at `cloudflare_admin_app.dart:53–55` discards the requested URI and lines 84/110 unconditionally return to Overview; `initialLocation` alone is not the cause.

**ADM-10:** An aborting insert trigger on the isolated `admin_account_audit` table produced 503/service_unavailable in all three security flows. The new password was valid, the old password invalid, auth_version 2, active sessions zero and audit rows zero; invitation acceptance also activated the account. [Probe results](../../.cache/admin-production-qa-20261005/backend/password-audit-probe.json). Source: `deploy/admin-api/src/worker.mjs:246–256,264–271,333–335`.

## Access-policy acceptance

| Capability | Owner/Admin candidate | Staff candidate | Required disposition |
| --- | --- | --- | --- |
| Overview, Users, Groups, Members, Payees, Transactions, Ledgers reads | Available with data gaps | Available for implemented core areas | Keep server checks; complete omitted required pages/data. |
| Create a private group | Allowed | Denied | Permit narrowly scoped Staff creation; app creation stays private. |
| Make a group public | Allowed only through privileged operating path | Denied | Keep Admin/Owner-only publication. |
| Reconciliation read/propose | Requested page absent | Requested page absent | Staff may read and propose only; privileged approval/financial finality remains separate. |
| Manage users/payees, evidence, allocations/journals | Privileged workflow present | Denied | Keep broad denial; independent review/posting controls must survive new workflows. |
| Invite/remove team, change roles, dispatch team email | Owner protected; privileged checks present | Denied | Controlled hosted role UAT still needed. |
| WhatsApp app authentication | Historical production OTP; Cloudflare operator login is separate email/password | Not an app-user approval task | Keep app OTP automatic; Direct membership is not WhatsApp identity. No manual WhatsApp approval should be introduced. |

## Browser and native route coverage

| Journey | Observed result | Evidence / boundary |
| --- | --- | --- |
| Production login | Historical OTP surface; new implementation absent | Native `production-login.jpg`; hosted artifact/API readback. No OTP sent. |
| Candidate empty login and keyboard focus | Required-field errors visible; Email → Password keyboard focus works | Native `preview-empty-login.txt/.jpg`, `preview-keyboard-focus.txt`; no hosted authentication/reset submission. |
| Candidate anonymous protected links / incomplete invitation | Login guard or honest incomplete-invitation state | Browser `preview-anonymous-deep-links.json`, `missing-invitation.json`. |
| Login responsive layouts | Confirmed 320×740, 390×844 and 844×390 renders | Saved browser screenshots. The initial transient blank 320 capture is not classified as a product defect. |
| Local Owner and Staff login | Both authenticate against the actual isolated Worker | First-run browser snapshots/auth health; resumed native Owner Overview. Fake local credentials only. |
| Users list and pagination | Genuine table; 1–25 → 26–30 works; poll resets to first page | Native `local-users.txt/.jpg`, `local-users-page-2.txt`, poll-reset file. |
| User search/detail | Exact ID finds 940002; full phone search fails; correct detail visually renders | First-run confirmed input snapshots; native `local-user-search.txt`, `local-user-detail.txt/.jpg`. |
| Members | Four unique active people shown; requested App/Direct/full payment columns missing | Native `local-members.txt`; source review. Multiple memberships do not multiply the member count. |
| Members at 200% zoom | Vertical access works; two native horizontal scroll attempts did not move the table | `local-members-200-before.jpg`, `after.jpg`, `scroll.txt`. Horizontal native scrolling is inconclusive, not certified. Zoom restored to 100%. |
| Groups/new private draft | Default Private/Draft present; controlled draft lost on same-session poll | First-run browser and polling evidence. No group created. |
| Staff new group and Team | New group denied/redirected; Team denied with 403 | First-run confirmed Staff snapshots. Secure denial passes; missing permitted group creation fails functional acceptance. |
| Payee activation | Review/confirmation accepted; authoritative response and refreshed Active/version 2 observed | First-run saved/readback snapshots. Local disposable database only; not repeated after reseed. |
| Transactions and detail | Two rows, correct provider reference/detail amount; body click does not open; facts/columns incomplete | Native `local-transactions.txt/.jpg`, `local-transaction-row-body-click.txt`, detail files. |
| Detail reload | Valid session restored to Overview rather than the requested page | Native reload and settled-state files. |
| Team | Three operators; card presentation | Native `local-team.txt/.jpg`. No invitation, removal or role change submitted. |
| Ledgers, gateway, member receipts, email pages | Empty/limited states inspected locally; not financial/provider acceptance | Current route/source review and reported first-run traversal; final browser ledger did not persist separate snapshots for these routes. |
| Reconciliations/SMS receipts | Required Cloudflare routes absent | Router/navigation source review; reported unavailable-route response. |
| Logout, then reload | Login remains; no protected data rendered | Native `local-logout-coordinate.txt`, `local-logout-final.txt`. Local test tab closed afterwards. |

Native evidence is in [the native folder](../../.cache/admin-production-qa-20261005/native/); first-run browser captures are in [local-uat-snapshots.json](../../.cache/admin-production-qa-20261005/browser/local-uat-snapshots.json). Native accessible detail facts lack values even when screenshots show them. Spoken VoiceOver, contrast/comparator certification, other physical browsers and phone acceptance remain open.

An automation input mapping error and an accidentally truncated address-entry attempt were excluded as product bugs. The initial AX attempt to click Sign out did not execute it; the screenshot-based native coordinate click succeeded and reload confirmed logout. No password was saved in Chrome and browser zoom was restored.

## Controls that passed and concerns not substantiated

- Session tokens are random, hashed in storage and carried in Secure/HttpOnly/SameSite=Strict host-only cookies with eight-hour expiry; malformed/duplicate cookies and cross-origin writes fail closed. PBKDF2-SHA256 uses 600,000 iterations. Durable rate/body limits and current-authority fences are tested locally.
- Single-use hashed invitation/reset links expire; provider uncertainty does not automatically resend. Provider acceptance is recorded separately from delivery. Actual mailbox delivery and hosted password CPU/latency remain unverified.
- Six-digit numeric unique profile IDs, private group defaults and Admin/Owner-only public visibility changes exist. Staff publication is not over-permissive; its permitted work is missing.
- Financial inputs use bounded integers and BigInt aggregation. Schema guards bound allocations and exact journal totals, protect posted evidence/journals and require independent review/posting. A supplied allocation member must actively belong to the group.
- Operating writes use idempotency keys and durable receipt lookup; audits are transactional for those operations. The account-security audit defect above is a separate path.
- The suspected member-count mismatch was disproved: Overview and Members both count distinct people with active membership. The suspected duplicate linked journal was disproved by the unique allocation constraint. No duplicate payment/posting defect is claimed.

## Hosted release gates still open

The hosted D1 has seven migrations, 52 triggers and zero foreign-key violations. It currently contains one invited Owner with no password, no active Admin sessions and no Admin/Staff accounts. Operating groups, memberships, payees, transactions, outbox, gateway devices and operating audit tables are empty. One invitation email is provider-accepted; inbox arrival is unverified. `operational_migration_complete` is false. These are acceptance prerequisites, not authorization to bypass activation or migrate production during QA.

| Gate | Required acceptance evidence |
| --- | --- |
| Authoritative hosted account setup | Owner invitation receipt/activation through the intended workflow, followed by authorized Owner/Admin/Staff journeys and server-enforced denials. |
| Provider and security lifecycle | Real invite/reset delivery, expiry/single use, current-password changes, session revocation across tabs, email failure/uncertainty recovery and durable audit. |
| Operating migration and finance | Approved data mapping/reconciliation, exact target identity and migration state; controlled successful/denied evidence, allocation, independent reviewer/poster, idempotent replay and unknown-response recovery. No real fund movement as a QA shortcut. |
| Release identity and CI | Exact frontend/Worker/configuration/migration source, current successful CI receipt, corrected target-specific live gates and post-cutover acceptance on production. Latest queried CI failures were historical September runs; they do not diagnose current source. |
| Monitoring and recovery | Candidate Wrangler currently disables observability. Enable approved redacted logs/alerts and verify dispatch/cron/error alerts. A Time Travel bookmark proves capability, not restoration; exercise approved disposable recovery and measure RPO/RTO and data reconciliation. |
| Performance and devices | Measure hosted password hashing/CPU/error/load budgets and long-table responsiveness. Complete intended physical browser/device and spoken screen-reader journeys. Desktop viewport resizing and native Mac Chrome are separate evidence. |

## Remediation order and review closeout

1. Fix same-session state preservation and account audit atomicity; add regression cases through the real shell and injected storage failures. Preserve revocation and request-recovery guarantees.
2. Complete authoritative system people/App–Direct/payment projections, contribution aggregates, reconciliation/SMS surfaces, narrow Staff actions and transaction SMS/reference/details. Use dedicated-column tables throughout non-Overview pages.
3. Correct accessible detail values, destination-preserving routing, transaction interaction/status/amount presentation, search and summary coverage. Verify the exact built candidate with native UAT, including narrow horizontal table access.
4. Establish hosted account/provider/operating acceptance, corrected release gates, monitoring, recovery and exact-source CI. Cut over only the approved artifact/configuration, then repeat acceptance on production.

The QA review is complete with a **NO-GO** decision and these unresolved gates. No deployment, product implementation, commit/push, live data/account/financial mutation, OTP, invitation/reset dispatch or provider configuration change was performed. QA artifacts were saved separately from the pre-existing dirty work. The disposable local session was signed out and its tab closed; only the owned QA runtime is stopped during closeout. Production and preview login tabs remain available for review. No mobile-app work was added.
