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

- User must be creator/admin/receiver for the collection.
- The App permissions screen provides a prominent disclosure before Android's
  native runtime prompt and a direct recovery route to Android app settings.
- Native Android requests only `RECEIVE_SMS`, stores consent only after the OS
  grants permission, and exposes denial, permanent-denial, rationale, and app
  settings recovery state through the method channel.
- The receiver is exported only so Android telephony can deliver the protected
  broadcast; it requires the system signature permission
  `android.permission.BROADCAST_SMS` and checks the native consent flag before
  processing any PDU.
- Provider, currency, and transaction markers limit capture to likely
  MTN/Airtel mobile-money events. Unrelated and promotional SMS are discarded
  on-device.
- Matching messages are kept in a bounded Android Keystore AES-GCM encrypted
  queue, excluded from backup/device transfer, and removed only after Flutter
  acknowledges successful authenticated ingestion. Turning the feature off
  clears the queue immediately.
- Supabase consent audit rows are written through
  `record_sms_access_consent`; the Flutter app does not directly insert into
  SMS consent tables.
- Matching raw SMS is sent to Supabase, protected by RLS, and never shown
  publicly. The app does not scan or backfill inbox history.
- Ingestion is accepted only when the authenticated user is the configured
  receiver or an admin for the receiver MoMo number. Requests must include
  either `receiver_momo_number` or `collection_id`; the Edge Function hashes the
  number and checks `user_can_ingest_receiver_sms` before storing raw SMS.

Fallback policy:

- There is no manual SMS paste.
- There is no contributor-reported transaction field.
- Ambiguous parsed SMS events stay in the admin exception queue for reparse or
  investigation; ledger posting remains automated through payment-intent
  allocation.
