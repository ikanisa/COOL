-- ==========================================================================
-- Cool App - Authenticated credit-score refresh RPC
-- ==========================================================================

create or replace function public.refresh_my_credit_score()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  return public.recompute_credit_score(v_user_id, now());
end;
$$;

revoke all on function public.refresh_my_credit_score() from public;
grant execute on function public.refresh_my_credit_score() to authenticated;
