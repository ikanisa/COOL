-- ==========================================================================
-- Cool App - Persist the OTP / WhatsApp number alongside ingested MoMo SMS
-- so inbox-driven parsing can always be tied back to the authenticated user
-- context that granted device SMS access.
-- ==========================================================================

alter table public.momo_sms_raw
  add column if not exists otp_whatsapp_number text;

comment on column public.momo_sms_raw.otp_whatsapp_number is
  'WhatsApp / OTP phone number attached to the authenticated app user at SMS ingest time.';

update public.momo_sms_raw as raw
set otp_whatsapp_number = users.phone
from public.users as users
where raw.user_id = users.id
  and raw.otp_whatsapp_number is null
  and nullif(btrim(coalesce(users.phone, '')), '') is not null;
