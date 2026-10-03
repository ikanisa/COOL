# Exception audit and recipient inbox v2

Additive migration `20261001200000_exception_inbox_audit_v2.sql`; original v1 definitions and typed responses remain unchanged. The accompanying JSON schema defines exactly three responses. Example fixtures are copied from actual isolated synthetic SQL outputs, not production data. This contract grants no financial, SMS, provider-delivery or source-resolution authority.

## Authority

All three endpoints require Read Committed, a locked current Auth session, the canonical combined-roster fence, `platform_owner`, the existing `payments.read`, `notifications.read` and `system_health.read` permissions, and the current verified email approval. Both authority and natural approval/session expiry are rechecked before return. Audit additionally requires `audit.read`. Inbox list/open require neither `audit.read` nor `notifications.manage`. API execute is granted only to `authenticated`; private tables/helpers have RLS/no direct API grants. Local fixture role/JWT-claim normalization does not prove hosted installer or Auth-service parity.

Local 100 ms lock timeout produces SQLSTATE `55P03` with `exception_audit_authority_busy` or `exception_inbox_authority_busy`. It discloses no request, recipient or audit state before authority. Invalid bounds/cursors produce `22023` `exception_audit_input_invalid` / `exception_inbox_input_invalid`. Canonical current-authority guards retain their existing `42501` and stale transaction `40001` reasons.

## Audit

`admin_get_exception_entity_audit_v2(p_exception_id uuid, p_limit integer=20, p_before_at timestamptz=null, p_before_event_id uuid=null)` accepts limits 1..25 and a paired cursor. Cursor timestamps must be finite and in years 0001..9999. Rows are strictly descending `(recorded_at,event_id)`, exclusive of the supplied pair; a non-null next cursor exactly identifies the final returned row and proves at least one additional eligible row existed in that read snapshot. A page has at most the requested limit; no total is fabricated. `checked_at` and `sample_valid_until` are exact UTC with six fractional digits, separated by 60 seconds. This is read-snapshot validity, not renewed source freshness.

Envelope exact keys: `contract_version=2`, `scope=rw_operator_entity_audit`, `entity_kind=exception`, `entity_id`, `status=available|unavailable`, `checked_at`, `sample_valid_until`, `limit`, `history_complete=false`, `financial_action=false`, `send_action=false`, `rows`, `next_cursor=null|{recorded_at,event_id}`. Unsupported, unknown, missing or contradictory source evidence returns `unavailable`, empty rows and null cursor.

Each row has exactly **15** fields: `event_id`, `source`, `source_record_id`, `action`, `recorded_at`, `actor_kind`, `actor_id`, `request_id`, `revision`, `workflow_revision`, `escalation_id`, `reason_code`, `origin`, `assignee_id`, `due_at`.

| source | actions | immutable source/revision and nullable fields |
| --- | --- | --- |
| `exception_action` | `exception.acknowledge`, `exception.escalate` | source_record_id=request_id; revision=expected_revision. Actual recorded operator actor/request; workflow_revision, escalation_id, assignee_id, due_at null. origin=immutable_request. |
| `exception_workflow_request` | `exception.workflow.assign`, `.escalate`, `.resolve` | source_record_id=request_id; revision=expected_source_revision; workflow_revision=immutable ACK workflow_revision=expected_workflow_revision+1. Actual recorded operator actor/request; origin=immutable_request. assign alone exposes original opaque assignee_id and due_at; escalate alone exposes original ACK escalation_id; all other corresponding fields null. |
| `exception_escalation_event` | `exception.escalation.queued`, `.delivered`, `.opened`, `.obsolete`, `.recipient_unavailable` | source_record_id=private immutable lifecycle record UUID; revision=actual escalation source_revision; escalation_id non-null. request_id, workflow_revision, assignee_id and due_at null. No original request UUID is guessed from a transition that never persisted it. |

All revisions are 1..1,000,000,000. All reason codes are non-null: review uses `review_started|owner_review_required|uncertain_send_review|contact_review`; workflow also permits `source_rechecked`, required for resolve; lifecycle uses `operator_escalation|deadline_exceeded`. `due_at` is a historical approved deadline, not a promise that it remains future or that the source is still actionable. Workflow assign/escalate retain existing submitted reason semantics unchanged.

`event_id` is UUIDv5 with namespace `c5a97546-80ab-5b57-a267-754aac043bd0` and name `<source>:<source_record_id>`; it is stable and distinguishes the same UUID reused in separate immutable request tables. Each lifecycle phase has an independent durable record ID. Multiple recipient-unavailable retry observations remain separate immutable records.

`actor_kind=operator` requires an actual non-null recorded operator UUID. Captured service-role execution has `actor_kind=service`, `actor_id=null`, even if a service claim happens to include a UID. Unknown/retained execution has `actor_kind=unknown`, `actor_id=null`. Original operator request rows have `origin=immutable_request`. New lifecycle rows have `origin=captured_transition`. Installation retains only actual stored queued/delivered/opened/obsolete timestamps with `origin=retained_source`, unknown actor and null request. Mutable pre-install recipient-unavailable transitions lack a reliable timestamp and are not manufactured. Thus `history_complete` remains false.

Receipt-event/backlog availability uses pure typed SELECT joins to actual canonical Rwanda source proof. It never runs operational ensure/enqueue/refresh, modifies event ACKs or invokes provider functions. Allocation events additionally require a supported RWF non-diaspora target, typed incoming parsed evidence and receiver/hash consistency; payment-backed events must bind the actual payment/collection/parsed or outbox identity. No contact, receipt body, raw SMS, error, hash, session or service credential is returned.

## Recipient inbox and opening

`admin_list_exception_escalation_inbox_v2(p_limit integer=20, p_before_delivered_at timestamptz=null, p_before_escalation_id uuid=null)` has the same bounds, exclusive paired cursor and 60-second read validity. It returns only deliveries for the current caller. Envelope: `contract_version=2`, `channel=admin_inbox`, `scope=current_operator`, `recipient_id=auth.uid()`, `checked_at`, `sample_valid_until`, `limit`, `rows`, `next_cursor=null|{delivered_at,escalation_id}`.

Existing eight row keys remain exact: `escalation_id`, `exception_id`, `source_revision`, `reason_code=operator_escalation|deadline_exceeded`, `source_active`, `current_source_revision`, `delivered_at`, `read_at=null|UTC6`. Current revision is at least the captured source revision. Delivery means committed availability in the private Admin inbox, not SMS/push/carrier delivery. `read_at` is the immutable first acknowledged opening time, distinct from source status.

`admin_read_exception_escalation_v2(p_escalation_id uuid)` wraps unchanged v1 idempotent opening with current verified-email authority before/after. Exact ACK: `contract_version=2`, `escalation_id`, `read_at`, `source_resolved=false`. Unknown or foreign-recipient delivery is refused by the unchanged v1 `42501` `exception_escalation_delivery_unavailable` guard. Opening adds only immutable inbox-read/lifecycle evidence; it closes no source, changes no workflow and sends nothing. If the response is lost, repeating opening returns the same original first-opened timestamp; it cannot cause a financial or transport action.

## Durable capture and limits

Triggers capture actual queued, durable-delivery, opened, obsolete and recipient-unavailable outcomes in the same transaction as their source write. Capture failure rolls back the source transition. Existing terminal states remain immutable and no existing source value is rewritten. Installation takes the canonical roster/workflow fences before source table locks; ordinary reads use one statement snapshot after current authority and recheck authority before returning. The retained finite known past is partial history, not retroactive attestation of service execution.
