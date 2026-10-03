begin;

-- These exact records were created for the June parity harness and must never
-- appear in the customer-facing group directory. Fail closed if any financial
-- or payment evidence has since been attached to them.
do $$
declare
  mock_collection_ids constant uuid[] := array[
    'bfb5d4d3-cb40-4bf1-ae89-579ea98073d5'::uuid,
    'd4bc46a2-dd50-4440-b950-dda5a13335d9'::uuid,
    '9208e94b-8b5a-4588-9dc2-0d4f8a34b7a5'::uuid,
    '747de065-e492-449c-b4e0-caa857ca413f'::uuid,
    'e30c018c-d19f-44f3-ada8-d7e666d45c55'::uuid
  ];
begin
  if exists (
    select 1 from public.payment_intents
    where collection_id = any(mock_collection_ids)
  ) or exists (
    select 1 from public.payments
    where collection_id = any(mock_collection_ids)
  ) or exists (
    select 1 from public.ledger_entries
    where collection_id = any(mock_collection_ids)
  ) or exists (
    select 1 from public.payment_allocations
    where collection_id = any(mock_collection_ids)
  ) or exists (
    select 1 from public.diaspora_contribution_intents
    where collection_id = any(mock_collection_ids)
  ) or exists (
    select 1 from public.parsed_payment_events
    where collection_id = any(mock_collection_ids)
  ) or exists (
    select 1 from public.raw_payment_sms
    where collection_id = any(mock_collection_ids)
  ) then
    raise exception
      'Legacy mock groups have payment evidence; manual review is required';
  end if;

  delete from public.collections
  where (id, slug) in (
    ('bfb5d4d3-cb40-4bf1-ae89-579ea98073d5'::uuid, 'mock-parity-private-member'),
    ('d4bc46a2-dd50-4440-b950-dda5a13335d9'::uuid, 'mock-parity-private-admin'),
    ('9208e94b-8b5a-4588-9dc2-0d4f8a34b7a5'::uuid, 'mock-parity-public-member'),
    ('747de065-e492-449c-b4e0-caa857ca413f'::uuid, 'mock-parity-public-nonmember'),
    ('e30c018c-d19f-44f3-ada8-d7e666d45c55'::uuid, 'mock-parity-private-nonmember')
  );
end;
$$;

-- The authenticated collection view includes both joined groups and public
-- discovery groups. Expose only classification booleans so the app can keep
-- "My groups" separate from public discovery without exposing membership
-- rows or private receiver data.
create or replace view public.member_collections_view
with (security_invoker = true)
as
select
  c.id,
  c.slug,
  c.creator_user_id,
  c.title,
  c.description,
  c.currency,
  c.collection_type,
  c.category_subtype,
  c.purpose_label,
  c.suggested_amount_rwf,
  c.diaspora_enabled,
  c.diaspora_regions,
  c.moderation_status,
  case
    when public.user_is_collection_admin(c.id, auth.uid())
      or exists (
        select 1
        from public.collection_receivers receiver_check
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
  c.recurring_cadence,
  c.public_status = 'public_approved' as is_public,
  (
    c.creator_user_id = auth.uid()
    or exists (
      select 1
      from public.collection_members member_check
      where member_check.collection_id = c.id
        and member_check.user_id = auth.uid()
        and member_check.status = 'active'
    )
  ) as is_member
from public.collections c
left join lateral (
  select
    receiver.momo_number,
    receiver.label,
    receiver.network
  from public.collection_receivers receiver
  where receiver.collection_id = c.id
    and receiver.is_active
  order by receiver.created_at asc
  limit 1
) cr on true
where public.user_can_read_collection(c.id, auth.uid());

alter view public.member_collections_view set (security_invoker = true);
revoke all on public.member_collections_view from public, anon;
grant select on public.member_collections_view to authenticated;

commit;
