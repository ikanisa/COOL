# Aggregate native SMS source prerequisites

This is a separate count-only, source-local PostgreSQL diagnostic for selected
conditions of the **synthetic** native SMS importer. It does not import data or
establish readiness. It evaluates every visible SMS receipt, reports linked and
other receipts separately, and returns aggregate counts and observation time;
it does not return record IDs, fingerprints, wallet values, amounts or bodies.

The selected conditions include source UUID syntax, transaction/source ID
equality, native-job/transaction identity, the stored job/origin fingerprint
comparison, conflict and allocation state, accepted source/job relations,
matching parse/receipt/body and receiving-account links, selected successful
incoming RWF job facts, and a nonnegative safe-integer wallet balance. Missing
data or multiple joined paths are unknown; a known conflicting field is counted
as a failed selected condition. `all_selected_fields_satisfy` means only these
conditions held, not that the complete importer accepts the record. A receipt
with no financial link is not automatically invalid. A present financial link
does not establish that the entire financial graph has been checked.

Stored fingerprint equality does not recompute either fingerprint. The query
does not verify object bytes, keys, encryption or AAD, owner mapping, credential
and lease state, provenance, device queues, provider effects, unrelated tables,
the target graph, a backup or a source freeze. It uses a single repeatable-read,
read-only transaction with access-share locks and a per-statement timeout. It
requires PostgreSQL 17, the `postgres` database over a Unix socket, full table
SELECT, no active RLS filter, ordinary non-inherited tables, required column
types and unique non-null receipt identifiers. The caller must separately
authenticate the intended local container and database. Reads may affect
caches, metrics or logs, and locks can briefly delay concurrent DDL.

Run on one fresh, trusted physical session: the session precheck executes before
`BEGIN`, then the read-only transaction locks all selected tables before its
first visibility/data query and rechecks the same backend and isolation.
`psql -X -v ON_ERROR_STOP=1` sends statements separately; drivers must likewise
send the precheck and transaction as separate commands on the same connection,
with no enclosing transaction or pooler session change. Same-user or privileged
actors can defeat session markers and remain outside the lock proof. Previously
saved v3 observations predate this ordering fix and cannot rule out the
concurrent-inheritance race; they remain preserved.

Run tests from the repository root with Node/`pg` and PostgreSQL 17 available:

```sh
node --test --test-concurrency=1 \
  scripts/supabase/current-pg-transfer/financial-consistency/native-readiness-v3/diagnostic.test.mjs
```

The tests create and remove an owned socket-only cluster with invented data;
they cover mismatch, unknown and ambiguous links, invalid wallet values,
conflict and allocation state, source format, RLS, access, inheritance and
required columns. They do not contact production.
