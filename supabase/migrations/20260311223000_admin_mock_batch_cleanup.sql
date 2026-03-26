begin;
-- ============================================================================
-- Admin mock-batch cleanup
-- ----------------------------------------------------------------------------
-- Allows admin users to purge a full demo/mock batch across public tables and
-- matching auth users in one operation.
-- ============================================================================

create or replace function public.purge_mock_batch(p_mock_batch text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_batch text := nullif(trim(p_mock_batch), '');
  v_result jsonb := '{}'::jsonb;
  v_count integer := 0;
begin
  if v_batch is null then
    raise exception 'Mock batch is required.';
  end if;

  if not public.is_admin_user() then
    raise exception 'Only admins can purge mock data batches.';
  end if;

  create temporary table tmp_mock_user_ids (
    user_id uuid primary key
  ) on commit drop;

  insert into tmp_mock_user_ids (user_id)
  select distinct id
  from public.users
  where mock_batch = v_batch
  union
  select distinct id
  from auth.users
  where coalesce(raw_user_meta_data ->> 'mock_batch', '') = v_batch
     or coalesce(raw_app_meta_data ->> 'mock_batch', '') = v_batch;

  delete from public.momo_reconciliations
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('momo_reconciliations', v_count);

  delete from public.momo_ledger_entries
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('momo_ledger_entries', v_count);

  delete from public.momo_sms_parsed
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('momo_sms_parsed', v_count);

  delete from public.momo_sms_raw
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('momo_sms_raw', v_count);

  delete from public.cool_mission_progress
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('cool_mission_progress', v_count);

  delete from public.cool_events
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('cool_events', v_count);

  delete from public.cool_status
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('cool_status', v_count);

  delete from public.season_memberships
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('season_memberships', v_count);

  delete from public.credit_scores
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('credit_scores', v_count);

  delete from public.group_contributions
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('group_contributions', v_count);

  delete from public.group_members
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('group_members', v_count);

  delete from public.groups
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('groups', v_count);

  delete from public.rs_tickets
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_tickets', v_count);

  delete from public.rs_shop_orders
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_shop_orders', v_count);

  delete from public.rs_initiative_contributions
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_initiative_contributions', v_count);

  delete from public.rs_achievements
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_achievements', v_count);

  delete from public.rs_fan_club_members
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_fan_club_members', v_count);

  delete from public.rs_fan_memberships
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_fan_memberships', v_count);

  delete from public.rs_matches
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_matches', v_count);

  delete from public.rs_shop_products
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('rs_shop_products', v_count);

  delete from public.partner_services
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('partner_services', v_count);

  delete from public.partners
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('partners', v_count);

  delete from public.cool_missions
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('cool_missions', v_count);

  delete from public.season_definitions
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('season_definitions', v_count);

  delete from public.cool_seasons
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('cool_seasons', v_count);

  delete from public.users
  where mock_batch = v_batch;
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('users', v_count);

  delete from auth.users
  where id in (select user_id from tmp_mock_user_ids);
  get diagnostics v_count = row_count;
  v_result := v_result || jsonb_build_object('auth_users', v_count);

  return jsonb_build_object(
    'success',
    true,
    'mock_batch',
    v_batch,
    'deleted',
    v_result
  );
end;
$$;
grant execute on function public.purge_mock_batch(text) to authenticated;
commit;
