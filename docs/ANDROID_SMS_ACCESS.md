# Android SMS App Access

SMS app access is Android-only and restricted to the `internal_receiver` flavor.

Feature flags:

- `ENABLE_ANDROID_SMS_ACCESS`
- `ENABLE_SMS_READER`

The production Android manifest does not include `READ_SMS` or `RECEIVE_SMS`. The restricted permissions are contributed only by `android/app/src/internal_receiver/AndroidManifest.xml`.

Consent requirements:

- User must be creator/admin/receiver for the collection.
- User must explicitly grant Android SMS runtime permission.
- Flutter records consent through the `collect/sms_access` Android method
  channel. Native Android requests `RECEIVE_SMS` and `READ_SMS`, stores consent
  only after the OS grants permission, and the internal SMS receiver checks that
  native consent flag before it reads SMS PDUs, filters likely mobile-money
  notifications, and queues only consented messages for Flutter to drain.
- Supabase consent audit rows are written through
  `record_sms_access_consent`; the Flutter app does not directly insert into
  SMS consent tables.
- App explains what is collected and why.
- Raw SMS is sent to Supabase, protected by RLS, and never shown publicly.
- Ingestion is accepted only when the authenticated user is the configured
  receiver or an admin for the receiver MOMO number. Requests must include
  either `receiver_momo_number` or `collection_id`; the Edge Function hashes the
  number and checks `user_can_ingest_receiver_sms` before storing raw SMS.

Fallback policy:

- There is no manual SMS paste.
- There is no contributor-reported transaction field.
- Ambiguous parsed SMS events stay in the admin exception queue for reparse or
  investigation; ledger posting remains automated through payment-intent
  allocation.
