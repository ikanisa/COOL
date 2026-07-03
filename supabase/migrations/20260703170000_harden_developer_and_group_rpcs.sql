create or replace function ensure_developer_account_data()
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  allowed_phone constant text := '+250788767816';
  allowed_digits constant text := '250788767816';
  developer_momo constant text := '0788767816';
  current_digits text;
  profile_row profiles%rowtype;
  collection_church constant uuid := '8db1f114-4f2b-4a6a-aec9-a0e33a1f1001'::uuid;
  collection_ikimina constant uuid := '8db1f114-4f2b-4a6a-aec9-a0e33a1f1002'::uuid;
  payment_one constant uuid := '8db1f114-4f2b-4a6a-aec9-a0e33a1f2001'::uuid;
  payment_two constant uuid := '8db1f114-4f2b-4a6a-aec9-a0e33a1f2002'::uuid;
  ledger_one constant uuid := '8db1f114-4f2b-4a6a-aec9-a0e33a1f3001'::uuid;
  ledger_two constant uuid := '8db1f114-4f2b-4a6a-aec9-a0e33a1f3002'::uuid;
  receiver_hash text := encode(digest(allowed_phone, 'sha256'), 'hex');
begin
  if auth.uid() is null then
    return false;
  end if;

  select regexp_replace(
    coalesce(u.phone, p.whatsapp_phone, auth.jwt() ->> 'phone', ''),
    '[^0-9]',
    '',
    'g'
  )
  into current_digits
  from auth.users u
  left join profiles p on p.id = u.id
  where u.id = auth.uid();

  if left(coalesce(current_digits, ''), 2) = '00' then
    current_digits := substring(current_digits from 3);
  end if;

  if current_digits <> allowed_digits then
    return false;
  end if;

  if exists (
    select 1
    from profiles
    where whatsapp_phone = allowed_phone
      and id <> auth.uid()
  ) then
    raise exception 'Developer WhatsApp number belongs to another profile';
  end if;

  insert into profiles (
    id,
    public_id,
    whatsapp_phone,
    display_name,
    momo_number,
    momo_number_hash
  )
  values (
    auth.uid(),
    generate_public_id(),
    allowed_phone,
    'Collect developer',
    developer_momo,
    receiver_hash
  )
  on conflict (id) do update
  set
    whatsapp_phone = allowed_phone,
    display_name = coalesce(nullif(profiles.display_name, ''), 'Collect developer'),
    momo_number = coalesce(nullif(profiles.momo_number, ''), developer_momo),
    momo_number_hash = coalesce(nullif(profiles.momo_number_hash, ''), receiver_hash),
    updated_at = now()
  returning * into profile_row;

  insert into collections (
    id,
    slug,
    creator_user_id,
    title,
    description,
    category,
    receiver_display_label,
    public_status,
    visibility,
    is_recurring,
    recurring_rule,
    collection_type,
    category_subtype,
    purpose_label,
    moderation_status,
    created_at
  )
  values
    (
      collection_church,
      'developer-parish-support',
      profile_row.id,
      'Developer parish support',
      'Developer-owned Supabase seed for validating Collect group balances.',
      'Church',
      'Developer MoMo receiver',
      'public_approved',
      'public_approved',
      true,
      jsonb_build_object('cadence', 'monthly'),
      'church',
      'offering',
      'Parish support',
      'approved',
      now() - interval '3 days'
    ),
    (
      collection_ikimina,
      'developer-ikimina-savings',
      profile_row.id,
      'Developer ikimina savings',
      'Developer-owned Supabase seed for validating private group activity.',
      'Family / friends',
      'Developer MoMo receiver',
      'private',
      'private',
      true,
      jsonb_build_object('cadence', 'monthly'),
      'ikimina',
      'group_savings',
      'Savings cycle',
      'not_requested',
      now() - interval '1 day'
    )
  on conflict (id) do update
  set
    creator_user_id = excluded.creator_user_id,
    title = excluded.title,
    description = excluded.description,
    receiver_display_label = excluded.receiver_display_label,
    public_status = excluded.public_status,
    visibility = excluded.visibility,
    is_recurring = excluded.is_recurring,
    recurring_rule = excluded.recurring_rule,
    collection_type = excluded.collection_type,
    category_subtype = excluded.category_subtype,
    purpose_label = excluded.purpose_label,
    moderation_status = excluded.moderation_status,
    updated_at = now();

  insert into collection_members (collection_id, user_id, role, status)
  values
    (collection_church, profile_row.id, 'owner', 'active'),
    (collection_ikimina, profile_row.id, 'owner', 'active')
  on conflict (collection_id, user_id, role) do update
  set status = 'active';

  update collection_receivers
  set is_active = false
  where collection_id in (collection_church, collection_ikimina)
    and receiver_user_id = profile_row.id
    and momo_number <> developer_momo;

  insert into collection_receivers (
    collection_id,
    receiver_user_id,
    momo_number,
    momo_number_hash,
    network,
    label,
    is_active
  )
  select seed.collection_id, profile_row.id, developer_momo, receiver_hash,
    'mtn_momo', 'Developer MoMo receiver', true
  from (values (collection_church), (collection_ikimina)) as seed(collection_id)
  where not exists (
    select 1
    from collection_receivers cr
    where cr.collection_id = seed.collection_id
      and cr.receiver_user_id = profile_row.id
      and cr.momo_number = developer_momo
      and cr.is_active
  );

  insert into payments (
    id,
    collection_id,
    contributor_user_id,
    contributor_public_id,
    receiver_user_id,
    receiver_momo_number_hash,
    amount_rwf,
    transaction_id,
    source,
    status,
    anonymity_choice,
    posted_at,
    created_at
  )
  values
    (
      payment_one,
      collection_church,
      profile_row.id,
      profile_row.public_id,
      profile_row.id,
      receiver_hash,
      25000,
      'DEV-MOMO-0001',
      'import',
      'posted',
      'public_id',
      now() - interval '5 hours',
      now() - interval '5 hours'
    ),
    (
      payment_two,
      collection_church,
      profile_row.id,
      profile_row.public_id,
      profile_row.id,
      receiver_hash,
      10000,
      'DEV-MOMO-0002',
      'import',
      'posted',
      'public_id',
      now() - interval '2 hours',
      now() - interval '2 hours'
    )
  on conflict (id) do update
  set
    collection_id = excluded.collection_id,
    contributor_user_id = excluded.contributor_user_id,
    contributor_public_id = excluded.contributor_public_id,
    receiver_user_id = excluded.receiver_user_id,
    receiver_momo_number_hash = excluded.receiver_momo_number_hash,
    amount_rwf = excluded.amount_rwf,
    transaction_id = excluded.transaction_id,
    source = excluded.source,
    status = excluded.status,
    anonymity_choice = excluded.anonymity_choice;

  insert into ledger_entries (
    id,
    payment_id,
    collection_id,
    user_id,
    entry_type,
    amount_rwf,
    visibility,
    metadata,
    created_at
  )
  values
    (
      ledger_one,
      payment_one,
      collection_church,
      profile_row.id,
      'collection_credit',
      25000,
      'public_safe',
      jsonb_build_object('seed_owner', allowed_phone),
      now() - interval '5 hours'
    ),
    (
      ledger_two,
      payment_two,
      collection_church,
      profile_row.id,
      'collection_credit',
      10000,
      'public_safe',
      jsonb_build_object('seed_owner', allowed_phone),
      now() - interval '2 hours'
    )
  on conflict (id) do nothing;

  return true;
end;
$$;

revoke execute on function ensure_developer_account_data()
  from public, anon, authenticated;
grant execute on function ensure_developer_account_data() to authenticated;

create or replace function archive_group(collection uuid)
returns void
language plpgsql
security invoker
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update collections
  set
    visibility = 'archived'::collection_visibility,
    public_status = 'archived'::collection_visibility,
    archived_at = now()
  where id = collection
    and creator_user_id = auth.uid();

  if not found then
    raise exception 'Only the group owner can archive this group';
  end if;
end;
$$;

create or replace function transfer_group_ownership(
  collection uuid,
  new_owner_public_id text
)
returns void
language plpgsql
security invoker
set search_path = public, auth
as $$
declare
  current_owner uuid := auth.uid();
  new_owner uuid;
begin
  if current_owner is null then
    raise exception 'Authentication required';
  end if;

  select id
  into new_owner
  from profiles
  where public_id = regexp_replace(coalesce(new_owner_public_id, ''), '\D', '', 'g')
  limit 1;

  if new_owner is null then
    raise exception 'Collect ID not found';
  end if;

  update collections
  set creator_user_id = new_owner
  where id = collection
    and creator_user_id = current_owner;

  if not found then
    raise exception 'Only the group owner can transfer ownership';
  end if;

  insert into collection_members (collection_id, user_id, role, status)
  values (collection, new_owner, 'owner'::member_role, 'active'::member_status)
  on conflict (collection_id, user_id, role)
  do update set status = 'active'::member_status;

  if new_owner <> current_owner then
    delete from collection_members
    where collection_id = collection
      and user_id = current_owner
      and role = 'owner'::member_role;

    insert into collection_members (collection_id, user_id, role, status)
    values (
      collection,
      current_owner,
      'admin'::member_role,
      'active'::member_status
    )
    on conflict (collection_id, user_id, role)
    do update set status = 'active'::member_status;
  end if;
end;
$$;

revoke execute on function archive_group(uuid) from public, anon, authenticated;
grant execute on function archive_group(uuid) to authenticated;

revoke execute on function transfer_group_ownership(uuid, text)
from public, anon, authenticated;
grant execute on function transfer_group_ownership(uuid, text) to authenticated;
