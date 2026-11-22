# Aggregate-only source financial consistency

This source-only diagnostic examines selected posting snapshots, ledger balances
and native SMS evidence relationships. PostgreSQL performs the joins and
calculations internally; its single result contains aggregate counts, flags and
an observation time, with no financial identifiers, digests, amounts or row
bodies. It does not change, import, repair or authorize data. The query runs in
one `REPEATABLE READ READ ONLY` PostgreSQL 17 transaction and rolls it back. Its
brief access-share locks can delay conflicting DDL. The 15-second timeout
limits a statement, not the total runtime. Ordinary reads may still affect
database caches, metrics or logs.

Use one fresh, trusted physical session. The session check runs before `BEGIN`;
the transaction locks all required relations before its first visibility/data
query and verifies that the precheck used the same backend, plus the expected
read-only isolation. `psql -X -v ON_ERROR_STOP=1` sends the statements in this
order. A driver that sends the whole file as one protocol query may reject it;
submit the precheck and transaction as separate commands on the same fresh
connection, without an enclosing transaction or pooler session change. A
same-user or privileged actor can defeat session markers and is outside this
lock proof. Earlier saved receipts predate this ordering fix and cannot prove
that concurrent inheritance changes were visible; they remain preserved.

The SQL requires the `postgres` database over a Unix socket, ordinary non-inherited
required tables, every explicitly listed column with its expected type, schema
usage and full table-level SELECT, and no active RLS filtering. RLS may be enabled
on a required table if the trusted reader actually bypasses it; it refuses a
reader subject to a row filter. Duplicate or null payment identifiers refuse the
observation. These guards do not authenticate which socket-backed server is the
intended source, audit the full schema or role graph, establish a source freeze,
or protect against a compromised database or privileged concurrent actors.

## Interpretation

The snapshot timestamp is compared as the exact stored text that the posting
builder copies from its ledger entry. Canonical timestamp validation requires the
millisecond-precision UTC form used by the current importer. Missing, invalid or
noncanonical timestamps are counted as unknown; unequal non-null text is counted
separately. The future-time count depends on the database clock.

Balance evaluation is a **candidate model** for each visible collection: all
observed ledger entries must be positive RWF contributions with one matching
payment and snapshot, complete required fields, canonical equal timestamps and
no future time beyond the tolerance. Other groups remain unknown. The model
assumes the observed ledger is complete and starts at zero; neither assumption
is established by this diagnostic. It sorts by the recorded group-after values,
which must be unique for positive contributions, and compares cumulative group
and per-member balances. A contradiction challenges those assumptions; it is
not proof of loss, incorrect accounting or a safe basis for a write. When group
ordering is contradictory, member and chronology results are unknown.

Separately, the candidate order is compared with recorded posting times. Equal
times are counted, not used to invent an order. A chronology contradiction only
means this candidate order is not chronological according to those recorded
times. Application timestamps do not establish database commit order. Orphan
snapshots and ledger rows without a collection are counted separately and can
indicate that the visible graph does not represent a closed history.

An SMS candidate has either an `sms:` evidence-reference marker or an associated
native job. Only an unambiguous payment-to-evidence-to-financial-link-to-MoMo-
source-to-receipt-to-native-job path is compared. The selected checks compare
receipt body digest to payment-evidence plaintext digest, the native reference
and evidence-key patterns, and selected owner, collection, member, transaction,
amount, currency, event and job fields. A missing field or ambiguous path is
unknown, not a mismatch. A payment without either native marker is unclassified;
it is not automatically non-native or erroneous. No message body or storage
object is read, and digest equality does not verify bytes or provider truth.
The accepted-linkage counters separately require the source and native-job
relations to be `accepted`, matching transaction/source/job attempt identities,
an existing parse attempt tied to the same receipt and body digest, and matching
transaction/job receiving-account references. Missing linkage inputs are
unknown; known conflicts and unequal links are counted as mismatches. Other
retention, identity, custody and financial rules remain outside this check.

The result never establishes complete history, target equivalence, identity
mapping, object bytes or encryption keys, device queues, provider effects,
backups, recovery or production readiness.

## Tests

From the repository root, with the pinned Node/`pg` dependency and physical
PostgreSQL 17 binaries available:

```sh
COLLECT_SYNTHETIC_PG_BIN=/absolute/physical/postgresql-17/bin \
  node --test --test-concurrency=1 \
  scripts/supabase/current-pg-transfer/financial-consistency/consistency.test.mjs
```

The tests create and remove an owned socket-only database with invented data.
They exercise equal timestamps, alternate ordering, group/member contradictions,
unknown or malformed timestamps, reversal, missing or ambiguous SMS paths,
digest/reference mismatch, missing access, RLS filtering, inheritance, missing
columns, duplicate payment identity, rejected source/job relation, changed or
missing parse-attempt linkage and the wrong database. They do not connect
to production or prove the actual source history is complete.
