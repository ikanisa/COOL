begin;

create table if not exists admin_queue_sla_policies (
  queue_key text primary key,
  target text not null,
  owner text not null,
  escalation text not null,
  updated_by uuid references profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table admin_queue_sla_policies enable row level security;

revoke all on admin_queue_sla_policies from anon, authenticated;
grant all on admin_queue_sla_policies to service_role;

insert into admin_queue_sla_policies (queue_key, target, owner, escalation)
values
  (
    'admin_list_payment_events',
    'Review ambiguous SMS within 4 business hours',
    'Payments operations',
    'Escalate failed allocation after same-day retry'
  ),
  (
    'admin_list_allocations',
    'Clear allocation reviews by next business day',
    'Payments operations',
    'Escalate mismatched ledger impact immediately'
  ),
  (
    'admin_list_unallocated',
    'Triage open exceptions within 4 business hours',
    'Payments support',
    'Escalate unresolved member impact same day'
  ),
  (
    'admin_list_sms_metadata',
    'Review failed parser metadata within 1 business day',
    'Compliance support',
    'Escalate raw reveal requests to compliance owner'
  ),
  (
    'admin_list_collections',
    'Respond to group support requests within 1 business day',
    'Group operations',
    'Escalate receiver-readiness blockers same day'
  ),
  (
    'admin_list_users',
    'Respond to account support requests within 1 business day',
    'Member support',
    'Escalate identity or access risk immediately'
  ),
  (
    'admin_list_payments',
    'Review pending or expired intents within 1 business day',
    'Payments support',
    'Escalate duplicate or disputed intent same day'
  ),
  (
    'admin_list_receivers',
    'Review receiver setup changes within 1 business day',
    'Group operations',
    'Escalate inactive receiver routes before launch'
  ),
  (
    'admin_list_ledger',
    'Review ledger exceptions within 1 business day',
    'Finance operations',
    'Escalate correction path before member messaging'
  ),
  (
    'admin_list_audit_logs',
    'Review sensitive audit events daily',
    'Compliance owner',
    'Escalate unexplained sensitive access immediately'
  ),
  (
    'admin_list_settings',
    'Review config changes before release window',
    'Platform owner',
    'Escalate unapproved production change immediately'
  ),
  (
    'admin_list_feature_flags',
    'Review rollout flags before activation',
    'Product operations',
    'Escalate degraded health signal immediately'
  ),
  (
    'admin_list_admin_users',
    'Review operator access weekly',
    'Platform owner',
    'Revoke stale or overbroad access immediately'
  )
on conflict (queue_key) do update
set target = excluded.target,
    owner = excluded.owner,
    escalation = excluded.escalation,
    updated_at = now();

create or replace function admin_get_queue_sla(p_queue_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  normalized_queue_key text := trim(coalesce(p_queue_key, ''));
  policy_row admin_queue_sla_policies%rowtype;
begin
  case normalized_queue_key
    when 'admin_list_payment_events' then perform assert_admin_permission('payment_events.read');
    when 'admin_list_allocations' then perform assert_admin_permission('payment_events.read');
    when 'admin_list_unallocated' then perform assert_admin_permission('payment_events.read');
    when 'admin_list_sms_metadata' then perform assert_admin_permission('sms.metadata.read');
    when 'admin_list_collections' then perform assert_admin_permission('collections.read');
    when 'admin_list_users' then perform assert_admin_permission('users.read');
    when 'admin_list_payments' then perform assert_admin_permission('payments.read');
    when 'admin_list_receivers' then perform assert_admin_permission('receivers.read');
    when 'admin_list_ledger' then perform assert_admin_permission('ledger.read');
    when 'admin_list_audit_logs' then perform assert_admin_permission('audit.read');
    when 'admin_list_settings' then perform assert_admin_permission('settings.read');
    when 'admin_list_feature_flags' then perform assert_admin_permission('feature_flags.read');
    when 'admin_list_admin_users' then perform assert_admin_permission('admin_users.read');
    else raise exception 'Unsupported admin queue SLA key: %', normalized_queue_key;
  end case;

  select *
  into policy_row
  from admin_queue_sla_policies
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

revoke execute on function admin_get_queue_sla(text) from public, anon;
grant execute on function admin_get_queue_sla(text) to authenticated;

commit;
