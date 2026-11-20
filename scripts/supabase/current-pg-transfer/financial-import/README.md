# Synthetic posted-financial-graph import

This is an executable **single-database, synthetic-only PostgreSQL 17 candidate**.
It is not a managed Supabase importer, a data transfer or permission to cut
production over. All entry points reject `mode` other than `synthetic` before
calling the supplied connector. They additionally check the fixture database,
cluster, non-superuser role and Unix-socket connection. Those names and a
socket can be imitated; they do not prove a server is disposable. Run it only
with the owned synthetic harness. The supplied `connect` function is trusted
executable code and is not sandboxed.

## Bounded operation

The candidate imports one closed set of 1–64 already-posted financial bundles
from `src` into `app` in one transaction. It inserts the five financial tables:
`payment_evidence`, `payments`, `momo_financial_links`, `ledger_entries` and
`contribution_posting_snapshots`. The SMS receipt, parse, transaction, source
link, native origin, job, scope, membership, and source/target object-proof
records must **already exist** in the same fixture database. The module does
not import them or access Storage; its synthetic `verified` proof fields are
fixtures, not evidence of object bytes, a provider response, key custody or AAD
compatibility.

The caller supplies the explicitly selected local-owner and cloud-primary
application and Auth IDs. The target Auth link is never updated. Only evidence
owner, financial-link actor and contribution-ledger actor are mapped to the
selected cloud owner; the receipt records the original source owner. Existing
payment, evidence, transaction, SMS, ledger and snapshot identifiers, amounts,
timestamps and other columns are preserved. A beneficiary is required to have
identical pre-existing source and target user and membership records. A
beneficiary equal to either owner ID is rejected rather than implicitly merged.
No other identity is inferred from email or a matching identifier.

The fixture accepts only native incoming SMS postings. It requires exactly one
accepted source and one contribution/snapshot per selected payment, matching
native posting facts, amounts, currencies and references, evidence plaintext
SHA matching the linked SMS body, a posted status, no reversal/correction, no
payment intent, a native receipt without an active originating-session
reference, matching selected object-proof records, closed fixture fences and
no uncertain admissions. It rejects extra source
financial rows and any pre-existing target financial rows. It therefore does
not cover unposted SMS, missing/multiple sources, reversals, nullable or
unsupported financial history, pre-existing cloud financial data, other
collections, or the broader dependency graph.

The synthetic fixture also requires an explicit reviewed assertion that its
positive-only ledger is complete and has no earlier deletions. It checks that
snapshot and ledger timestamps match, refuses tied or unsupported timestamps,
and verifies that the stored group-after balances permit one strictly
increasing sequence whose per-member running totals match the snapshots. It
orders this calculation by group-after balance, not by timestamps or IDs.
Distinct application-generated timestamps do not prove commit order, and a
consistent sequence does not prove the actual historical order or that prior
ledger rows were never deleted. The fixture assertion is not real-world proof.
The native writer initially sets the payment's payer display name from the
saved counterparty name. This candidate does not check their equality: later
legitimate edits have not been ruled out, so a mismatch remains unclassified
until its history is examined.

`captureSyntheticFinancialPlan` checks and reads the fixture state, returning a
canonical `planJson`, `expectedPlanSha256` and `writeAuthorized: false`. The
caller must independently verify the mapping, plan and digest; calculating a
digest does not constitute approval. `importSyntheticFinancialGraph` takes the
same plan and expected digest plus a 32-byte HMAC key and dedicated connector.
It rechecks the locked fixture, source graph, target identity and projected
postimage, writes all five tables and an operation receipt atomically, then
verifies the postimage. A replay with the same receipt verifies the postimage
and inserts nothing. Input snapshots, HMACs, IDs and `planJson` are sensitive;
the module does not log them, but the trusted caller must protect its memory,
logging and key material. The copied key is cleared on exit where feasible.

If COMMIT acknowledgement is lost, the result is
`commit_unconfirmed_do_not_retry`. `reconcileSyntheticFinancialGraph` uses a
separate read-only snapshot to check the receipt, target identity and selected
postimage. It acquires target-only access-share locks before that snapshot,
then rejects filtered, inherited, non-owned, inaccessible or catalog-drifted
target relations. This prevents hidden rows and concurrent target schema
changes from being silently certified. Access-share locks do not block
ordinary row writes: a successful reconciliation describes the selected state
at its snapshot and cannot establish that concurrent or subsequent DML did
not change it. Independently exclude target writers throughout final cutover
verification; this result alone is not final cutover evidence. An absent
receipt returns `receipt_not_visible_do_not_retry`; it
cannot prove the earlier transaction stopped. No entry point automatically
retries a money write. This candidate has no durable dispatch journal outside
the financial transaction, so it cannot enforce that instruction across
processes; a supervisor must resolve an uncertain outcome before any new
attempt. The receipt and its privileges are fixture designs, not a qualified,
tamper-resistant managed audit system.

## Fixture guards and limits

Before the first snapshot in the writing transaction, fixed-order relation
locks block concurrent fixture writers while the import runs. PostgreSQL
explains the relevant lock conflicts in its [version 17 locking
reference](https://www.postgresql.org/docs/17/explicit-locking.html) and [LOCK
command documentation](https://www.postgresql.org/docs/17/sql-lock.html). The
fixture checks a pinned schema/catalog digest, selected helper and trigger
bodies and execution properties, row-security visibility, relation inheritance,
bounded row sizes, source/target identity links, fences and admissions. Extra
write-table triggers are refused. These checks are not a managed-role,
provider, entire function-dependency or external actor exclusion proof. A
privileged actor able to alter function definitions concurrently must be
excluded independently; a guard check cannot establish that exclusion.

The fixture contains selected baseline table definitions and deliberately
simplified origin, jobs, scope, identity, object-proof and fence tables. It does
not install the full current Collect schema, source/target RLS, existing
side-effect triggers, Storage objects or device credentials. Source and target
live as schemas of the **same** fixture database. It does not prove an atomic
snapshot across independent source and managed databases, actual catalog or
privilege compatibility, complete historical attribution, backup/recovery,
provider effects, offline queues or production replay safety. The real importer
must revalidate the actual graph, effects, key/AAD and device boundaries under a
qualified cross-system freeze and recovery protocol before any managed write.

Run the PostgreSQL tests using the pinned repository `pg` package and a
physical PostgreSQL 17 binary directory:

```sh
COLLECT_SYNTHETIC_PG_BIN=/absolute/physical/postgresql-17/bin \
  node --test --test-concurrency=1 \
  scripts/supabase/current-pg-transfer/financial-import/import.test.mjs
```

They create and remove an owned socket-only PostgreSQL cluster. Cases cover two
linked synthetic contributions, exact owner mapping and preserved IDs,
missing graph/proofs, unsafe sessions, beneficiary collisions, changed source,
identity and fence state, RLS/catalog/helper/trigger drift, existing target
conflicts, transactional rollback, unconfirmed COMMIT, read-only reconciliation,
concurrent replay, blocked source/identity writes and postimage tampering.

A separate optional portability check creates and removes an owner-labelled,
networkless Docker fixture from the exact pinned Supabase PostgreSQL 17 image;
it verifies only the synthetic catalog digest and does not connect to any
existing database:

```sh
COLLECT_SYNTHETIC_DOCKER_CONTEXT=colima-supabase-local \
  node scripts/supabase/current-pg-transfer/financial-import/synthetic-linux-catalog.mjs
```
