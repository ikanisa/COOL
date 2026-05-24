set search_path = public;

create or replace view member_collections_view
as
select
  c.id,
  c.slug,
  c.creator_user_id,
  c.title,
  c.description,
  c.category,
  c.cover_image_url,
  c.currency,
  c.target_amount_rwf,
  c.deadline_at,
  c.visibility,
  c.public_status,
  c.is_recurring,
  c.recurring_rule,
  c.allow_anonymous,
  c.contribution_visibility,
  case
    when public.user_is_collection_admin(c.id, auth.uid())
      or exists (
        select 1
        from collection_receivers receiver_check
        where receiver_check.collection_id = c.id
          and receiver_check.receiver_user_id = auth.uid()
          and receiver_check.is_active
      )
      then cr.momo_number
    else null
  end as receiver_momo_number,
  case
    when public.user_can_read_collection(c.id, auth.uid()) then cr.label
    else null
  end as receiver_display_label,
  cr.network as receiver_network,
  c.created_at,
  c.updated_at,
  c.archived_at
from collections c
left join lateral (
  select
    collection_receivers.momo_number,
    collection_receivers.label,
    collection_receivers.network
  from collection_receivers
  where collection_receivers.collection_id = c.id
    and collection_receivers.is_active
  order by collection_receivers.created_at asc
  limit 1
) cr on true
where public.user_can_read_collection(c.id, auth.uid());

create or replace view member_contributions_view
as
select
  p.collection_id,
  p.id as payment_id,
  p.amount_rwf,
  p.currency,
  p.status,
  p.source,
  case
    when p.contributor_user_id = auth.uid()
      or public.user_is_collection_admin(p.collection_id, auth.uid())
      then p.transaction_id
    else null
  end as transaction_id,
  p.anonymity_choice,
  p.posted_at,
  p.created_at,
  case
    when p.contributor_user_id = auth.uid() then 'You'
    when p.anonymity_choice = 'display_name'
      and p.contributor_user_id is not null
      and public.user_is_collection_admin(p.collection_id, auth.uid())
      then coalesce(pr.display_name, 'User #' || pr.public_id)
    when p.anonymity_choice = 'public_id'
      and p.contributor_public_id is not null
      then 'User #' || p.contributor_public_id
    else 'Anonymous supporter'
  end as supporter_label
from payments p
left join profiles pr on pr.id = p.contributor_user_id
where p.status = 'posted'
  and (
    p.contributor_user_id = auth.uid()
    or public.user_is_collection_admin(p.collection_id, auth.uid())
    or exists (
      select 1
      from collections c
      where c.id = p.collection_id
        and c.public_status = 'public_approved'
    )
  );

create or replace view member_public_collection_requests_view
as
select
  pcr.id,
  pcr.collection_id,
  c.title as collection_title,
  pcr.requested_by,
  pcr.status,
  pcr.admin_user_id,
  pcr.admin_note,
  pcr.requested_at,
  pcr.reviewed_at
from public_collection_requests pcr
join collections c on c.id = pcr.collection_id
where pcr.requested_by = auth.uid()
  or public.current_user_is_platform_admin()
  or public.user_is_collection_admin(pcr.collection_id, auth.uid());

create or replace function record_receiver_mode_consent(
  enabled boolean,
  momo_number_hash text default null,
  build_channel text default 'internal_receiver',
  device_label text default 'flutter_app'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  consent_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  insert into receiver_mode_consents (
    user_id,
    enabled,
    momo_number_hash,
    build_channel,
    device_label
  )
  values (
    auth.uid(),
    coalesce(enabled, false),
    momo_number_hash,
    nullif(build_channel, ''),
    nullif(device_label, '')
  )
  returning id into consent_id;

  insert into audit_logs (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    auth.uid(),
    case
      when coalesce(enabled, false) then 'receiver_mode.enabled'
      else 'receiver_mode.disabled'
    end,
    'receiver_mode_consent',
    consent_id,
    jsonb_build_object('build_channel', build_channel, 'device_label', device_label)
  );

  return consent_id;
end;
$$;

revoke execute on function record_receiver_mode_consent(boolean, text, text, text) from public, anon;
grant select on member_collections_view to authenticated;
grant select on member_contributions_view to authenticated;
grant select on member_public_collection_requests_view to authenticated;
grant execute on function record_receiver_mode_consent(boolean, text, text, text) to authenticated;
