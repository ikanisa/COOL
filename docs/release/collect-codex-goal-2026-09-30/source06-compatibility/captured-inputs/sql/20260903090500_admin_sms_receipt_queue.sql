begin;

create function public.admin_list_hybrid_sms_receipts(
  p_search text default null,
  p_status text default null,
  p_limit integer default 25,
  p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  bounded_limit integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  bounded_offset integer := greatest(coalesce(p_offset, 0), 0);
  result jsonb;
begin
  perform public.assert_admin_permission('notifications.read');
  with filtered as (
    select
      outbox.*,
      collection.title as collection_title,
      member.collect_id
    from collect_hybrid.sms_notification_outbox outbox
    join public.collections collection on collection.id = outbox.collection_id
    join collect_hybrid.member_records member on member.id = outbox.member_record_id
    where (nullif(btrim(coalesce(p_status, '')), '') is null
        or outbox.state = btrim(p_status))
      and (
        nullif(btrim(coalesce(p_search, '')), '') is null
        or collection.title ilike '%' || btrim(p_search) || '%'
        or member.collect_id = btrim(p_search)
        or outbox.reference ilike '%' || btrim(p_search) || '%'
        or right(outbox.destination_e164, 3) = btrim(p_search)
      )
  ), ordered as (
    select filtered.*,
      row_number() over (
        order by
          case when coalesce(p_sort, 'created_at_desc') = 'created_at_asc'
            then filtered.created_at end asc nulls last,
          filtered.created_at desc,
          filtered.id
      ) as admin_rank
    from filtered
    order by
      case when coalesce(p_sort, 'created_at_desc') = 'created_at_asc'
        then filtered.created_at end asc nulls last,
      filtered.created_at desc,
      filtered.id
    limit bounded_limit offset bounded_offset
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(public._admin_row(
      ordered.id,
      ordered.collection_title || ' receipt',
      'Collect ID ' || ordered.collect_id || ' • '
        || left(ordered.destination_e164, 4) || '•••'
        || right(ordered.destination_e164, 3),
      ordered.state,
      'RWF ' || to_char(ordered.amount_rwf, 'FM999,999,999,999,999,990'),
      ordered.created_at,
      jsonb_build_object(
        'collection_id', ordered.collection_id,
        'member_collect_id', ordered.collect_id,
        'reference', ordered.reference,
        'destination_masked', left(ordered.destination_e164, 4) || '•••'
          || right(ordered.destination_e164, 3),
        'template_key', ordered.template_key,
        'template_version', ordered.template_version,
        'consent_revision', ordered.consent_revision,
        'authorization_current',
          collect_hybrid.sms_receipt_job_is_current(ordered.id),
        'attempt_count', ordered.attempt_count,
        'claim_expires_at', ordered.claim_expires_at,
        'channel', 'assisted_sms',
        'country_code', 'RW'
      )
    ) order by ordered.admin_rank), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into result
  from ordered;
  return coalesce(result, jsonb_build_object('rows', '[]'::jsonb, 'total', 0));
end;
$$;

create function public.admin_get_hybrid_sms_receipt(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.assert_admin_permission('notifications.read');
  return coalesce((
    select jsonb_build_object(
      'id', outbox.id,
      'state', outbox.state,
      'channel', 'Assisted SMS operator',
      'member_collect_id', member.collect_id,
      'collection_id', outbox.collection_id,
      'collection_title', collection.title,
      'destination_masked', left(outbox.destination_e164, 4) || '•••'
        || right(outbox.destination_e164, 3),
      'amount_rwf', outbox.amount_rwf,
      'member_balance_rwf', outbox.member_balance_rwf,
      'group_balance_rwf', outbox.group_balance_rwf,
      'reference', outbox.reference,
      'template_key', outbox.template_key,
      'template_version', outbox.template_version,
      'consent_revision', outbox.consent_revision,
      'authorization_current',
        collect_hybrid.sms_receipt_job_is_current(outbox.id),
      'body_sha256', outbox.body_sha256,
      'message_body', 'Hidden until a current fenced operator claim',
      'attempt_count', outbox.attempt_count,
      'claim_expires_at', outbox.claim_expires_at,
      'suppression_reason', outbox.suppression_reason,
      'created_at', outbox.created_at,
      'observed_sent_at', outbox.observed_sent_at,
      'latest_attempt_state', (
        select attempt.state
        from collect_hybrid.sms_notification_attempts attempt
        where attempt.outbox_id = outbox.id
        order by attempt.attempt_number desc
        limit 1
      ),
      'delivery_claim',
        'Observed sent is operator-recorded UI evidence, not handset delivery'
    )
    from collect_hybrid.sms_notification_outbox outbox
    join public.collections collection on collection.id = outbox.collection_id
    join collect_hybrid.member_records member on member.id = outbox.member_record_id
    where outbox.id = p_id
  ), '{}'::jsonb);
end;
$$;

insert into public.admin_navigation_items(
  key, label, icon_key, route_path, required_permission,
  display_order, enabled, metadata, updated_reason
) values (
  'hybrid_sms_receipts', 'SMS receipts', 'sms', '/admin/sms-receipts',
  'notifications.read', 46, true,
  '{"channel":"assisted_sms","country":"RW"}',
  'Account-independent member receipt queue'
)
on conflict (key) do update set
  label = excluded.label,
  icon_key = excluded.icon_key,
  route_path = excluded.route_path,
  required_permission = excluded.required_permission,
  display_order = excluded.display_order,
  enabled = excluded.enabled,
  metadata = excluded.metadata,
  updated_at = now(),
  updated_reason = excluded.updated_reason;

insert into public.admin_queue_specs(
  rpc_name, title, subtitle, required_permission,
  display_order, enabled, metadata, updated_reason
) values (
  'admin_list_hybrid_sms_receipts', 'SMS receipts',
  'Feature-phone acknowledgements prepared from immutable posted balances.',
  'notifications.read', 28, true,
  '{"detail_rpc":"admin_get_hybrid_sms_receipt","channel":"assisted_sms"}',
  'Account-independent member receipt queue'
)
on conflict (rpc_name) do update set
  title = excluded.title,
  subtitle = excluded.subtitle,
  required_permission = excluded.required_permission,
  display_order = excluded.display_order,
  enabled = excluded.enabled,
  metadata = excluded.metadata,
  updated_at = now(),
  updated_reason = excluded.updated_reason;

delete from public.admin_queue_filter_options
where rpc_name = 'admin_list_hybrid_sms_receipts';
insert into public.admin_queue_filter_options(
  rpc_name, filter_kind, value, label, display_order, enabled
) values
  ('admin_list_hybrid_sms_receipts', 'status', '', 'All', 10, true),
  ('admin_list_hybrid_sms_receipts', 'status', 'queued', 'Queued', 20, true),
  ('admin_list_hybrid_sms_receipts', 'status', 'awaiting_confirmation', 'Awaiting confirmation', 30, true),
  ('admin_list_hybrid_sms_receipts', 'status', 'send_started', 'Send started', 40, true),
  ('admin_list_hybrid_sms_receipts', 'status', 'observed_sent', 'Observed sent', 50, true),
  ('admin_list_hybrid_sms_receipts', 'status', 'uncertain', 'Uncertain', 60, true),
  ('admin_list_hybrid_sms_receipts', 'status', 'suppressed', 'Suppressed', 70, true),
  ('admin_list_hybrid_sms_receipts', 'sort', 'created_at_desc', 'Newest', 10, true),
  ('admin_list_hybrid_sms_receipts', 'sort', 'created_at_asc', 'Oldest', 20, true);

revoke all on function public.admin_list_hybrid_sms_receipts(text, text, integer, integer, text)
  from public, anon;
revoke all on function public.admin_get_hybrid_sms_receipt(uuid)
  from public, anon;
grant execute on function public.admin_list_hybrid_sms_receipts(text, text, integer, integer, text)
  to authenticated;
grant execute on function public.admin_get_hybrid_sms_receipt(uuid)
  to authenticated;

comment on function public.admin_get_hybrid_sms_receipt(uuid) is
  'Admin-safe SMS receipt metadata; exact destination and body remain available only through a current fenced operator claim.';

commit;
