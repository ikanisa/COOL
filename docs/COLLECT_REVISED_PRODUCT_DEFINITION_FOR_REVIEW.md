# Collect Bank-Transfer-Only Product Definition

Status: approved and implemented baseline
Decision date: 2026-08-20
Canonical rules: `docs/PRODUCT.md`

## Decision

Collect uses EUR SEPA bank transfers only. Members may use Revolut, including a
Revolut-to-Revolut transfer where both sides are bank beneficiaries, but Collect
does not integrate with Revolut or any payment API. Stripe, cards, direct debit,
USSD payment initiation, member MoMo receivers, and contributor-reported
confirmation are outside the product.

The in-app beneficiary name and IBAN are governed operational data. A disabled
non-routable placeholder is installed until two different platform owners
propose and approve the real beneficiary. The approval activates the
`bank_transfer_v1` feature flag.

## Required user experience

- Settings shows the approved beneficiary, IBAN, BIC, bank, currency, scheme,
  and instant-transfer support with copy actions.
- Contribute accepts a EUR amount, creates a unique Collect reference, and
  displays an immutable destination snapshot.
- Open Revolut uses the documented app deep link and official web fallback. It
  does not pre-authorize, pre-confirm, or represent that payment succeeded.
- The waiting state distinguishes transfer requested, handoff opened, bank
  evidence received, reconciled, exception, returned, expired, and cancelled.
- Confirmed group totals include reconciled bank transactions only.
- Members never see raw SMS/email, full payer data, statement data, admin
  allocation notes, or another member's private transaction identifier.

## Required operations workflow

1. Controlled bank SMS/email ingestion records immutable raw evidence and a
   deterministic parsed event.
2. Exact reference + amount + EUR can allocate a request, but transaction and
   request remain unconfirmed.
3. An authorized administrator imports the exact bank export.
4. Daily reconciliation matches the statement and canonical transaction.
5. Reconciliation posts the balanced journal and notification exactly once.
6. Missing or conflicting matches become exceptions; no balance is changed.
7. Manual allocation requires a proposer, a different approver, exact amount
   and currency, a reason, and audit evidence.
8. Daily close records totals and variance; reopening requires a reason.

## Acceptance evidence

The implementation is acceptable only when all of the following pass:

- clean database replay and SQL lint;
- deterministic parser and HMAC unit tests;
- bank lifecycle rollback UAT covering maker-checker, idempotent evidence,
  statement finality, balanced journal, notification, and daily close;
- Flutter analyzer and full test suite;
- production Edge Function inventory contains only the reviewed bank,
  WhatsApp-auth, and notification functions;
- production contains no Stripe tables or Stripe Edge Functions;
- real beneficiary remains disabled until actual bank details are approved;
- `FCM_SERVICE_ACCOUNT_JSON` exists in Supabase and can complete an OAuth token
  exchange for the correct Firebase project;
- production Android manifest contains no RECEIVE_SMS, READ_SMS, or CALL_PHONE;
- controlled `internal_receiver` capture is authenticated and cannot reconcile
  settlement;
- production migration, functions, app/admin build, and post-deploy smoke tests
  are verified on the live project.
