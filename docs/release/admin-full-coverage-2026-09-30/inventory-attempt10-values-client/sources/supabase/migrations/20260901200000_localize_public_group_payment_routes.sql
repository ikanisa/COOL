begin;

-- Public platform groups are contribution destinations, so their public
-- directory contract must include the safe route that a contributor needs to
-- choose the correct mobile journey. Private/member-created receiver rows,
-- receiver owners, and hashes remain excluded.
create or replace function public.public_collection_payment_route(
  p_collection_id uuid
)
returns table (
  payment_rail text,
  settlement_currency text,
  receiver_momo_number text,
  receiver_display_label text,
  receiver_network text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    'rwanda_momo'::text,
    'RWF'::text,
    receiver.momo_number,
    receiver.label,
    receiver.network
  from public.collections collection
  join lateral (
    select route.momo_number, route.label, route.network
    from public.collection_receivers route
    where route.collection_id = collection.id
      and route.is_active
      and route.network in ('mtn_momo', 'airtel_money')
    order by route.created_at
    limit 1
  ) receiver on true
  where collection.id = p_collection_id
    and collection.public_status = 'public_approved'
    and collection.is_platform_sponsored
    and collection.archived_at is null;
$$;

revoke all on function public.public_collection_payment_route(uuid)
  from public, anon, authenticated;
grant execute on function public.public_collection_payment_route(uuid)
  to anon, authenticated;

create or replace view public.public_collections_view
with (security_invoker = true, security_barrier = true)
as
select
  collection.id,
  collection.slug,
  collection.title,
  collection.description,
  collection.category,
  collection.cover_image_url,
  collection.target_amount_rwf,
  collection.deadline_at,
  collection.is_recurring,
  collection.created_at,
  collection.collection_type,
  collection.category_subtype,
  collection.purpose_label,
  collection.suggested_amount_rwf,
  collection.accent_color_hex,
  collection.recurring_cadence,
  collection.is_platform_sponsored,
  collection.diaspora_enabled,
  collection.diaspora_regions,
  coalesce(route.payment_rail, 'unavailable') as payment_rail,
  coalesce(route.settlement_currency, collection.currency) as settlement_currency,
  route.receiver_momo_number,
  route.receiver_display_label,
  route.receiver_network
from public.collections collection
left join lateral public.public_collection_payment_route(collection.id) route
  on true
where collection.public_status = 'public_approved'
  and collection.is_platform_sponsored
  and collection.archived_at is null;

revoke all on public.public_collections_view from public, anon, authenticated;
grant select on public.public_collections_view to anon, authenticated;

grant select (
  id,
  slug,
  title,
  description,
  category,
  cover_image_url,
  target_amount_rwf,
  deadline_at,
  is_recurring,
  created_at,
  collection_type,
  category_subtype,
  purpose_label,
  suggested_amount_rwf,
  accent_color_hex,
  recurring_cadence,
  is_platform_sponsored,
  public_status,
  archived_at,
  diaspora_enabled,
  diaspora_regions,
  currency
) on public.collections to anon, authenticated;

comment on function public.public_collection_payment_route(uuid) is
  'Signed-out-safe active payment route for an approved platform-sponsored public group only.';
comment on view public.public_collections_view is
  'Signed-out-safe platform group directory with the minimum contribution route; private receiver ownership and hashes are excluded.';

commit;
