# Android SMS App Access

SMS app access is Android-only. Both the `production` and
`internal_receiver` flavors declare the minimum `RECEIVE_SMS` permission;
development builds omit the restricted receiver.

No flavor declares `READ_SMS`, `SEND_SMS`, inbox-history, Call Log, contacts,
or storage access. The production receiver handles only new
`android.provider.Telephony.SMS_RECEIVED` broadcasts. Google Play distribution
must stay blocked until the SMS Permissions Declaration is accepted for the
SMS-based money-management core use case.

Consent and data-handling controls:

- The signed-in user must own an active configured receiving route.
- The App permissions screen provides a prominent disclosure before Android's
  native runtime prompt and a direct recovery route to Android app settings.
- Native Android requests only `RECEIVE_SMS`, stores consent only after the OS
  grants permission, and exposes denial, permanent-denial, rationale, and app
  settings recovery state through the method channel.
- The receiver is exported only so Android telephony can deliver the protected
  broadcast; it requires the system signature permission
  `android.permission.BROADCAST_SMS` and checks the native consent flag before
  processing any PDU.
- Provider and transaction markers, together with either an RWF/FRW marker or
  an amount plus transaction reference, limit capture to likely MTN/Airtel
  mobile-money events. Unrelated and promotional SMS are discarded on-device.
- Matching messages are kept in a bounded Android Keystore AES-GCM encrypted
  queue, excluded from backup/device transfer, and removed only after Flutter
  acknowledges successful authenticated ingestion. Turning the feature off
  clears the queue immediately.
- Supabase consent audit rows are written through
  `record_sms_access_consent`; the Flutter app does not directly insert into
  SMS consent tables.
- Matching raw SMS is sent to Supabase, protected by RLS, and never shown
  publicly. The Supabase parser sends the opted-in message to the OpenAI API
  for strict structured parsing. The app does not scan or backfill inbox
  history.
- Ingestion is accepted only when the authenticated user controls at least one
  configured group receiver. When exactly one receiver is known or explicitly
  present in the SMS, the app sends that receiver for hashing. With multiple
  possible receivers, it does not guess: the Edge Function still captures the
  raw receipt, and Postgres may derive a route only from one unique exact
  payer/amount/time intent owned by the same SMS-receiving account. Multiple or
  missing matches stay in review and never post.
- SMS receipt, parsing, and intent allocation are candidate evidence only.
  They can never settle a payment or update a payer/group balance. Ledger
  posting requires a separately authenticated, replay-safe provider-finality
  event, followed by independent reconciliation of both balances.

Fallback policy:

- There is no manual SMS paste.
- There is no contributor-reported transaction field.
- Ambiguous parsed SMS events stay in the admin exception queue for
  investigation; payment-intent allocation never posts the ledger without
  independently authenticated provider finality.
