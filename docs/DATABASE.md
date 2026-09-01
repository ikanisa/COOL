# Collect database

The financial model is geographically split: Rwanda uses MoMo USSD with
consented Android receipt ingestion, while diaspora members use the governed
EUR bank/Revolut rail. The hybrid layer is
`supabase/migrations/20260831084646_hybrid_geographic_payment_rails.sql` and
builds on the existing bank control plane.

## Financial records

- `collection_receivers`, `payment_intents`, `raw_payment_sms`,
  `parsed_payment_events`, `payment_allocations`, `payments` and
  `ledger_entries` govern Rwanda MoMo requests, receipt evidence, matching,
  exception review and exact-once posting.

- `bank_transfer_destinations` and `bank_destination_change_requests` govern
  beneficiary name, IBAN, BIC, bank, SEPA Instant capability, versioning and
  independent maker-checker approval.
- `bank_transfer_intents` holds a member, group, EUR minor-unit amount, unique
  transfer reference and destination snapshot. It is a transfer request, not a
  claim that money moved.
- `raw_payment_evidence`, `bank_evidence_events` and
  `payment_evidence_links` preserve idempotent, protected SMS/email evidence.
- `bank_transactions` is the canonical receipt record.
- `bank_statement_imports` and `bank_statement_lines` provide independent bank
  finality for daily reconciliation.
- `reconciliation_runs`, `reconciliation_matches`,
  `reconciliation_exceptions` and `daily_bank_closes` govern matching and close.
- `bank_allocation_change_requests` enforces maker-checker manual allocation.
- `journal_entries` and `journal_lines` are immutable, exact-once and balanced.

## Settlement boundary

For Rwanda, a scoped receipt parser can extract facts but cannot select a group
or update a balance; the database allocates only a unique server-side match to
an active intent. Ambiguous or unmatched receipts stay in the admin queue. For
diaspora, SMS and email remain candidate evidence and only a matching imported
bank statement provides settlement finality. In both rails, evidence ingestion
alone never updates member balances.

## Access

All financial tables have RLS. Members use scoped RPCs for the active
beneficiary, transfer-request creation and their own contribution status.
Admin RPCs require explicit capabilities for MoMo intent/event/allocation/
ledger queues and for diaspora bank details, transactions, evidence, raw
reveal, reconciliation and maker-checker approvals. Raw evidence is not
directly selectable by app roles.

The normalized Admin Operations contract is implemented by
`20260831095454_collect_admin_operations_model.sql`. Its four list RPCs and one
transaction-detail RPC project both rails into Payees, Transactions,
Reconciliations and Ledgers. They do not merge the underlying settlement rules:
Rwanda remains verified receipt-to-intent posting and diaspora remains
statement-final plus maker-checker where manual allocation is required.

## Retired systems

The earlier bank-only cutover retired Stripe persistence and temporarily
revoked MoMo functions. The hybrid migration restores the hardened MoMo
control plane for Rwanda while retaining bank settlement for diaspora.
Historical migrations remain immutable repository history.
