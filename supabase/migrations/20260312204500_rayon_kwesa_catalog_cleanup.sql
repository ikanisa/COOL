-- ============================================================================
-- Cool App — Rayon Sports KWESA catalog cleanup
-- ----------------------------------------------------------------------------
-- Keeps the curated KWESA-style Rayon catalog active while retiring older mock
-- placeholder products that were left behind by previous demo seeds.
-- ============================================================================

do $$
declare
  v_partner_id uuid;
begin
  select id
  into v_partner_id
  from public.partners
  where slug = 'rayon-sports'
  limit 1;

  if v_partner_id is null then
    raise exception 'Rayon Sports partner not found for catalog cleanup.';
  end if;

  update public.rs_shop_products
  set
    is_active = false,
    updated_at = now()
  where partner_id = v_partner_id
    and coalesce(is_mock, false) = true
    and name not in (
      'Home Replica Jersey',
      'Away Replica Jersey',
      '1968 Jersey',
      'Warm Up Top',
      'Rayon Hoodie',
      'Rayon Gilet',
      'Rayon Cap',
      'Gikundiro Scarf',
      'Rayon Slipper',
      'Rayon Sports Ball',
      'Rayon Watch',
      'Rayon Valeze'
    );
end;
$$;
