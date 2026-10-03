begin;

-- FQA-025: public directory visibility must not expose the member roster.
-- Preserve feature-phone membership, amount privacy, wrappers and grants.

create or replace function collect_member_actions.group_roster(
  p_collection_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  group_row public.collections%rowtype;
  result jsonb;
begin
  if actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select * into group_row
  from public.collections where id = p_collection_id;
  -- Directory visibility and platform authority do not confer membership.
  -- Retain verified linked/claimed feature-phone membership through the
  -- existing lifecycle-aware ownership predicate.
  if group_row.id is null or not (
    group_row.creator_user_id = actor or exists (
      select 1 from public.collection_members membership
      where membership.collection_id = p_collection_id
        and membership.status = 'active'
        and (
          membership.user_id = actor
          or collect_hybrid.member_record_belongs_to_user(
            membership.member_record_id, actor
          )
        )
    )
  ) then
    raise exception 'Join this group to view members' using errcode = '42501';
  end if;

  with candidates as (
    select
      coalesce(
        membership.member_record_id::text,
        'user:' || membership.user_id::text
      ) as identity_key,
      membership.member_record_id,
      coalesce(
        membership.user_id, member.linked_user_id, claim.user_id
      ) as account_user_id,
      coalesce(member.collect_id::text, profile.public_id::text) as public_id,
      case when coalesce(
          membership.user_id, member.linked_user_id, claim.user_id
        ) = group_row.creator_user_id then 'owner'
        when membership.role = 'owner' then 'admin'
        else membership.role::text end as role,
      membership.status::text as status,
      membership.created_at as joined_at
    from public.collection_members membership
    left join collect_hybrid.member_records member
      on member.id = membership.member_record_id
    left join collect_hybrid.member_account_claims claim
      on claim.member_record_id = member.id and claim.user_id is not null
    left join public.profiles profile
      on profile.id = coalesce(
        membership.user_id, member.linked_user_id, claim.user_id
      )
    where membership.collection_id = p_collection_id
    union all
    select
      coalesce(member.id::text, 'user:' || group_row.creator_user_id::text),
      member.id,
      group_row.creator_user_id,
      coalesce(member.collect_id::text, profile.public_id::text),
      'owner', 'active', group_row.created_at
    from public.profiles profile
    left join collect_hybrid.member_records member
      on member.linked_user_id = profile.id
    where profile.id = group_row.creator_user_id
      and not exists (
        select 1 from public.collection_members membership
        where membership.collection_id = p_collection_id
          and membership.user_id = group_row.creator_user_id
      )
  ), ranked as (
    select *,
      min(joined_at) over (partition by identity_key) as first_joined_at,
      row_number() over (
        partition by identity_key
        order by
          case status when 'active' then 0 when 'invited' then 1 else 2 end,
          case role when 'owner' then 0 when 'admin' then 1
            when 'receiver' then 2 when 'member' then 3
            when 'contributor' then 4 else 5 end,
          joined_at, status
      ) as priority
    from candidates
    where public_id is not null
  ), roster as (
    select identity_key, member_record_id, account_user_id, public_id,
      role, status, first_joined_at as joined_at
    from ranked where priority = 1
  ), visible_amounts as (
    select roster.identity_key, payment.currency,
      payment.amount_rwf as amount_minor
    from public.payments payment
    join roster on (
      payment.member_record_id = roster.member_record_id
      or (
        payment.member_record_id is null
        and payment.contributor_user_id = roster.account_user_id
      )
    )
    where payment.collection_id = p_collection_id
      and payment.status = 'posted'
      and (
        roster.account_user_id = actor
        or (
          payment.anonymity_choice = 'public_id'
          and payment.contributor_public_id::text = roster.public_id
        )
      )
    union all
    select roster.identity_key, transaction.currency,
      transaction.amount_minor
    from public.bank_transactions transaction
    join public.bank_transaction_allocations allocation
      on allocation.bank_transaction_id = transaction.id
    join roster on roster.account_user_id = allocation.contributor_user_id
    where allocation.collection_id = p_collection_id
      and transaction.status = 'reconciled'
      and roster.account_user_id = actor
  ), totals as (
    select identity_key, currency, sum(amount_minor)::bigint as amount_minor
    from visible_amounts group by identity_key, currency
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'public_id', roster.public_id,
    'role', roster.role,
    'status', roster.status,
    'joined_at', roster.joined_at,
    'account_state', case when roster.account_user_id is null
      then 'feature_phone' else 'app' end,
    'amount_scope', case when roster.account_user_id = actor then 'own'
      when exists (
        select 1 from totals
        where totals.identity_key = roster.identity_key
      ) then 'shared' else 'hidden' end,
    'contributions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'currency', totals.currency,
        'amount_minor', totals.amount_minor
      ) order by totals.currency)
      from totals where totals.identity_key = roster.identity_key
    ), '[]'::jsonb)
  ) order by roster.public_id), '[]'::jsonb)
  into result from roster;
  return result;
end;
$$;

commit;
