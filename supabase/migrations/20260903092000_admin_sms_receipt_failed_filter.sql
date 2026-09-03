begin;

insert into public.admin_queue_filter_options(
  rpc_name, filter_kind, value, label, display_order, enabled
) values (
  'admin_list_hybrid_sms_receipts', 'status', 'failed_no_send',
  'Failed—no send', 55, true
)
on conflict (rpc_name, filter_kind, value) do update set
  label = excluded.label,
  display_order = excluded.display_order,
  enabled = excluded.enabled,
  updated_at = now();

commit;
