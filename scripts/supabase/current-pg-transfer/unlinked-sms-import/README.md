# Synthetic unlinked SMS quarantine

This is a **single-database, synthetic-only model**, not a managed importer.
Its entry points reject any mode other than `synthetic` before invoking the
caller-supplied connector. Database/socket/role/cluster checks and fixture
catalogue pins also constrain the demonstration. A caller can imitate these
fixture identifiers, however, and a connector is trusted executable code:
run the model only in the owned, disposable test harness. It does not contact
Supabase, any provider, a mobile device or Storage, and it does not migrate
actual data. It must not be used as a production release mechanism.

The represented source is deliberately narrow. One unique accepted
receipt/transaction/origin/job/scope/lineage path per receipt is required;
selected records must have no financial link, have no conflict, be in an
allowed non-linked allocation state, have a completed job and pass the modeled
identity, visibility and provenance checks. The full synthetic cohort can
also contain financially linked records, which are excluded from this
quarantine. Unrelated, ambiguous, unsupported or incomplete graph structure is
refused instead of being silently dropped. The model preserves represented
receipt, transaction, source-link, all historical parse attempts, job, origin,
scope, synthetic lineage and synthetic object metadata, including nullable
fields. It separately records whether each of the two nullable JSONB job
columns was SQL NULL, since conversion to JSON would otherwise collapse SQL
NULL and JSON `null`. Missing keys in JSON objects remain missing.
The fixture pins the definition and attributes of its JSON validation helper
and independently validates stored parse-attempt JSON text with PostgreSQL's
JSONB input validation; this catches invalid text inserted while the helper
was previously altered. It does not prevent a privileged actor from changing
helper definitions concurrently.

The fixture inserts payloads only into private quarantine tables; it writes no
application SMS, transaction, job, payment, ledger or financial-link rows,
and it does not alter the selected target Auth account or its link. No worker
or replay endpoint consumes the quarantine. A nonprivileged synthetic runtime
role has no privileges on those tables. This is a property of the isolated
fixture, not a global block on privileged actors or a recipe for enabling
application users to see the archived messages. The payload is **plaintext
JSONB**: HMACs and source digests do not encrypt it. Do not place real data in
this fixture or interpret the model as a compliant storage or custody design.
The synthetic object metadata's `verified` flag is preserved whether true or
false; the model performs no object-byte or Storage verification.

A retained, unfenced local count receipt from an earlier observation reported
33 receipt paths, 10 financially linked and 23 without a financial link; its
combined transaction/job consistency check was unknown for 14 and its wallet
check was unknown for three across that whole cohort. The combined check also
depends on transaction fields, so it is not a count of incomplete job-fact
objects. The receipt does not establish which records belong
to each overlap or that these counts remain current. The mixed 33/10/23 test
and its values are invented. A prior source observation is not proof that any
real row satisfies this fixture's graph, authority or Storage assumptions.
The existing linked-only native/financial importer cannot silently accept the
23 unlinked paths as posted transactions.

## Synthetic operation and proof boundary

`captureSyntheticUnlinkedPlan` returns a canonical HMAC-bound plan for an
explicit, already validated fixture mapping and reports `writeAuthorized:
false`. An import locks fixture sources and the quarantine tables before
checking the plan. A unique operation/collection claim commits first; the
quarantine receipt and items then commit in a separate transaction only after
another locked preimage check. A change or failure after claiming leaves the
claim in place. A lost claim acknowledgement returns
`claim_commit_unconfirmed_do_not_retry`; a lost archive commit acknowledgement
returns `commit_unconfirmed_do_not_retry`. Another operation for the same
collection also refuses. No automatic retry, claim release or replay path is
provided. The claim is scoped to this fixture database and can be lost with it
or bypassed by a privileged actor; it is not an independently durable dispatch
journal and proves nothing about old production actors or external effects.

`reconcileSyntheticUnlinkedQuarantine` uses a separate read-only snapshot to
check the claim, receipt, target identity and selected postimage HMAC. Each
postimage entry binds both the relational `source_id` and its payload; sorting
by an unbound key alone would not authenticate that key. An absent
receipt or claim yields `receipt_or_claim_not_visible_do_not_retry`, not proof
that a prior transaction stopped. Reconciliation takes ACCESS SHARE locks
before its snapshot and checks catalogue/visibility conditions; ACCESS SHARE
does not block ordinary DML, so success is point-in-time and does not itself
exclude target writers. HMAC comparison authenticates only the represented
payload under the supplied secret, and provides no encryption or long-term
custody guarantee. The model clears its own key copy where feasible. Its
single-database transaction does not prove atomicity across local PostgreSQL,
managed PostgreSQL, object storage, mobile devices or external providers.

## Synthetic classification

`classification.sql` provides a count-only diagnostic for the owned PostgreSQL
fixture. It checks local socket and session continuity and locks the selected
relations before reading. Its response distinguishes multiple joined paths,
missing jobs, SQL NULL, JSON null, absent wallet keys and nonzero or unknown
transaction conflicts. Those counts describe the selected snapshot and cannot
authorize a transfer.

## Remaining requirements for real use

A managed implementation still needs a complete, freshly captured and fenced
source/target graph and compatible migration history, schema, privileges,
foreign keys, policies and trigger behavior. Real native origins reference
observation requests, unresolved observations, account/collection scopes,
installations, grants and capture/admitting sessions beyond this synthetic
model. Their status, authority, owners, IDs, revocation and relationships need
separate qualification; modeled booleans are not evidence of those facts.
The user-confirmed cloud account remains the primary account, but this model
only records a synthetic source-to-target mapping and establishes no real
identity authority, credential migration or account change.

Real Storage bytes and metadata require independent preservation and
cryptographic verification, including owner scope, request fingerprints,
keys, encryption and authenticated data. A copied synthetic digest is not
proof of any object or of a safely changed owner. SMS bodies and raw parse
provenance require an appropriate encrypted custody and access design. Existing
workers, mobile queues, schedulers, financial posting and prior admitted actors
must be independently controlled or reconciled. In particular, a completed
accepted unlinked job can be eligible for native auto-posting: copying such a
row into active job tables does not by itself prevent replay. Final cutover
requires effective writer exclusion, durable dispatch/unknown-outcome
reconciliation, independent cross-system recovery, and end-to-end tests. The
old production admission and any unconfirmed external effect remain unresolved
by this synthetic quarantine.

## Owned tests

Run from the physical source checkout with a clean environment:

```sh
env -i PATH=/usr/bin:/bin LANG=C \
  /Volumes/PRO-G40/Development/Node/bin/node --test --test-concurrency=1 \
  scripts/supabase/current-pg-transfer/unlinked-sms-import/*.test.mjs
```

The Node tests use owned socket-only PostgreSQL 17 clusters and remove them on
confirmed shutdown. They exercise mixed synthetic cohorts, nullable and
JSON-null facts, source drift, graph conflicts, runtime privileges and RLS,
one-use claims, transaction rollback, lost acknowledgements, concurrent claim
and writer locking, deterministic catalogue races, target tampering and
read-only reconciliation. The fixture launcher verifies
pinned PostgreSQL launcher and wrapped executable pairs; the supplied review
manifest records source, dependency and executable hashes. Those checks do not
attest the OS, dynamic loader, shared libraries, all Node startup code or a
malicious same-user replacement, and do not qualify any managed execution.
