# Collect Product Source of Truth

Status: approved implementation baseline
Effective: 2026-08-31

Collect organizes group contributions on geography-specific rails. Rwanda is
RWF MoMo USSD with consented Android receipt SMS; the diaspora is Revolut/SEPA
bank transfer. Collect does not operate a wallet, acquire cards, hold funds, or
ask for MoMo PINs, banking credentials, card details, or OTPs.

## Non-negotiable rules

- Member identity remains Collect ID-first; payer and sign-in details are not
  exposed in public or ordinary group surfaces.
- WhatsApp suggests the initial country and Rwanda MoMo number; members may edit
  country, provider, MoMo number, or diaspora Revolut details.
- Every user-created group is private and may be created only on Android after
  SMS consent and Play Integrity verification.
- Public groups are created or approved only by the platform, including Buri
  Munsi, Gikundiro, and other sponsored groups.
- Rwanda groups use the owner's configured MoMo receiver. Diaspora transfers use
  the centrally approved Collect beneficiary bank account.
- Bank details are activated only through independent maker-checker approval.
- The app displays beneficiary name, IBAN, BIC, amount, and a unique transfer
  reference. Placeholder details are disabled and cannot accept transfers.
- `Open Revolut` is a handoff only. Collect never marks a transfer successful
  because another app opened or because the member returned.
- Rwanda MoMo SMS can post only after an exact payer, receiver, RWF amount,
  transaction ID, and time-window match to one pending intent.
- Diaspora SMS/email is candidate evidence; only a matching bank statement can
  finalize its settlement and post the journal.
- Every financial post is idempotent, balanced, immutable, and auditable.
- Ambiguous, duplicate, missing, returned, or inconsistent evidence posts
  nothing and enters the appropriate admin exception queue.
- A manual allocation requires an exact amount/currency match and independent
  maker-checker approval.
- Raw MoMo and bank evidence is separately permissioned and every reveal records a
  reason in sensitive-access and audit logs.

## Member journey

1. Sign in through WhatsApp OTP and receive a six-digit Collect ID.
2. Confirm or edit the suggested country and regional payment details.
3. Join a group on any supported client. Create a private group only on Android,
   with SMS consent and device verification.
4. In Rwanda, enter a whole-RWF amount, review the exact receiver, open MoMo
   USSD, and enter the PIN only in the provider prompt.
5. In the diaspora, enter a currency amount, review the approved beneficiary and
   unique reference, then authorize the transfer in Revolut or a banking app.
6. Return to Collect. The request stays pending until its rail-specific evidence
   is reconciled.
7. Collect shows only confirmed contributions and sends a preference-gated
   notification.

## Evidence and reconciliation

On a consented Rwanda receiver device, Android captures only new likely MoMo
receipt broadcasts. The message is encrypted in a bounded device queue, uploaded
from the matching authenticated account, deterministically parsed, and matched
by server-only functions. Ambiguous, incomplete, duplicate, reversed, or
unmatched evidence posts nothing and enters the MoMo admin queue.

For diaspora, controlled channels accept beneficiary-bank SMS, bank email webhooks, and bank
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
- one Payees page for Rwanda MoMo receivers and diaspora account payees;
- one Transactions page for received SMS/account messages, parsed details and
  linked payees;
- one Reconciliations page for exceptions and unallocated payments, retaining
  strict Rwanda matching and diaspora maker-checker actions;
- one Ledgers page for balanced Rwanda allocation and diaspora journal views;
- protected raw SMS, email and statement evidence with gated reveal;
- the underlying beneficiary approvals, statement reconciliation and immutable
  journals without exposing separate rail-specific menu bundles;
- notification queues and FCM/APNs delivery evidence;
- feature flags, runtime settings, audit logs, and system health.

Client routing is not an authorization boundary. PostgreSQL permissions,
security-definer RPCs, RLS, role permissions, immutable triggers, and audit logs
enforce the control plane.

## Release boundary

The production Android member app declares `RECEIVE_SMS` and `CALL_PHONE` for
the Rwanda MoMo route, while excluding `READ_SMS`, `SEND_SMS`, and Call Log
permissions. The runtime remains disabled until a signed-in Rwanda member gives
consent. Google Play restricted-permission approval and real-device evidence are
mandatory release gates.

FCM uses a dedicated Google service-account JSON stored only in Supabase Edge
Function secrets. The credential is never bundled with Flutter or committed.
