do $$ begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'rs_tickets') then
    alter table public.rs_tickets add column if not exists referral_invite_id uuid references public.referral_invites(id) on delete set null;
    create index if not exists idx_rs_tickets_referral_invite on public.rs_tickets (referral_invite_id) where referral_invite_id is not null;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'rs_shop_orders') then
    alter table public.rs_shop_orders add column if not exists referral_invite_id uuid references public.referral_invites(id) on delete set null;
    create index if not exists idx_rs_shop_orders_referral_invite on public.rs_shop_orders (referral_invite_id) where referral_invite_id is not null;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'rs_initiative_contributions') then
    alter table public.rs_initiative_contributions add column if not exists referral_invite_id uuid references public.referral_invites(id) on delete set null;
    create index if not exists idx_rs_initiative_contributions_referral_invite on public.rs_initiative_contributions (referral_invite_id) where referral_invite_id is not null;
  end if;
end $$;

create or replace function public.activate_referral_invite_for_user(
  p_referral_invite_id uuid,
  p_invitee_id uuid,
  p_qualifying_event_type text,
  p_qualifying_event_id text default null,
  p_inviter_points int default 150,
  p_invitee_points int default 50
)
returns public.referral_conversions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.referral_invites;
  v_conversion public.referral_conversions;
  v_dedupe_key text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Service role is required.';
  end if;

  if p_invitee_id is null then
    raise exception 'Invitee is required.';
  end if;

  select *
  into v_invite
  from public.referral_invites
  where id = p_referral_invite_id;

  if not found then
    raise exception 'Referral invite not found.';
  end if;

  if v_invite.inviter_id = p_invitee_id then
    raise exception 'Inviter cannot activate their own invite.';
  end if;

  v_dedupe_key := 'referral:' || p_referral_invite_id::text || ':' || p_invitee_id::text;

  insert into public.referral_conversions (
    referral_invite_id,
    inviter_id,
    invitee_id,
    qualifying_event_type,
    qualifying_event_id,
    dedupe_key
  )
  values (
    p_referral_invite_id,
    v_invite.inviter_id,
    p_invitee_id,
    p_qualifying_event_type,
    p_qualifying_event_id,
    v_dedupe_key
  )
  on conflict (referral_invite_id, invitee_id) do update
    set
      qualifying_event_type = excluded.qualifying_event_type,
      qualifying_event_id = excluded.qualifying_event_id,
      updated_at = now()
  returning *
  into v_conversion;

  if v_conversion.status <> 'rewarded' then
    perform public.apply_cool_event_internal(
      v_invite.inviter_id,
      'inviteQualified',
      greatest(coalesce(p_inviter_points, 0), 0),
      p_qualifying_event_id,
      jsonb_build_object(
        'referral_invite_id', p_referral_invite_id,
        'invitee_id', p_invitee_id,
        'qualifying_event_type', p_qualifying_event_type
      ),
      p_invitee_id,
      'inviteQualified:inviter:' || p_referral_invite_id::text || ':' || p_invitee_id::text,
      v_invite.campaign_id,
      null
    );

    perform public.apply_cool_event_internal(
      p_invitee_id,
      'inviteQualified',
      greatest(coalesce(p_invitee_points, 0), 0),
      p_qualifying_event_id,
      jsonb_build_object(
        'referral_invite_id', p_referral_invite_id,
        'inviter_id', v_invite.inviter_id,
        'qualifying_event_type', p_qualifying_event_type
      ),
      v_invite.inviter_id,
      'inviteQualified:invitee:' || p_referral_invite_id::text || ':' || p_invitee_id::text,
      v_invite.campaign_id,
      null
    );

    update public.referral_conversions
    set
      inviter_points = greatest(coalesce(p_inviter_points, 0), 0),
      invitee_points = greatest(coalesce(p_invitee_points, 0), 0),
      status = 'rewarded',
      updated_at = now()
    where id = v_conversion.id
    returning *
    into v_conversion;
  end if;

  update public.referral_invites
  set
    status = 'activated',
    opened_by_user_id = coalesce(opened_by_user_id, p_invitee_id),
    activated_by_user_id = coalesce(activated_by_user_id, p_invitee_id),
    opened_at = coalesce(opened_at, now()),
    activated_at = coalesce(activated_at, now()),
    updated_at = now()
  where id = p_referral_invite_id;

  return v_conversion;
end;
$$;
revoke all on function public.activate_referral_invite_for_user(
  uuid,
  uuid,
  text,
  text,
  int,
  int
) from public, anon, authenticated;
grant execute on function public.activate_referral_invite_for_user(
  uuid,
  uuid,
  text,
  text,
  int,
  int
) to service_role;
