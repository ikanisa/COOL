# Collect hybrid membership — durable execution goal

Started: 3 September 2026  
Owner: IKANISA / Collect  
Lead route: `flutter_mobile_app_engagement`  
Status: **ACTIVE — backend/Admin cutover and local browser QA pass; physical pilot and accountable acceptance remain open**

Latest continuation: production is at 121 migrations with the directory fix
deployed and live-verified. MCP Keychain authentication and real stdio health/list
PASS; 17 MCP tests PASS. The one-minute monitor is ACTIVE in read-only/no-send
mode. Buri Munsi / 41258 is the selected receiving route; the owner is the approved
second Admin. No further generic deployment approval or pilot/calendar selection
is required. [Current evidence](../../release/HYBRID_CONTINUATION_DEPLOYED_2026-09-03.md)
supersedes historical 120-migration, local-only and missing-credential notes below.

## Goal

Deliver one production-grade Collect membership and savings journey for authenticated app users and account-independent members who pay through Rwanda MoMo USSD. Admins must be able to create private groups, register or import reviewed member rosters, and configure deterministic receiving assignments. Permitted receipt SMS evidence must be retained exactly, parsed and allocated by the authoritative backend, posted once into a balanced RWF journal with immutable member/group balance snapshots, and routed to either the app or an assisted Mac Messages SMS queue. Codex must inspect that queue at one-minute cadence through narrowly scoped tools and obtain action-specific confirmation immediately before every real SMS send.

The goal is complete only when every requirement below has current authoritative evidence. Local tests, deployment, hosted readback, synthetic UAT, physical UAT, provider/store state and owner acceptance are separate gates.

## Authority and hard boundaries

- Local code, tests, documentation and synthetic data: authorized.
- Hosted production reads back at 120 migrations with the five hybrid Edge Functions and current Admin PWA deployed. Every hybrid rollout flag remains OFF; deployment is not feature acceptance.
- No fabricated Auth user for an offline member. No name-plus-last3 account authentication.
- No service-role or unrestricted SQL surface in the app, browser, prompt or MCP operator.
- No automatic payment guess from amount/time alone and no automatic choice among multiple eligible groups.
- No retrospective notification of imported history by default.
- No real payment, OTP, push, SMS, store upload, Git push or new production mutation without the applicable explicit authority.
- Assisted Messages mode is approved as a design decision. Every imminent SMS still requires exact recipient/content confirmation.

## Requirement and proof matrix

| ID | Requirement | Completion evidence | Current state |
| --- | --- | --- | --- |
| G-01 | One member registry for app and offline identities | Migration/readback, collision/concurrency tests, deletion/link continuity | Registry and unified directory are deployed; exact-phone claim remains flag-OFF pending authenticated member acceptance |
| G-02 | Private admin-assisted group creation plus existing app/public flows | Admin RPC/UI UAT, visibility/origin/permission readback, regression tests | Backend/Admin deployed and local automated browser QA passes; production-authenticated journey remains open |
| G-03 | Manual, paste, CSV/XLSX and reviewed PDF/image roster intake | Row-count reconciliation, review UI, duplicate/error UAT, OpenAI structured extraction evaluation | Deterministic imports and review-gated extraction are deployed; one consented live OpenAI evaluation and hosted Admin UAT remain open |
| G-04 | Explicit receiving route and per-member group assignment | Schema, uniqueness/validity rules, multi-group ambiguity tests, admin UAT | Production migration readback and synthetic UAT pass; flag remains OFF and hosted Admin/pilot UAT is open |
| G-05 | Exact permitted raw receipt capture and deterministic parse | Native/Edge tests, duplicate-source tests, approved physical capture | Ingestion/parser functions are deployed with exact source readback; physical receipt capture remains open |
| G-06 | Intent and direct-USSD allocation without amount/time guessing | Atomic SQL, one/many/none/disagreement/retry/concurrency tests | Financial core is deployed and flag-OFF; synthetic finality/concurrency pass while physical production-pilot UAT remains open |
| G-07 | One payment, balanced RWF journal, reconciliation and immutable after-balances | Constraint/readback, concurrent posting/reversal/restore tests | Production schema/privileges read back; posting/reversal/replay/concurrency and V23 recovery rehearsal pass; live pilot remains open |
| G-08 | Offline/app channel routing and verified account claim | Full-number link audit, history continuity, reachability/preference/suppression UAT | Claim and routing backend deployed flag-OFF; live Auth/member continuity acceptance remains open |
| G-09 | Durable SMS outbox with exact easyMO template | Queue/claim/fence/revision/uncertain-outcome tests; zero replay of history | Outbox and exact Buri Munsi renderer deployed flag-OFF; carrier/physical UAT remains open |
| G-10 | Narrow Collect operator/MCP tools and one-minute heartbeat | Tool authorization tests, no-SQL surface, idle/backlog/revocation/overlap dry run | Edge deployed; read-only host profile registered; 11 MCP tests pass; heartbeat PAUSED pending credentials, active legacy-sender takeover and physical dry run |
| G-11 | Admin/member UX, accessibility, localization and recovery states | Compact/large/dark/large-text/screenshots; keyboard/screen-reader/device UAT | Full local Admin matrix passes 69/69 across 23 routes and three viewports; hosted/manual screen-reader/zoom/dark/device acceptance remains open |
| G-12 | Security, privacy, observability, recovery and controlled release | Advisors reviewed, threat model, logs/metrics, clean replay/restore, hosted + physical UAT, approvals | Production readback, privilege cutover, warning inventory and recovery rehearsal pass; physical/provider and accountable approvals remain open |

## Execution sequence

1. **Direct money path:** receiving assignments, deterministic direct-USSD allocator, canonical RWF journal, snapshots, reconciliation exceptions and reversals.
2. **Operations input:** assisted group/route/roster admin experience; deterministic CSV/XLSX first, then reviewed OpenAI extraction for PDF/image.
3. **Identity continuity:** offline roster reads, verified full-number claim/link, account deletion retention and notification policy.
4. **Notification control plane:** backend-owned receipts, no-send outbox, fenced claims, attempts and uncertain outcomes.
5. **Operator layer:** narrow MCP/WebMCP facade, authenticated health/list/claim/outcome commands and one-minute no-send heartbeat; resolve easyMO ownership before cutover.
6. **Evidence and release:** full synthetic/concurrency/accessibility/recovery suites, approved physical Android/iPhone/feature-phone UAT, then separately authorized deployment/store/activation steps.

## Mandatory quality gates

- **Gate 0 — scope/authority:** environment, actor, data and external-action authority recorded.
- **Gate 1 — product truth:** smartphone/feature-phone journeys, private/public semantics and ambiguity behavior match the brief.
- **Gate 2 — architecture/security:** server-authoritative decisions, RLS/ACLs, no secret exposure, immutable evidence, idempotency and balanced accounting.
- **Gate 3 — implementation:** typed contracts, compatibility migration, narrow and broad tests, clean migration replay.
- **Gate 4 — UX/accessibility/performance:** responsive and large-text states, semantics, low-end/mobile evidence and bounded queues/imports.
- **Gate 5 — release:** backup/restore, hosted readback, exact build provenance, provider/store and physical device gates separated.
- **Gate 6 — closeout:** all G-01…G-12 proven, open issues resolved or accepted by owner, final UAT record and rollback/runbook complete.

## Current evidence baseline

- Base HEAD: `b256af455c1d19a64f0e13c7d0c0c380c1cfac80`; the implementation is a dirty, uncommitted worktree and preserves unrelated edits.
- Hosted migration state: 120 migrations through `20260903092500`; all five hybrid flags remain OFF. The new local-only `20260903200322` directory presentation correction is pending review/deployment.
- Network-disabled production archive rehearsal: [V23 report](/Volumes/PRO-G40/COOL/docs/release/PRODUCTION_COPY_UPGRADE_REHEARSAL_V23_2026-09-03.json) passes 23 reviewed migrations while preserving 116 pre-existing protected tables and 202,926 rows. This is not production GO.
- Edge/Admin deployment: five hybrid Edge Functions are active with exact source readback; Admin PWA version `871850eb-a270-489a-b400-b9facf6b5532` serves 100% traffic and passes its live gate.
- Automation: `Collect feature-phone receipts` exists as a PAUSED one-minute task; it has not connected to production or sent a message.
- Local foundation evidence: [implementation status](IMPLEMENTATION_STATUS.md) and [UAT matrix](UAT_QA_MATRIX.md).
- Local Admin browser evidence: [SMS-route and full-matrix QA report](/Volumes/PRO-G40/COOL/docs/release/HYBRID_ADMIN_BROWSER_QA_2026-09-03.md).
- Canonical operator constraints: [Codex operator contract](CODEX_OPERATOR_CONTRACT.md).
- Current hosted/release boundary: [production cutover report](/Volumes/PRO-G40/COOL/docs/release/PRODUCTION_CUTOVER_2026-09-03.md).
- Latest continuation: [authenticated Admin UAT and corrections](/Volumes/PRO-G40/COOL/docs/release/HYBRID_AUTHENTICATED_ADMIN_UAT_2026-09-03.md). Second-Admin fresh login/reload and hosted read-only navigation PASS; 562 Flutter, 15 new database and 11 MCP tests PASS. New directory corrections are local-only; hosted writes, runtime credentials, legacy takeover and physical acceptance remain open.
- Public distribution decision: [technical-readiness decision](/Volumes/PRO-G40/COOL/docs/release/PRODUCTION_GO_TECHNICAL_READINESS_2026-09-03.md) remains NO-GO pending Android signing review and release-owner signoff, plus separate store/publication authority.

## Definition of done

Do not close this goal because code compiles, migrations deploy or a synthetic suite passes. Close only after the completion audit maps every G-ID to current evidence at the same scope: production readback for deployed state; real authenticated Admin/member sessions for access; physical device and feature-phone evidence for capture/send; actual provider/store state for distribution; and explicit owner acceptance for activation. Any unverified item remains open.
