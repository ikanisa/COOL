begin;

-- Resolve readable groups once, not once for every historical payment.
-- Preserve the complete response and the existing authorization/privacy rules.
-- Pagination is a separate client/API change; this never truncates history.
create or replace function collect_member_actions.payment_history()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare actor uuid := auth.uid(); result jsonb;
begin
  if actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  with readable as materialized (
    select c.id from public.collections c
    where public.user_can_read_collection(c.id, actor)
  ), history as (
    select p.posted_at as happened_at, jsonb_build_object(
      'payment_id','momo:'||p.id,'collection_id',p.collection_id,
      'amount_minor',p.amount_rwf,'currency',p.currency,'rail','rwanda_momo',
      'posted_at',p.posted_at,
      'transaction_id',case when p.contributor_user_id=actor then p.transaction_id end,
      'is_current_user_contribution',coalesce(p.contributor_user_id=actor,false),
      'supporter_label',case when p.contributor_user_id=actor then 'You'
        when p.anonymity_choice='public_id' and p.contributor_public_id is not null
          then 'Collect ID '||p.contributor_public_id else 'Anonymous supporter' end
    ) as item
    from public.payments p
    where p.status='posted' and (p.contributor_user_id=actor
      or p.collection_id in (select id from readable))
    union all
    select t.reconciled_at, jsonb_build_object(
      'payment_id','bank:'||t.id,'collection_id',a.collection_id,
      'amount_minor',t.amount_minor,'currency',t.currency,'rail','diaspora_bank',
      'posted_at',t.reconciled_at,
      'transaction_id',case when a.contributor_user_id=actor
        then coalesce(t.bank_transaction_id,t.end_to_end_id) end,
      'is_current_user_contribution',a.contributor_user_id=actor,
      'supporter_label',case when a.contributor_user_id=actor then 'You' else 'Collect member' end
    )
    from public.bank_transactions t
    join public.bank_transaction_allocations a on a.bank_transaction_id=t.id
    where t.status='reconciled' and (a.contributor_user_id=actor
      or a.collection_id in (select id from readable))
  )
  select coalesce(jsonb_agg(item order by happened_at desc,item->>'payment_id'),'[]'::jsonb)
  into result from history;
  return result;
end;
$$;
revoke all on function collect_member_actions.payment_history() from public,anon,authenticated;
grant execute on function collect_member_actions.payment_history() to authenticated;

create or replace function public.list_current_member_payment_history()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select collect_member_actions.payment_history(); $$;
revoke all on function public.list_current_member_payment_history() from public,anon,authenticated;
grant execute on function public.list_current_member_payment_history() to authenticated;

commit;
