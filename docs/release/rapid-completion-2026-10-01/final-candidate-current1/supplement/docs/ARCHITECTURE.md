# Collect architecture: Rwanda MoMo scope

Collect is a Rwanda-only group-contribution and record-keeping service. Members use whole Rwandan francs through MTN MoMo or Airtel Money USSD. Collect does not hold funds, collect a MoMo PIN or OTP, or claim that a device-observed SMS independently proves settlement. Historical diaspora and bank-transfer code or records are outside the current product scope and require explicit proof of inactivity before production GO.

## Member journey

1. WhatsApp verification and a completed Rwanda profile establish the member's Collect ID, country `RW`, currency `RWF`, and MoMo provider/number.
2. An eligible member enters a whole-RWF amount. Supabase creates a pending intent bound to the payer and exact group receiver; Android opens the provider's USSD prompt. The PIN remains with the mobile network.
3. With explicit consent on an eligible Android receiver device, Collect captures only newly arriving likely MoMo receipt SMS into a protected queue. Authenticated ingestion and deterministic parsing produce candidate evidence.
4. The server evaluates owner, receiver, payer, amount, transaction ID, time window, replay and ambiguity. A durable acknowledgement may clear only the exact persisted envelope for the current owner.
5. Financial confirmation and balanced ledger posting require independent provider/statement reconciliation or an explicitly approved constrained finality policy. Until that policy is implemented and proven on the deployed backend, candidate receipt matches remain a production-readiness gap.

## Runtime surfaces

- Flutter member app and public website: Rwanda profiles, private/public groups, MoMo contribution instructions, truthful pending/unknown status, notifications and ledger views.
- Flutter Admin PWA: Groups and Members plus MoMo Payees, Transactions, Reconciliations and Ledgers, with scoped roles and audited exception handling.
- Supabase Postgres: row-level security, scoped RPCs, idempotent evidence and posting transitions, reconciliation and immutable balanced journal.
- Supabase Edge Functions: WhatsApp OTP, authenticated receipt ingestion/parsing, Play Integrity verification and notifications.
- Firebase Cloud Messaging: device notification delivery; it does not prove financial finality.

## Security and release boundaries

Android requests `RECEIVE_SMS` only for consented Rwanda receipt capture; it does not request inbox history (`READ_SMS`) or message sending. USSD uses the phone permission. Group creation on Android is bound to product eligibility and Play Integrity. Raw SMS remains protected until authenticated durable ingestion, and raw-evidence reveal is capability-gated, reason-gated and audited.

Current source, staged SQL, deployed database/function state, physical MTN/Airtel journeys, signed store artifacts, privacy/legal position and accountable approval must be verified against one release candidate. Existing historical bank paths and documentation are not evidence that a bank rail is supported in the Rwanda-only release.
