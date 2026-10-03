alter table collections
  add column if not exists accent_color_hex text,
  add column if not exists recurring_cadence text not null default 'monthly'
    check (recurring_cadence in ('daily', 'weekly', 'monthly'));

update collections
set recurring_cadence = coalesce(
  nullif(trim(recurring_rule->>'cadence'), ''),
  recurring_cadence,
  'monthly'
)
where recurring_rule ? 'cadence';

grant select (accent_color_hex, recurring_cadence)
  on collections to anon, authenticated;

drop function if exists ensure_current_profile(text);

create or replace function ensure_current_profile(p_whatsapp_phone text default null)
returns profiles
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  profile_row profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into profile_row
  from profiles
  where id = auth.uid();

  if profile_row.id is null then
    insert into profiles (id, public_id, whatsapp_phone)
    values (
      auth.uid(),
      generate_public_id(),
      nullif(trim(p_whatsapp_phone), '')
    )
    returning * into profile_row;
  elsif nullif(trim(p_whatsapp_phone), '') is not null
    and coalesce(profile_row.whatsapp_phone, '') = '' then
    update profiles
    set whatsapp_phone = trim(p_whatsapp_phone)
    where id = auth.uid()
    returning * into profile_row;
  end if;

  return profile_row;
end;
$$;

revoke execute on function ensure_current_profile(text)
  from public, anon, authenticated;
grant execute on function ensure_current_profile(text) to authenticated;

create or replace function update_collection_profile(
  collection uuid,
  group_name text,
  group_description text,
  group_image_url text default null,
  group_accent_color_hex text default null,
  group_is_public boolean default false,
  group_recurring_cadence text default 'monthly'
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  clean_cadence text := coalesce(
    nullif(trim(group_recurring_cadence), ''),
    'monthly'
  );
  next_public_status collection_visibility := case
    when coalesce(group_is_public, false) then 'public_requested'::collection_visibility
    else 'private'::collection_visibility
  end;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not user_is_collection_admin(collection, auth.uid()) then
    raise exception 'Only collection admins can update the group profile';
  end if;
  if nullif(trim(group_name), '') is null then
    raise exception 'Group name is required';
  end if;
  if clean_cadence not in ('daily', 'weekly', 'monthly') then
    raise exception 'Unsupported recurring cadence';
  end if;

  update collections
  set
    title = trim(group_name),
    description = trim(coalesce(group_description, '')),
    cover_image_url = nullif(trim(group_image_url), ''),
    accent_color_hex = nullif(trim(group_accent_color_hex), ''),
    public_status = next_public_status,
    visibility = next_public_status,
    is_recurring = true,
    recurring_cadence = clean_cadence,
    recurring_rule = jsonb_build_object('cadence', clean_cadence),
    updated_at = now()
  where id = collection;

  if not found then
    raise exception 'Group not found';
  end if;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'collection.profile_updated',
    'collection',
    collection,
    jsonb_build_object(
      'is_public', coalesce(group_is_public, false),
      'public_status', next_public_status::text,
      'recurring_cadence', clean_cadence
    )
  );
end;
$$;

revoke execute on function update_collection_profile(uuid, text, text, text, text, boolean, text)
  from public, anon, authenticated;
grant execute on function update_collection_profile(uuid, text, text, text, text, boolean, text)
  to authenticated;

create or replace view member_collections_view
with (security_invoker = true)
as
select
  c.id,
  c.slug,
  c.creator_user_id,
  c.title,
  c.description,
  c.currency,
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
  c.archived_at,
  c.accent_color_hex,
  c.recurring_cadence
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

alter view public.member_collections_view set (security_invoker = true);
grant select on member_collections_view to authenticated;
