begin;

-- PostgREST may expose this view to signed-out clients, so keep it limited to
-- catalogue metadata and let the collections RLS policy enforce public rows.
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
  collection.is_platform_sponsored
from public.collections collection
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
  archived_at
) on public.collections to anon, authenticated;

comment on view public.public_collections_view is
  'Signed-out-safe platform public group directory. Receiver routes and member data are excluded.';

commit;
