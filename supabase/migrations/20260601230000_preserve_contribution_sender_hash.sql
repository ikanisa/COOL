-- Preserve the contributor MoMo hash on payment intents created from the
-- mobile contribution flow. The Flutter client passes p_sender_phone_hash
-- after profile MoMo setup, and allocation/audit paths should keep that
-- contributor-side fingerprint when available.

create or replace function create_contribution_intent(
  collection uuid,
  p_expected_amount_rwf bigint default null,
  p_sender_phone_hash text default null
)
returns table (
  id uuid,
  collection_id uuid,
  expected_amount_rwf bigint,
  receiver_momo_number text,
  receiver_momo_number_hash text,
  receiver_label text,
  network text,
  sender_phone_hash text,
  status payment_intent_status,
  contributor_public_id char(6),
  created_at timestamptz,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  receiver_row collection_receivers;
  intent_row payment_intents;
  member_public_id char(6);
begin
  if not public.user_can_read_collection(collection, auth.uid()) then
    raise exception 'Group is not available';
  end if;

  if p_expected_amount_rwf is null or p_expected_amount_rwf <= 0 then
    raise exception 'Contribution amount must be above zero';
  end if;

  select p.public_id into member_public_id
  from profiles p
  where p.id = auth.uid();

  if member_public_id is null then
    raise exception 'Collect ID is required before contributing';
  end if;

  select *
    into receiver_row
  from collection_receivers cr
  where cr.collection_id = collection and cr.is_active
  order by cr.created_at
  limit 1;

  if receiver_row.id is null then
    raise exception 'Group has no active receiver';
  end if;

  insert into payment_intents (
    collection_id,
    contributor_user_id,
    contributor_public_id,
    expected_amount_rwf,
    receiver_momo_number_hash,
    sender_phone_hash
  )
  values (
    collection,
    auth.uid(),
    member_public_id,
    p_expected_amount_rwf,
    receiver_row.momo_number_hash,
    nullif(trim(p_sender_phone_hash), '')
  )
  returning * into intent_row;

  return query select
    intent_row.id,
    intent_row.collection_id,
    intent_row.expected_amount_rwf,
    receiver_row.momo_number,
    intent_row.receiver_momo_number_hash,
    receiver_row.label,
    receiver_row.network,
    intent_row.sender_phone_hash,
    intent_row.status,
    intent_row.contributor_public_id,
    intent_row.created_at,
    intent_row.expires_at;
end;
$$;

revoke execute on function create_contribution_intent(uuid, bigint, text)
  from public, anon;
grant execute on function create_contribution_intent(uuid, bigint, text)
  to authenticated;
