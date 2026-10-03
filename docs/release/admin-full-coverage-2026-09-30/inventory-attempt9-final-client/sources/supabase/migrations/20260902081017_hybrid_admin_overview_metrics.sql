begin;

-- Use the same hybrid queue contracts as the workspace. A bank-only count
-- must never report healthy/empty while Rwanda reconciliation work is open.
create or replace function public.admin_overview()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  review_count bigint;
  unallocated_count bigint;
  balanced_count bigint;
  payee_count bigint;
begin
  perform public.assert_admin_permission('overview.read');
  review_count := (public.admin_list_collect_reconciliations(null,null,1,0,'created_at_desc')->>'total')::bigint;
  unallocated_count := (public.admin_list_collect_transactions(null,'unallocated',1,0,'created_at_desc')->>'total')::bigint;
  balanced_count := (public.admin_list_collect_ledgers(null,'balanced',1,0,'created_at_desc')->>'total')::bigint;
  payee_count := (public.admin_list_collect_payees(null,'active',1,0,'created_at_desc')->>'total')::bigint;
  return jsonb_build_object('metrics', jsonb_build_array(
    jsonb_build_object('label','Open reconciliations','value',review_count,
      'status',case when review_count>0 then 'needs_review' else 'active' end),
    jsonb_build_object('label','Unallocated transactions','value',unallocated_count,
      'status',case when unallocated_count>0 then 'needs_review' else 'active' end),
    jsonb_build_object('label','Balanced ledgers','value',balanced_count,'status','active'),
    jsonb_build_object('label','Active payees','value',payee_count,'status','active')
  ));
end;
$$;
revoke all on function public.admin_overview() from public,anon,authenticated;
grant execute on function public.admin_overview() to authenticated;
commit;
