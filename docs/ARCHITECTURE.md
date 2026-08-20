# Collect architecture

Collect prepares and records group contributions made through external EUR bank
transfers. It is not a wallet, payment processor or custodian.

## Member journey

1. A member chooses a group and enters a EUR amount.
2. Supabase creates a bank transfer request with an exact reference and an
   approved beneficiary snapshot.
3. The app shows copyable beneficiary name, IBAN, BIC, bank, amount and reference.
4. The app opens Revolut when available, otherwise its HTTPS app page. The user
   selects the saved beneficiary and authorises the transfer in the banking app.
5. Collect records only that the handoff opened; it never fabricates success.
6. Bank SMS or email creates protected candidate evidence.
7. The daily statement independently confirms the receipt.
8. Reconciliation posts one balanced immutable journal and updates the member
   and group contribution state exactly once.

## Runtime surfaces

- Flutter member app and public web: groups, members, transfer requests,
  beneficiary settings, contribution status, notifications and ledger views.
- Flutter Admin PWA: users, admin users, groups, beneficiary maker-checker,
  transfer requests, bank transactions, evidence, statements, reconciliation,
  exceptions, allocation approvals, journal, notifications, settings, flags,
  health and audit logs.
- Supabase Postgres: RLS, scoped RPCs, idempotency, reconciliation and ledger.
- Edge Functions: WhatsApp OTP, bank SMS/email/statement ingestion and
  notification dispatch only.
- Firebase Cloud Messaging: device notification delivery; no financial finality.

## Security boundaries

The public Android flavour has no SMS-reading, SMS-receiving or phone-call
permission. A separately governed internal receiver flavour may capture bank
notification SMS after explicit operator consent. Bank email ingestion requires
a timestamped HMAC. Raw evidence reveal is capability-gated, reason-gated and
audited. Placeholder bank details remain disabled until independently approved.
