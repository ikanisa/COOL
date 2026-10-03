# Receipt backlog and event foundation — local candidate

Migration: `supabase/migrations/20260930230100_receipt_backlog_events.sql`.
This foundation grants no scheduler, unattended principal, payment-posting or
SMS-sending capability. Existing financial operations remain the sole posting
authority. Their transactions emit immutable events without needing Codex.

## Capture, pause and suppression

New receipt snapshots enqueue the existing approved version-1 payload for an
active account-independent member with current identity, enabled group policy
and explicit member consent. The global `hybrid_sms_notifications` flag now
controls dispatch authority, rather than deciding whether this newly eligible
work is retained. Its existing value is preserved by the migration.

While the flag is false or absent, claim, exact claimed-receipt read, human
confirmation and durable send-start return SQLSTATE `55000`,
`receipt_dispatch_paused`, before replay or queue changes. A locked flag row
serializes those boundaries with a concurrent pause. Private state-transition
and attempt-insertion guards also prevent a future path bypassing the gate.
Outcome reporting and unsent-claim release remain possible while paused.
Pausing cannot recall a send already handed to a carrier.

Queued work stays queued during pause. After resume, existing payment,
member/contact revision, policy revision and consent revision checks still
apply. Failed checks suppress unsafe unsent work rather than substituting a
new recipient or message. No consent, disabled group policy and app-linked
membership still exclude new SMS. Unsafe references retain the existing
suppressed evidence behavior. Payloads, journals, snapshots and balance
semantics remain immutable. Existing `UNIQUE(payment_id,template_key)` and the
fixed template-version checks are retained.

## Committed events and monitoring progress

The private `collect_hybrid.receipt_business_events` table has this exact row
projection. UUID fields listed as nullable may be JSON null:

```json
{
  "id": "UUID",
  "source_kind": "payment|allocation|receipt",
  "source_id": "UUID",
  "source_version": 1,
  "event_kind": "payment_posted|payment_reversed|allocation_changed|receipt_created|receipt_failed_no_send|receipt_uncertain|receipt_suppressed",
  "collection_id": "UUID or null",
  "payment_id": "UUID or null",
  "member_record_id": "UUID or null",
  "snapshot_id": "UUID or null",
  "outbox_id": "UUID or null",
  "source_state": "source status",
  "created_at": "UTC timestamptz"
}
```

Source versions are source-local integers 1–1,000,000,000. A physical private
head-row write serializes source transitions and deduplicates an identical
signature. Versions and timestamps are not commit-order watermarks. Events
are inserted inside the original payment/allocation/outbox transaction;
rollback removes its event. Payment posted/reversed events are emitted even
when SMS eligibility excludes a recipient. Late allocation changes emit a new
event regardless of the parsed record's original creation date. Receipt
creation and transitions into definite failure, uncertainty or suppression
emit receipt events. A suppressed initial insert is `receipt_created` with
`source_state=suppressed`.

The platform scope is derived server-side and fixed to `collect_platform`.
Every new public RPC requires a current confirmed, approved platform owner,
the current Auth session, and both `system_health.read` and
`notifications.read`. Auth/session, roster serialization and authority rows
are locked in the established order. Consumers are bound to that human actor;
one actor cannot use another actor's consumer. Reauthentication can continue
that actor's monitoring observations after fresh authority checks. This is
not an unattended tenant principal or a run-bound action lease.

`register_receipt_monitor_consumer_v1()` returns:

```json
{"contract_version":1,"consumer_id":"UUID","scope":"collect_platform","purpose":"manual_receipt_monitor","created_at":"UTC timestamptz"}
```

Repeated registration returns the same actor-bound consumer. It writes
monitoring metadata.

`list_receipt_monitor_events_v1(p_consumer_id UUID, p_limit INTEGER=20,
p_skip_event_ids UUID[]=[])` returns:

```json
{"contract_version":1,"consumer_id":"UUID","scope":"collect_platform","checked_at":"UTC timestamptz","rows":[],"limit":20,"progress":"per_event_observation","delivery_evidence":false}
```

Limits are 1–50. Skip IDs are non-null UUID arrays of at most 50 IDs, used only
to move through a bounded working batch. They never persist progress. Each
call scans committed events without that consumer's terminal observation;
no timestamp cursor is accepted. A new invocation without skip IDs discovers
an earlier-created transaction that committed after another event was read.

`ack_receipt_monitor_event_v1(p_consumer_id UUID, p_event_id UUID,
p_request_id UUID, p_outcome TEXT, p_reason_code TEXT)` writes one immutable
request. Outcomes are `observed` or `deferred`. Reasons are `monitoring_only`,
`review_required`, `policy_pending`, `dispatch_paused` or `source_changed`.
Exact request repeats reconcile the existing acknowledgement; changing its
consumer, event, outcome, reason or actor is a conflict. It returns:

```json
{"contract_version":1,"consumer_id":"UUID","event_id":"UUID","request_id":"UUID","outcome":"observed","reason_code":"monitoring_only","acknowledged_at":"UTC timestamptz","pending":false,"business_handled":false,"delivery_evidence":false}
```

`observed` removes that UUID only from that consumer's pending observations.
`deferred` stays pending. If an event was already observed, another deferred
request does not undo that terminal observation. Two consumers retain
independent progress. ACK rollback advances no progress; partially committed
observations leave the remainder discoverable. This records a human monitoring
statement, not attested Codex execution, completed business handling or SMS
delivery. Action-run validated acknowledgements require a later authority
stage. No event amounts, balances, references, names, contacts, bodies or
arbitrary diagnostic notes are exposed.

Argument/conflict/missing-event errors use `22023` with
`receipt_monitor_request_invalid`, `receipt_monitor_request_conflict` or
`receipt_event_not_found`. Foreign consumers use `42501`,
`receipt_consumer_scope_denied`. Current Auth/approval/permission failures use
the existing authority helper's `42501` errors. Evidence mutation uses
`55000`, `receipt_event_evidence_immutable`. No direct private-table access
or new RPC execution is granted to `service_role` or anonymous callers.

## Historical preview and policy refusal

`admin_preview_receipt_backlog_v1(p_limit INTEGER=20,
p_before_captured_at TIMESTAMPTZ=null, p_before_snapshot_id UUID=null)` returns
bounded missing-primary receipt snapshots. Cursor arguments must be supplied
together; limits are 1–50. The envelope has `contract_version`, `checked_at`,
`scope=collect_platform`, `catch_up=policy_pending`,
`historical_enqueue_enabled=false`, `rows`, `limit`, and a nullable
`next_cursor={captured_at,snapshot_id}`. This is historical preview pagination,
not persisted event progress.

Each row contains `snapshot_id`, `payment_id`, `collection_id`, nullable
`member_record_id`, `captured_at`, `payment_status`, `eligibility_code`, nullable
current `policy_revision`, `consent_revision`, `destination_revision`,
`catch_up=policy_pending`, and an opaque `review_version` SHA-256 of that exact
redacted row. Current eligibility codes are `MEMBER_SNAPSHOT_MISSING`,
`PAYMENT_NOT_POSTED`, `MEMBER_INACTIVE`, `APP_LINKED_MEMBER`, `POLICY_DISABLED`,
`IDENTITY_MISSING`, `CONSENT_DISABLED`, `UNSAFE_REFERENCE`, or
`CURRENTLY_ELIGIBLE_HISTORY_UNPROVEN`. Current consent/contact eligibility does
not prove the historical recipient or consent at the old posting.

`admin_reconcile_receipt_backlog_v1(p_request_id UUID,
p_snapshot_ids UUID[], p_review_versions TEXT[])` accepts bounded syntactically
valid proposal identifiers (1–25 equally sized entries), then refuses:

```json
{"contract_version":1,"ok":false,"code":"CATCHUP_POLICY_PENDING","request_id":"UUID","queued":0,"historical_enqueue_enabled":false}
```

This refusal makes no business or telemetry mutation. Version syntax is
checked; no version is accepted as enqueue authority. Approved historical
capture semantics and exact locked eligibility/version validation must be
implemented together before enabling reconciliation writes. The migration
does not populate old events, opt in old contacts, rewrite old receipts,
expand templates, or backfill old payments.
