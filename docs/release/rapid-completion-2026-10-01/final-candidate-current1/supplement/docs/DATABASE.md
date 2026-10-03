# Collect database: current Rwanda release scope

The active product is Rwanda-only, whole-RWF MTN MoMo/Airtel Money group contributions. The migration history contains older bank and geographic-rail tables; their presence in a schema does not make a bank rail part of this release. Before GO, read back deployed grants, RPCs, Edge routes and Admin/client navigation to prove legacy bank operations are inactive for current users.

## Active financial records

- `collection_receivers` and `payment_intents` bind the authorized group receiver, payer, exact whole-RWF amount and pending request.
- `raw_payment_sms` and `parsed_payment_events` preserve protected receipt evidence and bounded parsed facts. A likely SMS is candidate evidence, not independent settlement confirmation.
- `payment_allocations`, `payments` and `ledger_entries` represent governed matching, exceptions and balanced postings. Replay, timeout, account-switch, reversal and concurrency paths require isolated relational tests.
- Current Admin list RPCs present scoped Payees, Transactions, Reconciliations and Ledgers. Their client paging and totals must be checked against complete server aggregates, not recent-page sums.

## Historical schema compatibility

Past bank migrations introduced destination, bank-intent, evidence, statement, reconciliation and journal tables. Preserve migration history and any legally required records. Do not expose their routes, permissions or listing claims in the Rwanda-only release without a separately approved product and migration decision. Their deployed presence and access grants remain an explicit readback task.

## Financial finality

Receipt capture, authenticated ingestion, parsing, unique receiver/payer/amount/reference matching, settlement reconciliation and final ledger posting are distinct states. A device-captured SMS can establish candidate evidence; it cannot independently prove that funds settled. Production confirmation requires independently reconciled provider/statement evidence or an explicitly approved constrained finality policy implemented and tested end to end. Ambiguous, duplicate, stale or unmatched evidence stays pending or in an audited exception queue.

The staged SQL in `deploy/hardening/` is not a numbered migration and has not been applied to the current production database. Apply nothing until full-schema rehearsal, role/RLS checks, migration order, rollback/roll-forward and owner approval are recorded.

## Access and verification

All financial reads and writes must use scoped RLS/RPC authority. Test direct authenticated table writes, cross-group identifiers, role revocation, security-definer behavior, raw-evidence reveal, and service-only finalization against an isolated full schema. Compare the exact reviewed migration/function hashes and grants with authorized deployed readback before any release decision.
