begin;

-- The invoker view reads private receiver rows, which browser roles correctly
-- cannot select directly. Expose its scoped projection through an authenticated
-- RPC instead of granting access to the underlying receiver table.
create or replace function public.list_current_user_collections(
  p_collection_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select coalesce(jsonb_agg(
    to_jsonb(collection) || jsonb_strip_nulls(jsonb_build_object(
      'payment_rail', route.payment_rail,
      'settlement_currency', route.settlement_currency,
      'receiver_momo_number', route.receiver_momo_number,
      'receiver_display_label', route.receiver_display_label,
      'receiver_network', route.receiver_network
    )) order by collection.created_at desc, collection.id
  ), '[]'::jsonb)
  into result
  from public.member_collections_view collection
  left join lateral public.public_collection_payment_route(collection.id) route
    on true
  where (p_collection_id is null or collection.id = p_collection_id)
    and public.user_can_read_collection(collection.id, auth.uid());

  return result;
end;
$$;

revoke all on function public.list_current_user_collections(uuid)
  from public, anon, authenticated;
grant execute on function public.list_current_user_collections(uuid)
  to authenticated;

comment on function public.list_current_user_collections(uuid) is
  'Authenticated member catalogue. Retains collection authorization and private receiver masking; adds only the approved public payment route. Does not grant receiver-table access.';

-- The Rwanda client calls this contract, but the hybrid cutover restored only
-- the projection view. Keep payment storage private and reuse its masked rows.
create or replace function public.list_current_user_contributions()
returns setof public.member_contributions_view
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  return query
    select contribution.*
    from public.member_contributions_view contribution
    where public.user_can_read_collection(contribution.collection_id, auth.uid())
    order by contribution.posted_at desc, contribution.payment_id;
end;
$$;
revoke all on function public.list_current_user_contributions()
  from public, anon, authenticated;
grant execute on function public.list_current_user_contributions()
  to authenticated;

commit;
