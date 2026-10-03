# Exact unread hold projection — root review

Owned stage only. No original UUID, API, FK, journal, authority or immutable row
is moved, rewritten or deleted. The table is one extra private current hold
projection, not a delivery acknowledgement. No public DTO or MCP changes.

The only shipping delivery writer is the retained security-definer
`public.process_exception_escalations_v1(integer)`: a service caller acquires the
combined-roster and `collect-ops-workflow` gates, then appends one immutable
delivery under the original escalation UUID. The only shipping read writer is
`public.admin_read_exception_escalation_v1(uuid)`: an authenticated current
operator reads an original delivery belonging to their exact actor UUID, then
appends the immutable read under that exact original escalation/recipient pair.
The original Admin inbox list and workflow projections continue to read original
deliveries/reads; no consumer is redirected to the maintenance table. Original
private-table API-role denial and original row-immutability triggers remain.

`unread_inbox(escalation_id,exception_id,recipient_id)` retains the delivery UUID
as PK/FK to the original delivery and its exception FK. AFTER INSERT delivery
derives exception_id from the retained original escalation and recipient from
the original delivery; it creates membership unless the same immutable read
pair already exists. AFTER INSERT read deletes only the exact same UUID and
recipient membership. A BEFORE UPDATE/DELETE guard refuses all changes except
deletion proved by that original immutable matching read. TRUNCATE is refused.
No API role can access this schema, table or trigger helpers.

Delivery and private insertion commit or roll back in one transaction. Read and
private deletion commit or roll back in one transaction. The read's original FK
requires the delivery: a reader cannot acknowledge an uncommitted/nonexistent
delivery through the current Admin RPC. A conflicting recipient cannot clear the
hold. No global aggregate row or maintenance source lock is added to either
producer. Source-work admission still follows the reviewed original pending
queue protocol; the mirror does not produce, process or delete receipt work.

Installation holds the original scanner/workflow gates, then original receipt
producer→work publication locks. For inbox publication it locks original reads
before deliveries, matching the child read INSERT→delivery FK order. Triggers
and exact unread backfill publish in that one migration transaction. The
delivery producer's read-table SELECT is compatible with those publication
locks. The migration refuses drift in13 exact causal function bodies, the closed
work-kind CHECK, both original inbox FK edges, and original RLS/API table+column
denial before creating behavior. Existing function OID/owner/ACL/config/signature
and original row bytes are compared in the actual ordinary-owner UAT.

Retirement already holds the original workflow gate, which serializes new
shipping escalation/delivery production. It uses a partial original
`exception_id,state,id` index over only queued/recipient-unavailable escalations
and a private `exception_id,escalation_id` unread index. There is no lifetime
delivered/read anti-join. Each finite graph key uses an exact source_kind/source_id
exception lookup, capped at129 rows; at most128 distinct heads are admitted.
Telemetry history uses at most10 exact event/handled/attempt keys and33 alert-ID
index seeks per key; duplicate numeric observations for an alert are skipped by
`alert_id>last` rather than DISTINCTing historical rows. Root/source locks and
the telemetry sampler gate fence phantom head admission. Unknown/missing facts
or any cap/contention retain the original live membership.

Actual proof includes nonempty pre500 delivered/read checkpoint rows, exact
backfill equality, current Admin read, real assignment/deadline/source-clear/
resolve/read behavior, retained wrong-recipient/unavailable holds, original
worker/scan UUID consumers, actual rollback, deterministic pending-work producer
arrival after the final retirement check and before deletion, and indexed deep
history. Evidence from the in-progress attempt is not final acceptance. The
certificate describes evidence at its original scan time; future ordinary grants,
receipt transport transitions and new business events retain their own consumers.
