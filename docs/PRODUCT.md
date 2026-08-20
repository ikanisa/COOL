# Collect Product Source of Truth

Status: approved implementation baseline
Effective: 2026-08-20

Collect organizes group contributions paid by EUR SEPA bank transfer. It does
not operate a wallet, acquire cards, debit bank accounts, initiate payments, or
move money through an API. Stripe and the former member MoMo/USSD contribution
rail are retired.

## Non-negotiable rules

- Member identity remains Collect ID-first; payer and sign-in details are not
  exposed in public or ordinary group surfaces.
- One centrally approved Collect beneficiary bank account serves all groups.
- Bank details are activated only through independent maker-checker approval.
- The app displays beneficiary name, IBAN, BIC, amount, and a unique transfer
  reference. Placeholder details are disabled and cannot accept transfers.
- `Open Revolut` is a handoff only. Collect never marks a transfer successful
  because another app opened or because the member returned.
- SMS and email are candidate receipt evidence. They can allocate an exact
  transfer request but cannot finalize settlement or change confirmed balances.
- Only a matching bank statement can reconcile a receipt and post the journal.
- Every financial post is idempotent, balanced, immutable, and auditable.
- Ambiguous, duplicate, missing, returned, or inconsistent evidence posts
  nothing and enters the appropriate admin exception queue.
- A manual allocation requires an exact amount/currency match and independent
  maker-checker approval.
- Raw bank evidence is separately permissioned and every reveal records a
  reason in sensitive-access and audit logs.

## Member journey

1. Sign in through WhatsApp OTP and receive a six-digit Collect ID.
2. Create or join a group on Android or iPhone. Group creation is no longer
   tied to SMS permission, a receiver phone, or Play Integrity payment proof.
3. Tap Contribute and enter a positive EUR amount.
4. Supabase creates or reuses an unexpired transfer request containing the
   group, member, approved destination snapshot, amount, and unique `COL-…`
   reference.
5. Copy the beneficiary fields and open Revolut. Add/select the beneficiary,
   enter the amount and exact reference, and authorize the bank transfer.
6. Return to Collect. The request stays pending until controlled bank evidence
   arrives and then remains `received_unreconciled` until statement matching.
7. After reconciliation, Collect shows the confirmed contribution and sends a
   preference-gated notification.

## Evidence and reconciliation

Controlled channels accept beneficiary-bank SMS, bank email webhooks, and bank
statement exports. Deterministic rules extract direction, EUR amount, Collect
reference, provider transaction/end-to-end identifiers, timestamps, and
limited payer metadata. No AI service is used to decide financial allocation.

Evidence is deduplicated by source identifier and body hash. Canonical bank
transactions are deduplicated by provider identifiers and transaction key.
Daily statement imports support CSV, JSON, MT940, and CAMT.053, are
SHA-256-deduplicated, and automatically run reconciliation for the declared
period end.

Matching prioritizes bank transaction ID, then end-to-end ID, then exact
reference + amount + currency within the controlled date window. Confirmed
receipts post:

- debit `bank_cash:EUR`;
- credit `collection_liability`.

Daily closes record statement total, reconciled total, variance, transaction
count, exception count, and balanced/exception state. Reopening a close requires
permission, a reason, and an audit record.

## Admin scope

The Admin PWA manages:

- users, members, groups, and admin users/roles;
- beneficiary versions and maker-checker change requests;
- transfer requests and bank transactions;
- SMS, email, and statement evidence with gated raw reveal;
- statement imports, daily reconciliation, closes, and exceptions;
- maker-checker manual allocations;
- immutable double-entry journals;
- notification queues and FCM/APNs delivery evidence;
- feature flags, runtime settings, audit logs, and system health.

Client routing is not an authorization boundary. PostgreSQL permissions,
security-definer RPCs, RLS, role permissions, immutable triggers, and audit logs
enforce the control plane.

## Release boundary

The production Android member app declares no SMS or phone-call permission.
The `internal_receiver` Android flavor is a separately identified operations
build that can capture only new, bank-like EUR notification SMS after explicit
enablement by an authenticated operator with `bank_evidence.ingest`. It sends
candidate evidence to production and cannot bypass statement finality.

FCM uses a dedicated Google service-account JSON stored only in Supabase Edge
Function secrets. The credential is never bundled with Flutter or committed.
