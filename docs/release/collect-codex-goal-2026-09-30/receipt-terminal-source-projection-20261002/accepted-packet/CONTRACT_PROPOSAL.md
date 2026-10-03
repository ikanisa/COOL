# Terminal receipt-source live projection — bounded proposal

Status: awaiting root review before changing any existing scanner function.
Reserved migration:20261002050000. Root is the sole canonical promoter. The
completed worker_history_map_oct02 source map is reused in REUSED_SCANNER_MAP.md;
only the affected1400/2100 function fragments and hold/terminal schemas were read.
Canonical300 must match accepted008a0507; canonical400 is67de6de7. No UI, MCP,
worker schedule, enabled flag, credential or hosted configuration changes belong
to this slice.

## Scope and stable interface

Add private collect_receipt_source_projection admissions, live membership and
immutable certificates. Live key is(source_kind,source_id), finite kinds exactly
receipt_event/receipt_backlog. Every live membership identifies one immutable
admission UUID. Admission records bind either an original work UUID or the atomic
installation/backfill receipt; re-admission uses a new UUID after later producer
work. No original source, work, job, dispatch, receipt, expiration, scan, exception
observation or audit row is moved, rewritten or deleted.

Keep public.process_receipt_deferral_exceptions_v1(uuid,integer,timestamptz)
and every original lookup/API signature, OID, owner, ACL, configuration, UUID and
FK unchanged. Its closed result/version/limit25/expiry120s/busy/idempotent replay
rules remain unchanged; source_scan_complete staysfalse, financial_action and
send_action stayfalse. Existing jobs→dispatches→original scan→receipts and exact
scan→exception-observation revision references remain valid. No new public RPC
or API-role table/helper grant is introduced. Default worker configuration,
policy, feature flags and cron remain exact and inactive as currently configured.

Replace only its two sweep source queries with indexed live membership keys in
the same repeating phase/cursor order. The original pending queue, consumed in
queued_at,id order under its partial index, remains independent of that cursor.
Sources arriving behind it cannot be lost. Each original successful refresh can
call private try_retire_source(kind,id,scanUUID,workUUID) after recording its exact
observation revisions and transitioning that work row to processed. Scope-refused,
unavailable, expired or busy observations never retire membership. Certificate,
live deletion, original processed work and original scan receipt commit together;
any receipt failure/expiry rolls everything back. Replays create no certificate.

## Atomic producer membership and backfill

Retain original2100 historical sweep_sources and all original producer triggers.
Add an AFTER INSERT work admission trigger: successful original queue production
admits the exact same source without a global aggregate lock. Existing live keys
need no new admission/write. Retired keys with later original producer work are
re-admitted atomically. The source is never removed from pending work by this
maintenance. Backfill the original event_deferral keys, historical backlog keys,
and pending queue keys while holding the scanner lock before the relevant
producer table publication locks. Record one immutable installation receipt and
publish trigger/backfill in the same transaction. Validate source/admission shape.

Reuse the original pending(queued_at,id) consume index and2100 source/latest
terminal evidence indexes. Add only the missing pending source-local hold index
(source_kind,source_id,queued_at,id) WHERE processed_at IS NULL. Private live
(source_kind,source_id) is its sweep index. Do not scan immutable lifetime work,
callback or worker journals merely to find current source membership.

## Closed terminal evidence

A receipt_event requires an immutable handled_events row with the exact event
UUID and source_version and its closed terminal code. Receipt-valued codes also
bind the retained outbox to the original payment/source snapshot and immutable
content evidence. PAYMENT_REVERSED/SOURCE_SUPERSEDED keep their original code
semantics; maintenance creates no new handled ACK.

A receipt_backlog requires an exact immutable backlog_results(runUUID,snapshotUUID)
row with business_handled=true and a closed actual terminal code; receipt-valued
codes require matching original payment/snapshot/outbox/content evidence. A true
boolean paired with SOURCE_BUSY, DRY_RUN_ELIGIBLE or any other unsupported code
is not terminal proof. All candidate source/handled/receipt identities are joined
and compared, never inferred from a mutable current eligibility decision.

Strict event supersession is an alternative only when two committed immutable
business-event rows have the same source_kind/source_id and a strictly increasing
source_version, with matching scoped source provenance. The higher source must
remain independently discoverable in live/pending membership or have exact
immutable handled/certificate proof. A mutable head alone is insufficient. The
certificate identifies both immutable events and hashes their complete original
records. Do not retire an old source while its replacement is unrepresented.
Backlog supersession is intentionally excluded in this first slice unless a
separate immutable equivalence proof is defined; handled-backlog proof is enough
for the conservative implementation.

No retirement follows age, source_scan_complete, current_blocker_cleared,
DRY_RUN_ELIGIBLE, missing deferral rows, mutable payment/contact/consent/policy,
configuration/caps, framework request ACK, absence of a sampled row, unknown or
unavailable evidence. All original business/delivery acknowledgements remain
owned by their original producers.

## Explicit conservative holds

Derive a finite source graph: direct receipt_event/backlog, its actual payment,
allocation/parsed source, raw SMS and retained original receipt roots. Include any
actual associated gateway source only when a retained attempt establishes that
link. Missing or ambiguous required provenance returnsheld.

For every joined exception, require no active head, no unfinished workflow
(resolved_source_revision must match the current inactive head revision), no
queued/recipient-unavailable escalation and no delivered but unread original
Admin inbox item. Certificates bind every observed inactive exception to its exact
immutable exception_observation revision through FK rows. Absence of an exception
is documented by the locked finite graph and proof digest, not mistaken for an
unobserved current measurement.

Other pending source work is a hold until it is independently processed; the
current work has already made its original pending→processed transition. This
preserves deduplicated scans and original pending-work evidence.

Unknown/unfinished transport facts are a hold. For this initial conservative
slice, any original assisted claim/confirmation/attempt or automatic grant/arm/
callback keeps membership live unless immutable400 original closure explicitly
binds the same root/never-armed attempt and proves definitely_not_invoked. This
keeps even completed transport histories protected; loosening that hold requires
a separate terminal transport/callback/journal contract and proof. It does not
claim physical journal retention or delivery success. No transport means no
transport hold, not a delivery acknowledgement. Explicit uncertain states are
always held, including any conflict appearing despite earlier closure facts.

## Lock order and fresh certification

Keep the existing scan-request→worker→workflow→progress/work→source order.
Refresh executes exactly as before. Retirement occurs afterwards and requires
READ COMMITTED; a different isolation level retainslive without publishing a
certificate. Try source-local graph advisory locks in deterministic order with
pg_try_advisory_xact_lock, and source/live/outbox evidence fences with NOWAIT.
Contention is a conservative hold. No new blocking source/global producer lock
is introduced. An inner caught subtransaction releases partial retirement locks
on refusal; original refresh/work observations are retained. Hold/source checks
are fresh after fences and repeated immediately before certificate publication.
Live deletion matches the exact admission UUID, never a later re-admission.

Protect admission/installation/certificate/certificate-observation rows against
UPDATE,DELETE,TRUNCATE. Protect live changes behind private helpers/trigger and
leave private tables under RLS with all API roles denied. Installation is
additive; unexpected scanner/queue/source predecessor bodies or CHECK shape
refuse before publishing behavior. Existing source260 and telemetry300 functions
are preserved, not replaced by earlier sources.

## Actual acceptance scope

Prove ordinary-owner installation, predecessor drift and all ACL/config/UUID/FK
preservation. Execute real original service scans and original worker execute/
lookup receipts under the retained required platform/transport prerequisites;
reuse valid setup, never stub160 or replay unrelated63 checks. Required cases:
terminal handled event/backlog retirement; nonterminal/DRY_RUN/SOURCE_BUSY and
false terminal booleans retained; strict supersession versus mutable-head-only or
missing replacement refusal; exact payment/snapshot/content mismatches; every
active/workflow/escalation/inbox/transport hold; unavailable/scope refusal;
behind-cursor producer work and re-admission; bounded repeated scan over deep
historical originals; original lookups before/after; expiration/failed-scan
rollback; request replay/conflict; concurrent independent financial producer
progress and lock contention; immutable certificate tamper refusal; exact live/
admission/certificate equality and deep-history EXPLAIN. Preserve all original
journal hashes across installation and maintenance except their authorized
existing append/work/progress transitions. Capture source/tool/dependency bytes
and retain failed attempts honestly. No hosted, physical-device, provider,
physical hot/cold relocation, complete retention or whole-candidate claim.
