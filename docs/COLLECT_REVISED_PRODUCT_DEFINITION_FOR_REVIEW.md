# Collect Geographic Payment-Rails Product Definition

Status: approved and implemented baseline
Decision date: 2026-08-31
Canonical rules: `docs/PRODUCT.md`

## Decision

Collect uses Rwanda MoMo USSD/SMS for Rwanda profiles and Revolut/SEPA bank transfer
for diaspora profiles. It does not integrate with a payment provider or
collect a MoMo PIN, bank password, card detail, or OTP. The profile country
selects the journey; it does not change an existing financial record's rail.

Diaspora beneficiary name and IBAN are governed operational data. A disabled
non-routable placeholder is installed until two different platform owners
propose and approve the real beneficiary. The approval activates the
`bank_transfer_v1` feature flag.

## Required user experience

- WhatsApp onboarding suggests country and a local Rwanda MoMo number. Members
  can edit country/provider/number or enter diaspora Revolut link, name, and
  account details.
- User-created groups are private and created only on Android after SMS consent
  and Play Integrity. Public groups are platform-sponsored.
- Rwanda Contribute creates one RWF payer intent and opens the provider USSD
  route. Receipt matching updates the ledger only through server controls.
- Settings shows the approved beneficiary, IBAN, BIC, bank, currency, scheme,
  and instant-transfer support for diaspora profiles.
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

1. Consented Android MoMo receipt ingestion records immutable raw evidence and a
   deterministic parsed event for Rwanda.
2. One exact receiver, payer, RWF amount, transaction ID, and time-window match
   posts atomically; incomplete or ambiguous items stay in admin review.
3. Controlled diaspora bank SMS/email ingestion records immutable raw evidence and a
   deterministic parsed event.
4. Exact reference + amount + EUR can allocate a request, but transaction and
   request remain unconfirmed.
5. An authorized administrator imports the exact bank export.
6. Daily reconciliation matches the statement and canonical transaction.
7. Reconciliation posts the balanced journal and notification exactly once.
8. Missing or conflicting matches become exceptions; no balance is changed.
9. Manual bank allocation requires a proposer, a different approver, exact amount
   and currency, a reason, and audit evidence.
10. Daily bank close records totals and variance; reopening requires a reason.

## Acceptance evidence

The implementation is acceptable only when all of the following pass:

- clean database replay and SQL lint;
- deterministic MoMo parser and bank HMAC unit tests;
- bank lifecycle rollback UAT covering maker-checker, idempotent evidence,
  statement finality, balanced journal, notification, and daily close;
- Flutter analyzer and full test suite;
- production Edge Function inventory contains only the reviewed MoMo, bank,
  WhatsApp-auth, Play-Integrity, and notification functions;
- production contains no Stripe tables or Stripe Edge Functions;
- real beneficiary remains disabled until actual bank details are approved;
- `FCM_SERVICE_ACCOUNT_JSON` exists in Supabase and can complete an OAuth token
  exchange for the correct Firebase project;
- production Android manifest contains `RECEIVE_SMS` and `CALL_PHONE`, but no
  `READ_SMS`, `SEND_SMS`, or Call Log permission;
- Google Play approves the restricted SMS declaration before release;
- real Android devices prove MTN/Airtel USSD, consent, receipt parsing,
  allocation, exception review, and ledger posting without exposing raw SMS;
- production migration, functions, app/admin build, and post-deploy smoke tests
  are verified on the live project.
