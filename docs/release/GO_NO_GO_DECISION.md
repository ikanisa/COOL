# Go / no-go decision

Current decision: **deployment in progress; Go-Live not yet evidenced**.

The approved production architecture is EUR SEPA/Revolut bank transfer only.
Stripe, cards, direct debit, member MoMo receiver routes, USSD initiation and
contributor-reported payment success are outside the product.

A Go decision requires all of the following:

- bank-only migration applied and verified in production;
- exact six Edge Functions deployed and retired functions absent;
- approved, non-placeholder beneficiary details enabled by independent checker;
- May2026 Firebase configuration and FCM delivery validated;
- real receipt evidence, independent bank-statement finality, balanced ledger,
  reconciliation and notification delivery proven end to end;
- store, physical-device, accessibility and accountable release approvals.

Local tests or a successful build do not satisfy those external gates.
