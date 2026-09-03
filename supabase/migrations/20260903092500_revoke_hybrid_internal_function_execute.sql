begin;

-- Trigger helpers and internal account-claim implementation are never direct
-- client/service APIs. The public wrapper runs as its fixed-path owner while
-- the internal implementation still resolves auth.uid() from the caller JWT.
-- This preserves the reviewed authenticated API without exposing the private
-- schema routine directly.
create or replace function public.claim_verified_current_account()
returns jsonb
language sql
security definer
set search_path = ''
as $$ select collect_hybrid.claim_verified_current_account(); $$;

revoke all on function collect_hybrid.enqueue_sms_receipt_from_snapshot()
  from public, anon, authenticated, service_role;
revoke all on function collect_hybrid.claim_verified_current_account()
  from public, anon, authenticated, service_role;
revoke all on function public.claim_verified_current_account()
  from public, anon, authenticated, service_role;
grant execute on function public.claim_verified_current_account()
  to authenticated;

notify pgrst, 'reload schema';

commit;
