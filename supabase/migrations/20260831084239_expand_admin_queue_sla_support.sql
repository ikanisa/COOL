begin;

insert into public.admin_queue_sla_policies (
  queue_key,
  target,
  owner,
  escalation
)
values
  (
    'admin_list_bank_destinations',
    'Review beneficiary configuration before activation or retirement',
    'Bank reconciliation operations',
    'Escalate any unverified beneficiary change immediately'
  ),
  (
    'admin_list_bank_destination_change_requests',
    'Complete independent beneficiary review within 1 business day',
    'Payments control checker',
    'Escalate aged requests without bypassing maker-checker'
  ),
  (
    'admin_list_bank_transfer_intents',
    'Review expired or unmatched transfer requests within 4 business hours',
    'Payments operations',
    'Escalate duplicate, disputed, or unidentified transfers the same day'
  ),
  (
    'admin_list_bank_transactions',
    'Review unreconciled bank transactions within 4 business hours',
    'Payments operations',
    'Escalate duplicate or unmatched receipts the same day'
  ),
  (
    'admin_list_reconciliation_runs',
    'Complete daily reconciliation by the next business day',
    'Finance operations',
    'Escalate an incomplete or unbalanced close immediately'
  ),
  (
    'admin_list_journal_entries',
    'Review bank journal posting and balance status each business day',
    'Finance operations',
    'Escalate any unbalanced or unexplained journal entry immediately'
  )
on conflict (queue_key) do update
set target = excluded.target,
    owner = excluded.owner,
    escalation = excluded.escalation,
    updated_at = now();

create or replace function public.admin_get_queue_sla(p_queue_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  normalized_queue_key text := trim(coalesce(p_queue_key, ''));
  policy_row public.admin_queue_sla_policies%rowtype;
begin
  case normalized_queue_key
    when 'admin_list_payment_events' then perform public.assert_admin_permission('payment_events.read');
    when 'admin_list_allocations' then perform public.assert_admin_permission('payment_events.read');
    when 'admin_list_unallocated' then perform public.assert_admin_permission('payment_events.read');
    when 'admin_list_sms_metadata' then perform public.assert_admin_permission('sms.metadata.read');
    when 'admin_list_collections' then perform public.assert_admin_permission('collections.read');
    when 'admin_list_users' then perform public.assert_admin_permission('users.read');
    when 'admin_list_payment_intents' then perform public.assert_admin_permission('payments.read');
    when 'admin_list_payments' then perform public.assert_admin_permission('payments.read');
    when 'admin_list_receivers' then perform public.assert_admin_permission('receivers.read');
    when 'admin_list_ledger' then perform public.assert_admin_permission('ledger.read');
    when 'admin_list_bank_destinations' then perform public.assert_admin_permission('bank_details.read');
    when 'admin_list_bank_destination_change_requests' then perform public.assert_admin_permission('bank_details.read');
    when 'admin_list_bank_transfer_intents' then perform public.assert_admin_permission('bank_transactions.read');
    when 'admin_list_bank_transactions' then perform public.assert_admin_permission('bank_transactions.read');
    when 'admin_list_bank_evidence' then perform public.assert_admin_permission('bank_evidence.read');
    when 'admin_list_reconciliation_runs' then perform public.assert_admin_permission('bank_reconciliation.read');
    when 'admin_list_reconciliation_exceptions' then perform public.assert_admin_permission('bank_reconciliation.read');
    when 'admin_list_bank_allocation_requests' then perform public.assert_admin_permission('bank_transactions.read');
    when 'admin_list_journal_entries' then perform public.assert_admin_permission('bank_reconciliation.read');
    when 'admin_list_notifications' then perform public.assert_admin_permission('notifications.read');
    when 'admin_list_audit_logs' then perform public.assert_admin_permission('audit.read');
    when 'admin_list_settings' then perform public.assert_admin_permission('settings.read');
    when 'admin_list_feature_flags' then perform public.assert_admin_permission('feature_flags.read');
    when 'admin_list_admin_users' then perform public.assert_admin_permission('admin_users.read');
    else raise exception 'Unsupported admin queue SLA key: %', normalized_queue_key;
  end case;

  select *
  into policy_row
  from public.admin_queue_sla_policies
  where queue_key = normalized_queue_key;

  if not found then
    return '{}'::jsonb;
  end if;

  return jsonb_build_object(
    'queue_key', policy_row.queue_key,
    'target', policy_row.target,
    'owner', policy_row.owner,
    'escalation', policy_row.escalation,
    'updated_at', policy_row.updated_at
  );
end;
$$;

revoke execute on function public.admin_get_queue_sla(text) from public, anon;
grant execute on function public.admin_get_queue_sla(text) to authenticated;

comment on function public.admin_get_queue_sla(text) is
  'Returns permission-gated operational SLA guidance for every current Admin queue.';

commit;
