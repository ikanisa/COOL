# Collect database: current Rwanda release scope

The active product is Rwanda-only, whole-RWF MTN MoMo/Airtel Money group contributions. The migration history contains older bank and geographic-rail tables; their presence in a schema does not make a bank rail part of this release. Before GO, read back deployed grants, RPCs, Edge routes and Admin/client navigation to prove legacy bank operations are inactive for current users.

## Active financial records

- `users`, `collections` and `payment_intents` hold member, group receiver and pending whole-RWF contribution state in the curated baseline.
- `sms_receipts` records owner-bound capture metadata and an object identity; the corresponding retained payload is protected separately. A captured SMS is candidate evidence, not independent settlement confirmation.
- `request_receipts` retains operation/session/body binding for idempotent outcomes. `payments` and `ledger_entries` represent governed financial records. Replay, timeout, account-switch, reversal and concurrency paths require isolated relational tests.
- Admin pages use server-scoped list and detail contracts. Their client paging and totals must be checked against complete server aggregates, not recent-page sums.

## Historical schema compatibility

Past bank migrations introduced destination, bank-intent, evidence, statement, reconciliation and journal tables. Preserve migration history and any legally required records. Do not expose their routes, permissions or listing claims in the Rwanda-only release without a separately approved product and migration decision. Their deployed presence and access grants remain an explicit readback task.

## Financial finality

Receipt capture, authenticated ingestion, parsing, unique receiver/payer/amount/reference matching, settlement reconciliation and final ledger posting are distinct states. A device-captured SMS can establish candidate evidence; it cannot independently prove that funds settled. Production confirmation requires independently reconciled provider/statement evidence or an explicitly approved constrained finality policy implemented and tested end to end. Ambiguous, duplicate, stale or unmatched evidence stays pending or in an audited exception queue.

The generator produces `supabase/schema-src/baseline.sql` from the recorded source inputs. The current baseline bytes match `supabase/migrations/20261020134444_collect_curated_platform_baseline.sql`; later numbered migrations are separate inputs. Historical or staged SQL is not evidence of application to a deployed database. Rehearse the complete reviewed migration chain, role/RLS checks and recovery plan before a release decision.

## Access and verification

Financial operations require scoped server-side session and permission authority and the database's applicable role, RLS and transaction controls. Test direct authenticated table writes, cross-group identifiers, role revocation, raw-evidence reveal and finalization against an isolated full schema. Compare the exact reviewed migration/function hashes and grants with authorized deployed readback before any release decision.
