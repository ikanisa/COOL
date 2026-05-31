create table if not exists mobile_account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete restrict,
  reason text,
  status text not null default 'pending'
    check (status in ('pending', 'in_review', 'completed', 'rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references profiles(id) on delete set null
);

create table if not exists mobile_support_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete restrict,
  subject text not null,
  message text not null,
  status text not null default 'open'
    check (status in ('open', 'in_review', 'resolved', 'closed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references profiles(id) on delete set null
);

alter table mobile_account_deletion_requests enable row level security;
alter table mobile_support_requests enable row level security;

drop policy if exists "account deletion own read" on mobile_account_deletion_requests;
create policy "account deletion own read"
on mobile_account_deletion_requests
for select to authenticated
using (user_id = auth.uid() or is_platform_admin(auth.uid()));

drop policy if exists "support requests own read" on mobile_support_requests;
create policy "support requests own read"
on mobile_support_requests
for select to authenticated
using (user_id = auth.uid() or is_platform_admin(auth.uid()));

create index if not exists mobile_account_deletion_requests_user_idx
on mobile_account_deletion_requests (user_id, created_at desc);

create index if not exists mobile_support_requests_user_idx
on mobile_support_requests (user_id, created_at desc);

create or replace function request_account_deletion(request_reason text default null)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  request_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  insert into mobile_account_deletion_requests (user_id, reason)
  values (auth.uid(), nullif(trim(request_reason), ''))
  returning id into request_id;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'mobile.account_deletion_requested',
    'profile',
    auth.uid(),
    jsonb_build_object('request_id', request_id)
  );

  return request_id;
end;
$$;

create or replace function create_mobile_support_request(
  request_subject text,
  request_message text
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  request_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if nullif(trim(request_subject), '') is null then
    raise exception 'Support subject is required';
  end if;
  if nullif(trim(request_message), '') is null then
    raise exception 'Support message is required';
  end if;

  insert into mobile_support_requests (user_id, subject, message)
  values (auth.uid(), trim(request_subject), trim(request_message))
  returning id into request_id;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'mobile.support_requested',
    'profile',
    auth.uid(),
    jsonb_build_object('request_id', request_id)
  );

  return request_id;
end;
$$;

create or replace function list_collection_collect_ids(collection uuid)
returns table (
  public_id text,
  role text,
  status text,
  joined_at timestamptz
)
language sql
security definer
set search_path = public, extensions
as $$
  select
    p.public_id::text,
    cm.role::text,
    cm.status::text,
    cm.created_at as joined_at
  from collection_members cm
  join profiles p on p.id = cm.user_id
  where cm.collection_id = collection
    and user_can_read_collection(collection, auth.uid())
  order by cm.created_at asc;
$$;

create or replace function update_collection_receiver(
  collection uuid,
  receiver_momo_number text,
  receiver_momo_number_hash text,
  receiver_label text default 'Primary MOMO receiver'
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not user_is_collection_admin(collection, auth.uid()) then
    raise exception 'Only collection admins can update the receiver';
  end if;
  if nullif(trim(receiver_momo_number), '') is null then
    raise exception 'Receiver MoMo number is required';
  end if;
  if nullif(trim(receiver_momo_number_hash), '') is null then
    raise exception 'Receiver MoMo hash is required';
  end if;

  update collection_receivers
  set is_active = false
  where collection_id = collection
    and is_active = true;

  insert into collection_receivers (
    collection_id,
    receiver_user_id,
    momo_number,
    momo_number_hash,
    label,
    is_active
  )
  values (
    collection,
    auth.uid(),
    trim(receiver_momo_number),
    trim(receiver_momo_number_hash),
    coalesce(nullif(trim(receiver_label), ''), 'Primary MOMO receiver'),
    true
  );

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'collection.receiver_updated',
    'collection',
    collection,
    jsonb_build_object('receiver_label', coalesce(nullif(trim(receiver_label), ''), 'Primary MOMO receiver'))
  );
end;
$$;

create or replace function get_owner_group_health(collection uuid)
returns jsonb
language sql
security definer
set search_path = public, extensions
as $$
  select jsonb_build_object(
    'collection_id', collection,
    'receiver_configured', exists (
      select 1
      from collection_receivers cr
      where cr.collection_id = collection
        and cr.is_active
    ),
    'sms_access_enabled', exists (
      select 1
      from receiver_mode_consents rmc
      where rmc.user_id = auth.uid()
        and rmc.enabled
    ),
    'pending_payment_intents', (
      select count(*)
      from payment_intents pi
      where pi.collection_id = collection
        and pi.status = 'pending'
    ),
    'needs_review_events', (
      select count(*)
      from parsed_payment_events ppe
      where ppe.collection_id = collection
        and ppe.allocation_status in ('unallocated', 'ambiguous', 'needs_review')
    ),
    'last_synced_at', (
      select max(rps.created_at)
      from raw_payment_sms rps
      where rps.collection_id = collection
    )
  )
  where user_is_collection_admin(collection, auth.uid());
$$;

revoke execute on function request_account_deletion(text) from public, anon, authenticated;
revoke execute on function create_mobile_support_request(text, text) from public, anon, authenticated;
revoke execute on function list_collection_collect_ids(uuid) from public, anon, authenticated;
revoke execute on function update_collection_receiver(uuid, text, text, text) from public, anon, authenticated;
revoke execute on function get_owner_group_health(uuid) from public, anon, authenticated;

grant execute on function request_account_deletion(text) to authenticated;
grant execute on function create_mobile_support_request(text, text) to authenticated;
grant execute on function list_collection_collect_ids(uuid) to authenticated;
grant execute on function update_collection_receiver(uuid, text, text, text) to authenticated;
grant execute on function get_owner_group_health(uuid) to authenticated;
