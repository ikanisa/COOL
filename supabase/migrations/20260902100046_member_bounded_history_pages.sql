begin;

-- Only sanitized, actor-authorized rows enter this non-exposed helper.
-- Its public invoker wrapper requires authentication. A revision-bound anchor prevents skipped or
-- duplicated rows when posting, privacy choices or permissions change.
create or replace function collect_member_actions.history_page(
  p_collection_id uuid, p_query text, p_sort text, p_cursor jsonb, p_limit integer
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  result jsonb;
  query_text text := lower(btrim(coalesce(p_query,'')));
begin
  if actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_limit is null or p_limit not between 1 and 100 or length(query_text)>80
     or p_sort is null or p_sort not in ('newest','oldest','highest','lowest') then
    raise exception 'Invalid history query' using errcode = '22023';
  end if;
  if p_cursor is not null and (jsonb_typeof(p_cursor)<>'object'
      or coalesce(p_cursor->>'revision','') !~ '^[a-f0-9]{32}$'
      or length(coalesce(p_cursor->>'after','')) not between 1 and 100) then
    raise exception 'Invalid history cursor' using errcode = '22023';
  end if;

  with history as materialized (
    select e.item from jsonb_array_elements(collect_member_actions.payment_history()) e(item)
    where (p_collection_id is null or e.item->>'collection_id'=p_collection_id::text)
      and (query_text='' or strpos(lower(coalesce(e.item->>'supporter_label','')),query_text)>0
        or strpos(lower(coalesce(e.item->>'transaction_id','')),query_text)>0
        or exists(select 1 from public.collections c
          where c.id=(e.item->>'collection_id')::uuid
            and public.user_can_read_collection(c.id,actor)
            and strpos(lower(c.title),query_text)>0))
  ), ranked as materialized (
    select item,row_number() over(order by
      case when p_sort in ('highest','lowest') then item->>'currency' end,
      case when p_sort='highest' then (item->>'amount_minor')::bigint end desc,
      case when p_sort='lowest' then (item->>'amount_minor')::bigint end,
      case when p_sort='oldest' then (item->>'posted_at')::timestamptz end,
      case when p_sort<>'oldest' then (item->>'posted_at')::timestamptz end desc,
      item->>'payment_id') as position
    from history
  ), revision as (
    select md5(concat(actor,':',p_collection_id,':',query_text,':',p_sort,':',
      coalesce(string_agg(md5(item::text),'' order by item->>'payment_id'),''))) as value
    from history
  ), anchor as (
    select case when p_cursor is null then 0::bigint
      else (select position from ranked where item->>'payment_id'=p_cursor->>'after') end as position
  ), page as materialized (
    select r.item,r.position from ranked r cross join anchor a
    where r.position>a.position order by r.position limit p_limit
  ), amounts as (
    select item->>'currency' as currency,sum((item->>'amount_minor')::bigint) as total,
      coalesce(sum((item->>'amount_minor')::bigint)
        filter(where (item->>'is_current_user_contribution')::boolean),0) as own
    from history group by item->>'currency'
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(item order by position) from page),'[]'::jsonb),
    'total_count',(select count(*) from history),
    'totals',coalesce((select jsonb_object_agg(currency,total) from amounts),'{}'::jsonb),
    'own_totals',coalesce((select jsonb_object_agg(currency,own) from amounts),'{}'::jsonb),
    'own_collection_ids',coalesce((select jsonb_agg(id order by id) from
      (select distinct item->>'collection_id' as id from history
       where (item->>'is_current_user_contribution')::boolean) ids),'[]'::jsonb),
    'revision',v.value,
    'next_cursor',case when (select max(position) from page)<(select count(*) from history)
      then jsonb_build_object('revision',v.value,'after',
        (select item->>'payment_id' from page order by position desc limit 1)) end,
    '_valid',p_cursor is null or (v.value=p_cursor->>'revision' and a.position is not null)
  ) into result from revision v cross join anchor a;
  if not (result->>'_valid')::boolean then
    raise exception 'History changed. Refresh before loading more.' using errcode='P0001';
  end if;
  return result-'_valid';
end;
$$;
revoke all on function collect_member_actions.history_page(uuid,text,text,jsonb,integer) from public,anon,authenticated;
grant execute on function collect_member_actions.history_page(uuid,text,text,jsonb,integer) to authenticated;

create or replace function public.list_current_member_history_page(
  p_collection_id uuid default null, p_query text default '', p_sort text default 'newest',
  p_cursor jsonb default null, p_limit integer default 50
) returns jsonb language sql stable security invoker set search_path = ''
as $$ select collect_member_actions.history_page(p_collection_id,p_query,p_sort,p_cursor,p_limit); $$;
revoke all on function public.list_current_member_history_page(uuid,text,text,jsonb,integer) from public,anon,authenticated;
grant execute on function public.list_current_member_history_page(uuid,text,text,jsonb,integer) to authenticated;

-- The app needs recent intents for resumption, not every historical attempt.
-- A separate exact-ID read keeps old notification/deep links resolvable.
create or replace function collect_member_actions.recent_intents(p_intent_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode='28000';
  end if;
  with intents as materialized (
    select item,ordinality from jsonb_array_elements(public.list_current_member_payment_intents())
      with ordinality e(item,ordinality)
  ), selected as (
    select item,ordinality from intents
    where p_intent_id is null or item->>'id'=p_intent_id::text
    order by ordinality limit 50
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(item order by ordinality) from selected),'[]'::jsonb),
    'pending_count',(select count(*) from intents where item->>'status' in
      ('pending','awaiting_transfer','handoff_opened','awaiting_bank_evidence'))
  ) into result;
  return result;
end;
$$;
revoke all on function collect_member_actions.recent_intents(uuid) from public,anon,authenticated;
grant execute on function collect_member_actions.recent_intents(uuid) to authenticated;
create or replace function public.list_current_member_recent_intents(p_intent_id uuid default null)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select collect_member_actions.recent_intents(p_intent_id); $$;
revoke all on function public.list_current_member_recent_intents(uuid) from public,anon,authenticated;
grant execute on function public.list_current_member_recent_intents(uuid) to authenticated;

commit;
