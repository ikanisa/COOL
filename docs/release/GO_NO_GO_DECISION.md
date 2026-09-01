# Go / no-go decision

Current decision: **NO-GO for production; local hybrid implementation only**.

The approved architecture is Rwanda MoMo USSD plus consented Android receipt
reconciliation, and diaspora EUR SEPA/Revolut bank transfer. Stripe, cards,
direct debit, pasted transaction IDs and contributor-reported success remain
outside the product.

A Go decision requires all of the following:

- hybrid migration chain applied and read back in production;
- MoMo ingestion/parser/Integrity functions and bank functions deployed;
- Play restricted-SMS approval and a configured Integrity cloud project;
- physical Rwanda MTN/Airtel USSD, receipt, duplicate and exception UAT;
- approved, non-placeholder beneficiary details enabled by independent checker;
- May2026 Firebase configuration and FCM delivery validated;
- real MoMo allocation plus bank-statement finality, balanced ledgers,
  reconciliation and notification delivery proven end to end;
- store, physical-device, accessibility and accountable release approvals.

Local tests or a successful build do not satisfy those external gates.
