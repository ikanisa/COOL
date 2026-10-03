# Receipt terminal-source projection: implemented bounded contract

Root accepted the conservative proposal and the source-race/unread refinements.
Root is the sole canonical promoter. This stage owns additive migration
`20261002050000_receipt_terminal_source_projection.sql`; its source is held in
`promote/` and is not installed in a hosted system by this worker.

## Stable original interface and evidence

Only the body of `public.process_receipt_deferral_exceptions_v1(uuid,integer,timestamptz)`
changes. Its original OID, owner, ACL, parameters, volatility/configuration,
closed result, limits, request replay/lookup, expiration and original scan/work
UUIDs remain. Its two sweep queries use private live keys; its independent
pending queue still consumes the exact original work in `(queued_at,id)` order.
Every original source, financial journal, work, job, dispatch, receipt,
expiration, scan, observation, escalation, delivery/read and lookup FK remains.
No physical history movement, deletion, journal-retention acceptance or new
business/delivery acknowledgment is introduced. Scan/certificate
`source_scan_complete`, `financial_action`, `send_action` remain false.

Six private tables contain installation/admission evidence, indexed live keys,
immutable certificates/exact exception revisions, and exact unread inbox holds.
API roles have no schema/table/helper access; RLS and immutable protections are
installed. No MCP allowlist, public RPC, worker schedule, flag, policy, unattended
identity or live configuration change belongs to the migration. Existing
configuration and cron rows are compared exactly across installation.

Thirteen exact causal predecessor bodies, the original finite work CHECK,
validated delivery/read FK edges and original private ACLs are checked before
behavior is published. Source260, telemetry300, content250 and closure400 bodies
are preserved. The only original body replacement is bound separately by its
final SHA; all other twelve causal bodies must remain exact after the proof.

## Admission, races and certificates

The work AFTER INSERT trigger tries a source-local admission lock only when live
membership is missing. It never adds a financial aggregate lock. Existing live
membership is an intentional fast path. Installation/backfill is atomic under
scanner/workflow and original source-to-work publication locks, and retains
original source rows.

The fast path can race a scanner that has completed its final pending check and
is about to delete the old membership. A producer can therefore commit an exact
original pending row while deletion commits without live membership. This does
not claim atomic future re-admission: the original pending queue is durable and
independent of the cursor. Before refreshing each exact pending work row, the
scanner must ensure its source membership; contention leaves the row pending.
The next scan then records a new immutable admission associated with that exact
original work. Deletion binds the old admission UUID. The deterministic proof
pauses after the last pending check and verifies that exact interleaving,
original request replay, behind-cursor recovery and certificate/admission equality.

Retirement requires the exact immutable handled-event/source-version proof or
closed handled-backlog/run/snapshot proof. Receipt codes bind the original
payment/snapshot/outbox/content evidence. A boolean, SOURCE_BUSY,
DRY_RUN_ELIGIBLE, missing/mutable facts or age never establishes terminality.
Strict event supersession additionally binds an immutable higher same-source
version with independently represented replacement evidence; mutable heads or
unrepresented replacements remain live. Backlog supersession is excluded.

A certificate records source facts at its original scan time. It does not claim
permanent transport absence. A future ordinary grant has no original1400 work
producer; later original transport transitions synchronously refresh exceptions
and create their own new immutable business events. They remain owned by those
original consumers. Unknown/armed/assisted transport holds retirement. Immutable
400 never-armed closure may establish its exact original-route no-arm fact, but
active RECEIPT_SUPPRESSED still holds the source. No successor route is implied.

The same original payment/outbox fences used by grant/arm/callback/closure are
held with NOWAIT inside a caught subtransaction. Original workflow and telemetry
publication gates prevent phantom operational heads. Source-local graph gates
match the shipping observer. Partial retirement locks roll back on refusal.
Independent financial posting/source-work production must progress while a
different source is locked. No source or operational hold is cleared by maintenance.

Source graph/head caps are finite. Historical telemetry associations use at most
33 source-local indexed alert-ID seeks per finite source key rather than lifetime
DISTINCT aggregation. Numeric duplicates for one alert are skipped by the next
alert-ID predicate. Current/historical linked heads, unfinished workflows,
queued/unavailable escalations and exact unread holds are joined. The digest binds
original source/terminal records, exact inactive exception revisions, root/attempt
IDs, immutable closure ID/digest and superseding evidence.

Certificate, observation FKs, live deletion, original work transition and original
scan/worker receipt commit in one transaction. Wall-clock expiry or publication
failure rolls back the complete attempt. Original UUID replay does not append
another certificate or scan.

## Unread producer mirror

`UNREAD_MIRROR_CONTRACT.md` binds the shipping immutable delivery and read writers,
their exact original UUID/recipient pairs, FK order and ACL guards. The populated
backfill equals original deliveries minus matching-recipient original reads.
Delivery/read producer triggers commit their mirror effect in the same transaction.
Only an exact immutable matching read permits private membership deletion. An
owner-only malformed wrong-recipient read cannot remove the correct unread hold.
Current Admin workflow/inbox reads continue using the original tables and APIs.

## Proof boundary

The scoped proof restores the exact retained192-prerequisite checkpoint and
executes the nine exact current160/2330/2340/2350/2355/300/315/400/410 DDL inputs.
These are 201 selected source definitions, not 201 new migration replays. Root's
separate current201 clean/populated ordinary-owner rehearsal remains independent.
500 is installed and exercised with actual NOSUPERUSER application ownership;
retained CREATEDB/CREATEROLE/BYPASSRLS and declared local managed-platform setup
are explicit limitations.

The pg_net prerequisite uses the reviewed real owner-gated table/column ACL and
index script; real160 remains installed. Snapshot platform metadata/pg_cron
extension-owner setup reuses root's accepted local platform configuration. No
application receives direct cron DML. Vault credentials are explicitly synthetic
in a local view, the network is disabled, cron launch is off and pg_net batch size
is zero. The Auth session/JWT claims and device health/callback inputs are declared
SQL fixtures: no GoTrue, JWT cryptography, Vault encryption, hosted session,
physical Android/telephony, SMS, provider availability or store acceptance claim.

Failed attempts and their captured inputs/results are retained. Acceptance uses
one final unchanged-source actual run and saved EXPLAIN plans, with all original
producer body hashes checked at the end. Root still owns canonical promotion and
any refreshed full-candidate replay afterward.
