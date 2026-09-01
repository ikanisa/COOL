# Collect architecture

Collect prepares and records group contributions through two external rails:
Rwanda MoMo USSD and diaspora EUR bank/Revolut transfer. It is not a wallet,
payment processor or custodian.

## Member journey

1. WhatsApp verification suggests the profile country and, for Rwanda numbers,
   the local MoMo provider/number. The member may edit those profile details.
2. A Rwanda member enters a whole-RWF amount; Supabase creates an exact MoMo
   intent and Android opens the governed USSD request. The PIN stays in MoMo.
3. With explicit consent, Android captures only likely incoming MoMo receipts.
   Edge parsing extracts bounded facts and the database performs the unique
   member/group allocation and exact-once ledger post.
4. A diaspora member receives an exact EUR bank-transfer request, approved
   beneficiary snapshot and reference, then authorises outside Collect in
   Revolut or a banking app.
5. Controlled bank evidence creates a candidate; daily statement
   reconciliation provides finality and posts the balanced journal once.

## Runtime surfaces

- Flutter member app and public web: profiles, private/public groups, regional
  contribution instructions, status, notifications and ledger views.
- Flutter Admin PWA: Groups and Members plus four normalized financial
  Operations pages—Payees, Transactions, Reconciliations and Ledgers. The
  underlying Rwanda parsing/allocation and diaspora maker-checker/statement
  controls remain rail-specific and auditable.
- Supabase Postgres: RLS, scoped RPCs, idempotency, reconciliation and ledger.
- Edge Functions: WhatsApp OTP, authenticated MoMo receipt ingestion/parsing,
  Play Integrity verification, bank evidence ingestion and notifications.
- Firebase Cloud Messaging: device notification delivery; no financial finality.

## Security boundaries

Android requests `RECEIVE_SMS` only for consented Rwanda MoMo receipt capture;
it never requests inbox history (`READ_SMS`) or message sending. USSD uses the
phone permission, and Android-only group creation is bound to Play Integrity.
Raw SMS stays in a protected device queue until authenticated ingestion and is
never logged. Bank email ingestion requires a timestamped HMAC. Raw evidence
reveal is capability-gated, reason-gated and audited.
