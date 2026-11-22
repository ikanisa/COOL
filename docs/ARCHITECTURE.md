# Collect architecture: Rwanda MoMo scope

Collect is a Rwanda-only group-contribution and record-keeping service. Members use whole Rwandan francs through MTN MoMo or Airtel Money USSD. Collect does not hold funds, collect a MoMo PIN or OTP, or claim that a device-observed SMS independently proves settlement. Historical diaspora and bank-transfer code or records are outside the current product scope and require explicit proof of inactivity before production GO.

## Member journey

1. The current authentication source includes WhatsApp, email and SMS flows and a limited guest path. Provider configuration and verification determine which paths are available; guest access does not itself establish a verified member account.
2. An eligible member enters a whole-RWF amount. The backend prepares a pending intent bound to the member and group receiver; the Android flow reviews current details before handing off to the provider's USSD prompt. The PIN remains with the mobile network. A device-local handoff journal is not proof of account-wide duplicate prevention.
3. With explicit consent, the ordinary Android member app can capture eligible newly arriving MoMo SMS into an owner-bound protected queue. An optional dedicated receiver has a separate enrollment and inbox-recovery workflow. Authenticated ingestion produces candidate evidence, not settlement proof.
4. The server evaluates owner, receiver, payer, amount, transaction ID, time window, replay and ambiguity. A durable acknowledgement may clear only the exact persisted envelope for the current owner.
5. Financial confirmation and balanced ledger posting require independent provider/statement reconciliation or an explicitly approved constrained finality policy. Until that policy is implemented and proven on the deployed backend, candidate receipt matches remain a production-readiness gap.

## Runtime surfaces

- The Flutter member app owns Rwanda profiles, private and public groups, MoMo contribution instructions, pending and unknown payment states, notifications and ledger views. [Member entrypoint](../lib/main.dart)
- The public website renders product and legal pages, deep-link entry pages and reviewed app previews using the static site generator. [Site builder](../scripts/public_static_site_build.rb) · [Legal renderer](../scripts/public_legal_rendering.rb)
- BuriMunsi Staff and Admin Sync are native Android variants. They share the Kotlin app and verified wire contracts. Each variant has its own package and permission boundary. [Native source](../native/burimunsi) · [API 36 verification](implementation/2026-11-20-burimunsi-android-verification.json)
- React Admin PWA: `admin-web/` owns the browser workspace for Groups, Members, Payees, Transactions, Reconciliations, Ledgers and operator workflows with scoped roles and audited exception handling. Supabase owns access and writes.
- Supabase Postgres, Edge Functions and protected storage: curated schema and application handlers for account, session, permission, receipt and financial workflows. Member bearer sessions and Admin cookie sessions have separate admission paths.
- Frontend hosting and transport use the managed Collect project `rrlduytparvsjfmegalh` on Supabase Cloud. The Admin and member API can use their configured application origins while keeping the same project and Auth issuer.
- Notification delivery is separately governed. Current scheduled push processing is Android/FCM-oriented; registration of another device type does not establish delivery for it.

## Security and release boundaries

The ordinary member build declares `RECEIVE_SMS` for consented capture and does not request `READ_SMS` or `SEND_SMS`. The separate internal receiver declares `READ_SMS`; the internal gateway declares `SEND_SMS` for its distinct sending workflow. USSD uses the phone permission. The native source binds capture to consent and an owner. Raw evidence access requires server-side authorization; review the reason and audit controls for each exposed route before relying on them universally.

Current source, staged SQL, deployed database/function state, physical MTN/Airtel journeys, signed store artifacts, privacy/legal position and accountable approval must be verified against one release candidate. Existing historical bank paths and documentation are not evidence that a bank rail is supported in the Rwanda-only release.
