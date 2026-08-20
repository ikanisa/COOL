# Collect database

The production financial model is bank-transfer-only. The authoritative cutover
is `supabase/migrations/20260820162240_bank_transfer_only_financial_control_plane.sql`.

## Financial records

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

SMS and email can create evidence and a received-but-unreconciled candidate.
Only a matching imported bank statement can mark a receipt reconciled and post
the balanced ledger entry. Evidence ingestion never updates member balances.

## Access

All financial tables have RLS. Members use scoped RPCs for the active
beneficiary, transfer-request creation and their own contribution status.
Admin RPCs require explicit capabilities for bank details, transactions,
evidence, raw reveal, reconciliation and maker-checker approvals. Raw evidence
is not directly selectable by app roles.

## Retired systems

The cutover fails closed if Stripe rows need export, then removes Stripe
persistence. It revokes the former payment-intent, MoMo receiver, SMS-parser and
allocation functions and removes their admin navigation. Historical migrations
remain immutable repository history; they are not the active production model.
