# Receipt successor contract — proposed bounded implementation

Status: technical proposal for root review before implementation. Staging owner: `/root/settings_finish`. Root alone promotes canonical changes. This proposal creates no hosted, device, signing, SMS, or release authority.

## Outcome and current gap

Support three explicit, reasoned actions without mutating an original receipt: retry a provably uninvoked attempt, approve a clearly labelled duplicate after conclusive reconciliation of the observations actually available, and issue a correction supported by new valid financial evidence. A primary ensure remains an ensure: the existing lifetime `UNIQUE(payment_id, template_key)`, `snapshot_id UNIQUE`, and automatic `UNIQUE(outbox_id)` constraints remain unchanged.

Current services expose original-request recovery, cancellation of untouched queued receipts, immutable financial/content evidence, device grants, final server arms, multipart callbacks and archive acknowledgement. They do not expose a safe successor operation. The Android journal reserves durably **before** final arm and invocation. Its `invocationStartedAt` is a reservation timestamp; a reservation, exception, framework failure, expired grant, lost response, missing callback or unknown lookup is not proof that SMS was never invoked. Existing archive acknowledgement proves a particular complete set of framework observations, with `carrier_proof=false`, `delivery_proven=false`, `send_authority=false`. Later contradictions remain possible and must remain actionable.

## One architecture

Add `collect_receipt_successors`, with a separate immutable approval/work queue and execution identities. No successor is inserted into `collect_hybrid.sms_notification_outbox`. Original primary readers and ensure operations keep their one-row assumptions. New readers explicitly join lineage; new signed successor gateway operations dispatch only approved successor work. The existing manual five-read MCP profile and existing unattended seven-action profile remain closed.

An owner first inspects a backend-derived candidate, sees immutable preview and proof classification, and approves one exact candidate with a request UUID. Approval is durable work, not permission to invoke SMS. A fresh configured live run and authenticated enrolled device subsequently materialize the exact approved content and reserve the existing shared action/segment budget atomically with a new grant. Final arm rechecks the old lineage, financial source, current recipient/consent/language, mode, stop, run, device and health. No changed preview is silently substituted.

## Proof classes and allowed actions

Every action is constrained by a backend classification. The UI cannot supply or override it.

| Classification | Required evidence | Allowed successor |
| --- | --- | --- |
| `never_armed_closed` | No assisted claim/confirmation/attempt/arm; no automatic arm; original automatic grant, if any, irrevocably closed by a new backend closure under the same outbox→attempt locks used by arm. Closure is checked by every later arm, and the original queued receipt is suppressed atomically. | `retry_uninvoked` |
| `untouched_cancelled` | Existing immutable manual pre-send cancellation, no assisted or automatic transport evidence, valid original financial evidence. Original remains suppressed. | `retry_uninvoked` only with fresh explicit reason, source and recipient review. |
| `framework_complete_reconciled` | Exact original automatic arm and all `2*n` callback bindings; all referenced authenticated callback request hashes and observations; no duplicate conflict, failure, unknown local phase or outstanding original request; verified signed device terminal journal evidence linked to the exact reservation and callback set; positive complete current fold and archive acknowledgement. | `approved_resend`, explicitly labelled duplicate. This establishes known app/framework observations, not carrier delivery or recipient receipt. |
| `reversal_notice_eligible` | A new immutable reversal snapshot and balanced reversal journal whose `reverses_entry_id` is the original receipt journal; original payment is now reversed; old attempt is either closed/uninvoked or reconciled complete as above; same member/group, active eligible recipient and current contact/consent. | `correction`, specifically a reversal notice. |
| `outcome_unknown`, `contradictory`, `assisted_transport_present`, `incomplete`, `legacy_unverifiable` | Any unresolved, missing, ambiguous or contradictory fact. | No retry, resend or correction enqueue/arm. Read evidence and retain a durable exception. |

The retry proof comes from irreversible exclusion of any future authorized original arm, not elapsed time. If an original arm wins the race, closure fails. Existing final-arm native code requires an initial non-replayed acknowledgement before invocation. Backend closures must also fence any queued original job without an automatic attempt, so ordinary dispatch cannot later create an original grant.

For an already armed unknown attempt, this stage does not accept an operator assertion or a generic “not sent” form. Current journal states cannot supply conclusive non-invocation after an arm. Such work remains blocked. A later separately reviewed protocol could admit stronger device/provider evidence; this contract does not invent it.

Resend reconciliation requires the full verified evidence set and signed terminal journal export, not archive acknowledgement alone. A duplicate may already reach the member: the UI says this and the renderer labels it. It never claims carrier delivery. A later contradiction invalidates a pending approval or unarmed successor. If a successor has already been armed, stop further lineage work and open a durable exception; do not erase either receipt or claim a reversal of SMS.

Correction uses the actual new financial evidence already supported by Collect: a canonical reversal journal and reversal balance snapshot. There is no existing trusted replacement-payment lineage. An unrelated payment, cross-member allocation, manually supplied replacement amount, or an old receipt renamed “corrected” is refused. Sending another member's allocation is outside this contract. Receipt operations do not reverse/post/reallocate money.

## Backend data and immutable records

All new schemas/tables have RLS enabled, no direct public/anon/authenticated/service table grants, explicit SECURITY DEFINER entry points, `search_path=''`, immutable evidence triggers and restrictive FKs. Privileged RPCs are the only write paths.

1. `lineage_heads(root_outbox_id PK, revision)` — monotonic revision advances for closure, approval/revocation, successor grant/arm/status and every relevant original callback or signed journal fact, including a callback that leaves the original seven-state transport value unchanged. Outbox action revision alone is insufficient.
2. `original_closures(id PK, root_outbox_id UNIQUE, original_attempt_id nullable UNIQUE, actor/session, original_revision, transport_revision, request_id UNIQUE, proof_sha256, reason_code, reason, closed_at)` — immutable exclusion of future original grant/arm. Never clears existing evidence or returns an attempt to `granted`.
3. `terminal_evidence(id PK, original_attempt_id, device/key/installation, exact signed request/hash, reservation hash, journal object/manifest hash, all callback request refs, invocation_returned, no_invocation_exception, local conflict/head sequence, backend folded proof hash, recorded_at)` — append-only authenticated evidence. A free-form operator reference cannot create this row. Distinct later evidence remains retained.
4. `approvals(id PK, root_outbox_id, predecessor_successor_id nullable, sequence, action, reason_code, reason, actor/session, expected_root_revision, expected_lineage_revision, preview_sha256, source_kind/id/hash, destination/policy/consent revisions and hashes, language, content_policy_version, approval_expires_at, request_id UNIQUE)` — exact immutable intent. Root→successor chain is acyclic, every predecessor belongs to the same root, and sequence is serialized by the lineage head. Only one pending approved execution per root; a second request cannot implicitly replace it.
5. `approval_events(id PK, approval_id, event_kind, revision, immutable request/result, actor or authenticated device/run, recorded_at)` — approved/revoked/expired/blocked/executed status is folded from retained events. A read never silently marks work handled.
6. `jobs(id PK, approval_id UNIQUE, root_outbox_id, predecessor_successor_id, source snapshot and journal, backend-derived immutable financial amount/balance/time/reference, destination and its hash/revision, consent/policy/language, body/hash, proof hashes)` — immutable execution payload, separate from the original outbox. No amount, balance, body, reference, destination, language override is accepted from a mutation caller.
7. `attempts(id PK, job_id UNIQUE, run/principal/device/fence/policy/reservation, body/destination/proof hashes, segment_count, issued/expires, state)` plus immutable `arms`, callback bindings, signed requests, callbacks and archive acknowledgements — equivalent monotonic one-invocation safeguards to the current automatic sender, using distinct identities. No state transition makes an attempt reusable.
8. `owner_requests(request_id PK, actor, action, exact input hash, result)` — immutable original-request recovery, including closure, approval and revocation. Same UUID/actor/exact input replays the same receipt; changed input/actor is a conflict. A persisted mutation refusal is also a recorded outcome.
9. `content_policies(version, immutable owner authorization and choices)` — append a new successor-only decision rather than changing the retained v2 financial policy decision (`correction_or_resend=false`). Immutable new renderers support rw/en/fr. Retain old content proofs unchanged.

Preview contains the full exact text, masked recipient, contact/source/language/revision evidence, duplicate/reversal label, and explicit proof limits. The stored destination remains private. Retry uses normal recorded-savings wording from a current eligible receipt snapshot. Resend prefixes that wording with a localized duplicate label. Correction states that the referenced savings record was reversed and shows only the immutable member balance recorded at that reversal, its timestamp and backend-derived reference. It does not report a current live balance or another member/group total.

## Financial/source predicates

Retry/resend reuse the actual current `snapshot_is_eligible` rules: canonical posted positive RWF payment; bound provider confirmation; Rwanda receiving/parser scope; active ikimina and active account-independent allocated member; exact balanced two-line receipt journal; no reversal; immutable original receipt snapshot. Validate current policy enabled, explicit consent, contact revision/hash, language, content and feature flag again at materialization and arm.

Correction has a new `reversal_is_eligible(root, reversal_snapshot)` predicate: immutable receipt and reversal entries for the same payment/member/group; `reverses_entry_id` equals the original journal; balanced two-line reversal debit member-savings/credit MoMo asset with exact original positive amount; `event_type='reversal'`, negative exact delta, finite timestamp and non-negative immutable member balance; canonical payment `reversed`; same recorded provider-confirmation/Rwanda evidence; active member/group/current contact/consent/language. The original payment's reversed state is never passed to the posted-receipt predicate or relabelled eligible for resend.

Every preview hash includes the financial source identity/version/hash, original revision, lineage revision, complete transport proof hash, current contact/consent/policy/language and exact body/hash. Source metadata is backend derived. Inspection is valid 60 seconds; approval must bind that inspection within its window. Approval expires 15 minutes after creation; expiry retains the work and requires an explicit new reviewed approval. Paused approvals do not gain unlimited later send authority.

## Closed public owner APIs

Current email owner session + `platform_owner` + `payments.read`, `notifications.read`, `system_health.read` are required for reads; mutations add `notifications.manage`. Use `collect_receipt_actions.actor(...)` semantics and revalidate after lock waits. No legacy WhatsApp identity fallback.

- `admin_inspect_receipt_successor_v1(p_outbox_id, p_action, p_source_snapshot_id)` — derives all eligibility/evidence/preview. Source ID selects a backend-validated candidate; it is not an arbitrary financial override. For retry/resend it must equal the original receipt snapshot. For correction it must identify the exact bound reversal snapshot. Returns one closed DTO with sample deadline and finite reason codes; unavailable rows are redacted consistently.
- `admin_close_unarmed_receipt_v1(p_request_id, p_outbox_id, p_expected_root_revision, p_expected_lineage_revision, p_reason_code, p_reason)` — explicit irreversible closure. It does not enqueue or send. Initial unarmed grant expiry is neither required nor sufficient; current arm absence and full exclusion proof are required.
- `admin_approve_receipt_successor_v1(p_request_id, p_outbox_id, p_action, p_source_snapshot_id, p_expected_root_revision, p_expected_lineage_revision, p_preview_sha256, p_sample_valid_until, p_reason_code, p_reason)` — rederives and compares the entire candidate. Reason 8..500 characters; finite action-specific reason code. Emits exact immutable intent/result/audit record, no sender authority.
- `admin_revoke_receipt_successor_v1(p_request_id, p_approval_id, p_expected_lineage_revision, p_reason)` — allowed only before final arm. Serialized against grant/arm; a granted job is irreversibly closed, not reset. It cannot cancel an already armed SMS.
- `admin_get_receipt_successor_request_v1(p_request_id)` — actor-bound `recorded` / `in_progress` / `not_recorded`, same original request recovery semantics. A UI timeout never chooses a fresh UUID or auto-submits the old action again.
- `admin_get_receipt_successor_v1(p_approval_id)` and `admin_list_receipt_successors_v1(p_outbox_id, p_after, p_limit)` — bounded joined lineage/evidence/action history with finite DTOs and stable keyset ordering. Redaction and session checks apply independently to every read.

Reason codes: retry `definitely_not_invoked`; resend `member_requested_duplicate` or `approved_duplicate_copy`; correction `canonical_reversal_notice`. Generic resend because `send_failed` or “timeout” is refused. All results explicitly carry `financial_action=false`; approvals/closures also `send_action=false`, retained primary true, carrier/delivery proof false.

## Automatic gateway consumer

Use a new closed endpoint `collect-receipt-successor-gateway`, version 1 and fixed audience `collect.receipt-successor-gateway.v1/<project-ref>`. This avoids collision with existing dispatch2/archive3/native-retention5 versions. Reuse the enrolled device key verification/fixed-host transport; do not accept an operator token on the handset or arbitrary destination/host.

Finite signed actions: `dispatch_grant`, `arm_dispatch`, `callback`, `attempt_status`, `terminal_evidence`, `archive_attempt`, `reconcile`. Original terminal evidence is read-only to sending: it attests retained actual original journal facts and cannot issue a grant. Every request is immutably journalled before network I/O. Unknown reconciliation or a replayed redacted grant/arm response never yields body or send authority.

Grant chooses one approved unexpired successor for the authenticated device's current authorized run/collection. Before creating its immutable job/attempt, require mode Live-limited/Live, no emergency stop, current principal/run/device/policy/scope/health/SIM and feature flag. Recompute exact approved preview/proof under locks. Reserve budget using existing `collect_receipt_operations.reserve_budget(run,fence,attempt-or-grant-reservation,collection,device,1,n)` so normal and successor work share all eight caps. Reservation/job/attempt/grant/request commit atomically. Existing run completion continues to count reservations; a separate immutable execution receipt links approval to run and audit. It does not pretend a primary business event was handled by a successor.

Shadow/Dry-run may inspect candidates and record non-authorizing observations; no execution job, segment reservation or grant. Paused/emergency stop/revoked principal/device denies grant and arm. Owner read/revocation remains available. Explicit approval records can be retained while paused but expire on the same short deadline.

Native integration uses an immutable encrypted sidecar route for each new successor attempt (`attempt_id`, namespace/version, job/root/approval IDs, exact hashes) committed before invocation reservation. Keep original journal records unchanged. The route survives hot/cold retention and recovery, routes callbacks/status/archive to the correct endpoint, and never authorizes a second invocation. The existing dispatch engine still validates body/destination/segments, fsyncs, requires the initial final arm, checks current SIM/permission/network/pause and crosses the same sender seam at most once. An unrecognized route or missing route proof closes execution and retains uncertainty.

The background coordinator requests successor work through the new endpoint using current configured authority; a definite `NO_ELIGIBLE_SUCCESSOR` may then allow ordinary primary polling. Unknown successor-grant outcome is reconciled by its original UUID and does not become a successful empty queue or alternate send. Ordinary dispatch2 cannot see successor jobs. There is one sender, the organization-owned Android gateway.

## Lock order, recovery and contradiction fences

Dispatch order is current operations policy→run→original outbox→original automatic attempt→lineage head→approval/job→successor attempt; device proof uses the existing current safe order. Owner mutation first locks auth/roster authority, then the same policy (for closure/revocation if needed) and receipt/lineage order. Existing callback starts with original outbox→attempt and may advance/invalidate lineage without acquiring the policy lock. New callback follows original outbox→lineage/job→successor attempt. No callback waits on policy while holding receipt evidence locks.

Financial/contact/policy/consent eligibility locks follow the current NOWAIT source-lock approach, returning a finite busy refusal rather than introducing payment→receipt versus receipt→payment deadlocks. Recheck natural session, preview, approval, run and grant deadlines after waits. No retry changes lock order or converts busy to handled.

Every insertion of a new original callback, terminal attestation or contradiction advances the lineage proof head. A changed fold causes pending work to block; a late negative/conflicting fact causes a durable stop exception and refusal at final arm. Successful identical callback request replay retains its original result without manufacturing a new observation. Reusing an original mutation UUID cannot change action, selected source, reason, proof, approval or owner.

## Required indexes and bounded scans

- Original closures unique root and nullable original-attempt identity; request UUID unique.
- Lineage head PK root; approvals `(root_outbox_id, sequence)` unique; pending admission serialized by the head. Immutable event fold uses `(approval_id, revision)` unique and `(approval_id, recorded_at, id)` keyset index.
- Eligible pending work index `(approval_expires_at, created_at, id)` restricted to the materialized folded admission state; head/event truth remains authoritative. Candidate scans are capped (25) and skip locked work without treating it as no work.
- Jobs unique approval; attempts unique job; arms unique attempt; callback bindings unique `(attempt_id, segment_index, callback_kind)`; immutable requests UUID unique across the relevant enrolled-device request namespaces.
- Callbacks `(attempt_id, callback_id, recorded_at, request_id)` and original terminal evidence `(original_attempt_id, recorded_at, id)` support complete bounded fold/contradiction queries.
- Execution receipts `(run_id, approval_id)` plus `(root_outbox_id, sequence)` and bounded admin root/action/time indexes; use the existing shared reservation daily indexes and do not create separate successor quotas that bypass primary usage.

## Actual integration consumers and ownership boundary

All implementation occurs under `.cache/receipt-successor-workflows-20261001/` until root accepts a sealed packet. No canonical mutation here.

- New migration appends successor tables/predicates/RPCs/protocol. Minimal affected existing automatic-arm/grant/callback guard functions gain closure and lineage checks with exact predecessor byte/hash expectations. No original schema uniqueness weakening, retained row mutation, or rewrite of old migrations.
- New `supabase/functions/collect-receipt-successor-gateway/` handler/wire validates closed signed envelopes, request hashes, finite actions, strict results/redaction/deadlines and enrolled/revoked device rules. Existing gateway endpoint remains compatible.
- Android `GatewaySignedBackend`, `GatewayBackgroundCoordinator`, dispatch route/sidecar and callback/retention/recovery consumers integrate the endpoint and original terminal-evidence export. Preserve other worker changes; root resolves shared-file promotion. Exact original primary dispatch and archive tests stay required when their consumers change.
- Admin add successor models/SDK/provider/controller/checkpoint/card. Use existing `_AdminReceiptRepository`/runtime part split without overwriting receipt/exception mixins. Notifications/investigation explicitly show primary→successor lineage, immutable previews, finite eligibility and evidence, action status and original-request recovery. Audit navigation points to owner request, old receipt, successor approval/job, run and attempt. Existing transaction investigation cardinality stays one primary plus an explicitly typed bounded successor collection.
- Existing five-read MCP server/allowlist and unattended contract/runner/Edge supervisor actions remain unchanged. No arbitrary ensure/enqueue/send RPC is exposed through either existing profile.

## Acceptance plan (actual execution required, no inferred totals)

Backend local PostgreSQL cases must observe actual strict DTOs and denied writes: closed schemas/RLS/grants; immutable rows; retained primary uniqueness and duplicate ensure; never-armed closure versus racing arm/grant; assisted presence refusal; bare expiry/failure/archive ACK refusal; exact terminal evidence authentication, callback set, hash/installation/phase/exception and late conflict fences; all three source predicates/languages; correction reversal proof, unrelated/cross-member source refusal; source/recipient/consent/language changes; preview and approval expiry after waits; UUID exact replay/conflict and same-owner lookup; bounded lineage admission; paused/Shadow/Dry-run/live caps shared with primary sends; quota/day boundary; source-lock contention; crash/unknown-request recovery; revocation race; successor callback fold/archive/late contradiction; joined audit/read redaction.

Edge checks consume the actual PostgreSQL-produced fixtures, reject extra keys/overrides/invalid signatures and cross-namespace replay, and prove no grant/arm replay releases text/authority. Native checks exercise fsync failure, missing/wrong route, no initial arm, timeout/unknown, pause/SIM/permission/network changes, at-most-once seam, callback routing, cold archive and restored inactive route/journal evidence. These are local code evidence; physical-device and carrier evidence remain separate.

Admin checks cover strict closed observed DTOs, sample/source/lineage changes, proof classifications, explicit immutable preview/reason, action-specific wording, session/permission change while awaiting, request bookmark/recovery, busy/refusal handling, stale callbacks and expired approval; narrow widget/keyboard/reader/responsive route checks using the selected Revolut operator references. No visual/comparator acceptance is inferred from unit tests.

Freeze changed and transitive source, selected skill, tool/runtime/dependency closure before affected checks; retain every failure and actual terminal receipt. Seal only verified exact artifacts. Required predecessor regressions are selected by changed consumers, not wholesale reruns of unaffected Settings suites.

## Review decision requested from root

Accept or adjust this single additive queue contract before implementation. Material boundary choices: original five-read/primary uniqueness stay closed; retries require irreversible unarmed closure; resends require full authenticated reconciled framework/journal evidence and duplicate wording without carrier claims; corrections initially cover actual canonical reversal notices, with unrelated/cross-member replacement allocation refused. Broader correction types require a trustworthy financial lineage producer, not receipt-operator invention.
