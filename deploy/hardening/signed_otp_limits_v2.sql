-- Retained source entry point; the original v2 contract is superseded by
-- supabase/migrations/20260930130000_signed_otp_uncertain_recovery.sql.
-- Applying this old staged definition after v3 would remove send fencing and
-- allow unknown provider sends to be acknowledged without bound evidence.
-- Run the canonical migration chain instead. Configure its private policy
-- singleton explicitly; no credentials or production quotas are supplied here.
do $$ begin
 raise exception 'Deprecated OTP staged installer: use canonical signed OTP recovery migration'
   using errcode='55000';
end $$;
