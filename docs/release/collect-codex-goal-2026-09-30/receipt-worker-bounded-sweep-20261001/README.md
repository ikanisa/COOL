# Staged receipt worker source-sweep query improvement

This is an additive SQL query-cost slice for the existing receipt exception
worker. Canonical application, SQL, tests and release documents remain untouched
by this worker while another chat owns the frozen Admin build.

The migration replaces each repeated lifetime DISTINCT over historical backlog
and budget refusals with a private append-only snapshot source registry. Backfill
uses exactly the former UNION membership. The existing producer trigger keeps
that registry and its independent work append in the producer transaction.
Historical unhandled evidence retains its membership after a later handled
result; a solely handled result creates independent work but no sweep membership.
The repeating cursor and behind-cursor producer arrival behavior stay intact.

Seven indexes match global latest-job/latest-receipt reads, source-local
unhandled/handled/QUOTA_EXHAUSTED backlog evidence, budget evidence and quota
run-event evidence. The two backlog evidence UNIONs now merge at most one exact
timestamp/run-UUID winner per branch. The scanner's generic keyset plan can use a
lower-bound index condition even when its cursor is nullable; the nil UUID remains
eligible at the start of a sweep.

Four exact predecessor body SHA-256 guards reject drift before any changed
behavior commits. The replacements retain existing function OIDs, owners,
signatures, security attributes and grants. The new registry has RLS, no API-role
table privileges, a restrictive snapshot FK and immutable update/delete guards.
It introduces no public API and no financial or sender action.

Installation intentionally performs one full historical membership backfill and
ordinary index creation under producer table locks. Hosted deployment must plan
that maintenance window against its actual data and workload. This packet does
not prove hosted permissions, production migration duration or hosted capacity.

The UAT composes the 177 unchanged captured fixture prerequisites plus the exact
110000/120000/140000/150000 feature prerequisites. The new migration and changed
behavior run as an actual NOSUPERUSER owner in the task-owned network-none
PostgreSQL 17.6 target. The prior fixture bootstrap explicitly normalizes its
local schema installer to superuser; that bootstrap is not claimed to reproduce
managed hosted installation permissions. Auth role claims are synthetic SQL
fixtures, not GoTrue or signed JWT verification. Real synthetic canonical
postings produce the financial snapshot sources; query-only immutable worker
history anchors are explicitly labeled installer fixtures.

This slice does not complete hot/cold worker history maintenance, export or
restore. Existing original acknowledgements, jobs and scan histories remain
retained; the registry itself permanently retains distinct historical identities.
Unresolved queue totals and daily quota sums still count their actual retained
rows. It does not claim an entirely bounded scanner transaction or continuous
worker retention. No hosted write, provider call, native device test or SMS occurs.

Integration owner: root. Copy the staged migration and UAT only after the frozen
candidate owner releases its boundary. The UAT accepts `--migration` for an exact
selected SQL file; its default supports the staged file or the canonical migration
at the same basename. Preserve the complete passing attempt and rejected attempt
receipts rather than summing their checks or presenting them as one execution.
