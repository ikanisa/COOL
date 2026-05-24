# SMS Receiver Mode

Receiver Mode is Android-only and restricted to the `internal_receiver` flavor.

Feature flags:

- `ENABLE_INTERNAL_RECEIVER_MODE`
- `ENABLE_SMS_READER`

The production Android manifest does not include `READ_SMS` or `RECEIVE_SMS`. The restricted permissions are contributed only by `android/app/src/internal_receiver/AndroidManifest.xml`.

Consent requirements:

- User must be creator/admin/receiver for the collection.
- User must explicitly enable receiver mode.
- Flutter records consent through the `collect/receiver_mode` Android method
  channel. The internal SMS receiver checks that native consent flag before it
  reads SMS PDUs, filters likely mobile-money notifications, and queues only
  consented messages for Flutter to drain.
- Supabase consent audit rows are written through
  `record_receiver_mode_consent`; the Flutter app does not directly insert into
  `receiver_mode_consents`.
- App explains what is collected and why.
- Raw SMS is sent to Supabase, protected by RLS, and never shown publicly.
- Ingestion is accepted only when the authenticated user is the configured
  receiver or an admin for the receiver MOMO number. Requests must include
  either `receiver_momo_number` or `collection_id`; the Edge Function hashes the
  number and checks `user_can_ingest_receiver_sms` before storing raw SMS.

Fallback:

- Manual SMS paste.
- Manual transaction field entry.
- Admin review queue for ambiguous allocation.
