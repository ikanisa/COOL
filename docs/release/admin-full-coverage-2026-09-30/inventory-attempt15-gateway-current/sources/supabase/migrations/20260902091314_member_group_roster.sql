begin;

-- Member rosters are not public-directory data. One row per account, with
-- authoritative roles and only contribution amounts already visible to it.
create or replace function collect_member_actions.group_roster(p_collection_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  group_row public.collections%rowtype;
  result jsonb;
begin
  if actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select * into group_row from public.collections where id = p_collection_id;
  if group_row.id is null or not (
    group_row.creator_user_id = actor or exists (
      select 1 from public.collection_members m
      where m.collection_id = p_collection_id and m.user_id = actor and m.status = 'active'
    )
  ) then
    raise exception 'Join this group to view members' using errcode = '42501';
  end if;

  with candidates as (
    select m.user_id,
      case when m.user_id = group_row.creator_user_id then 'owner'
        when m.role = 'owner' then 'admin' else m.role::text end as role,
      case when m.user_id = group_row.creator_user_id then 'active' else m.status::text end as status,
      m.created_at as joined_at
    from public.collection_members m
    where m.collection_id = p_collection_id and m.user_id is not null
    union all
    select group_row.creator_user_id, 'owner', 'active', group_row.created_at
    where not exists(select 1 from public.collection_members m
      where m.collection_id = p_collection_id and m.user_id = group_row.creator_user_id)
  ), ranked as (
    select *, min(joined_at) over (partition by user_id) as first_joined_at,
      row_number() over (partition by user_id order by
      case status when 'active' then 0 when 'invited' then 1 else 2 end,
      case role when 'owner' then 0 when 'admin' then 1 when 'receiver' then 2
        when 'member' then 3 when 'contributor' then 4 else 5 end,
      joined_at, status) as priority
    from candidates
  ), roster as (
    select r.user_id, p.public_id, r.role, r.status, r.first_joined_at as joined_at
    from ranked r join public.profiles p on p.id = r.user_id where r.priority = 1
  ), visible_amounts as (
    select p.contributor_user_id as user_id, p.currency, p.amount_rwf as amount_minor
    from public.payments p join roster r on r.user_id = p.contributor_user_id
    where p.collection_id = p_collection_id and p.status = 'posted'
      and (p.contributor_user_id = actor or (
        p.anonymity_choice = 'public_id' and p.contributor_public_id::text = r.public_id::text
      ))
    union all
    select a.contributor_user_id, t.currency, t.amount_minor
    from public.bank_transactions t
    join public.bank_transaction_allocations a on a.bank_transaction_id = t.id
    where a.collection_id = p_collection_id and t.status = 'reconciled'
      and a.contributor_user_id = actor
  ), totals as (
    select user_id, currency, sum(amount_minor)::bigint as amount_minor
    from visible_amounts group by user_id, currency
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'public_id', r.public_id::text, 'role', r.role, 'status', r.status, 'joined_at', r.joined_at,
    'amount_scope', case when r.user_id = actor then 'own'
      when exists(select 1 from totals t where t.user_id = r.user_id) then 'shared' else 'hidden' end,
    'contributions', coalesce((select jsonb_agg(jsonb_build_object(
      'currency',t.currency,'amount_minor',t.amount_minor) order by t.currency)
      from totals t where t.user_id = r.user_id),'[]'::jsonb)
  ) order by r.public_id), '[]'::jsonb) into result from roster r;
  return result;
end;
$$;
revoke all on function collect_member_actions.group_roster(uuid) from public,anon,authenticated;
grant execute on function collect_member_actions.group_roster(uuid) to authenticated;

create or replace function public.list_current_member_group_roster(p_collection_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select collect_member_actions.group_roster(p_collection_id); $$;
revoke all on function public.list_current_member_group_roster(uuid) from public,anon,authenticated;
grant execute on function public.list_current_member_group_roster(uuid) to authenticated;

-- Preserve installed-client signature while fixing duplicates and access.
create or replace function public.list_collection_collect_ids(collection uuid)
returns table(public_id text,role text,status text,joined_at timestamptz)
language sql stable security invoker set search_path = ''
as $$
  select r.public_id,r.role,r.status,r.joined_at
  from jsonb_to_recordset(collect_member_actions.group_roster(collection))
    as r(public_id text,role text,status text,joined_at timestamptz);
$$;
revoke all on function public.list_collection_collect_ids(uuid) from public,anon,authenticated;
grant execute on function public.list_collection_collect_ids(uuid) to authenticated;

commit;
