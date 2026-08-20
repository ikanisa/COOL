# Privacy and compliance notes

- Public and member surfaces never expose phone numbers, raw bank messages,
  full payer identity, admin identifiers or another member's records.
- Beneficiary bank details are visible to authenticated members only when the
  approved destination is active. The placeholder is non-routable and disabled.
- SMS/email evidence is data-minimised into channel, masked sender, amount,
  currency, reference, bank transaction identifier and parsing confidence.
- Raw evidence is stored separately, cannot be selected by normal app roles and
  requires an explicit capability, reason and audit event to reveal.
- Evidence is not settlement. Bank-statement reconciliation is required before
  ledger or balance updates.
- Notifications contain status information but never raw evidence, credentials,
  PINs, OTPs or service-account material.
- Collect does not store banking-app credentials and does not submit or authorise
  the external bank transfer.
