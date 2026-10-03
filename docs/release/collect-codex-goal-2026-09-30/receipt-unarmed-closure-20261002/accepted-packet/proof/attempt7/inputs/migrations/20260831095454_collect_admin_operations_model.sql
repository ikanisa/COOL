begin;

-- The Admin surface intentionally exposes four financial operations only.
-- Rail-specific tables remain authoritative, but operators see one normalized
-- payee, transaction, reconciliation, and ledger model.

create or replace function public.collect_admin_mask_name(p_value text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when nullif(btrim(coalesce(p_value, '')), '') is null then null
    when char_length(btrim(p_value)) = 1 then left(btrim(p_value), 1) || '•••'
    else left(btrim(p_value), 1) || '•••' || right(btrim(p_value), 1)
  end;
$$;

create or replace function public.collect_admin_mask_sender(p_value text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when nullif(btrim(coalesce(p_value, '')), '') is null then null
    when regexp_replace(p_value, '[^0-9]', '', 'g') ~ '^[0-9]{6,}$'
      then public.mask_phone(p_value)
    when p_value like '%@%'
      then left(split_part(p_value, '@', 1), 1) || '•••@' || split_part(p_value, '@', 2)
    else left(btrim(p_value), 32)
  end;
$$;

revoke execute on function public.collect_admin_mask_name(text)
  from public, anon;
revoke execute on function public.collect_admin_mask_sender(text)
  from public, anon;
grant execute on function public.collect_admin_mask_name(text)
  to authenticated, service_role;
grant execute on function public.collect_admin_mask_sender(text)
  to authenticated, service_role;

create or replace function public.admin_list_collect_payees(
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
set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('receivers.read');

  with unified as (
    select
      'momo:' || receiver.id::text as id,
      coalesce(nullif(receiver.label, ''), collection.title) as title,
      'Rwanda · ' || case receiver.network
        when 'mtn_momo' then 'MTN MoMo'
        when 'airtel_money' then 'Airtel Money'
        else 'MoMo'
      end || ' · ' || coalesce(public.mask_phone(receiver.momo_number), 'Number unavailable') as subtitle,
      case when receiver.is_active then 'active' else 'inactive' end as status,
      'Rwanda · MoMo USSD' as amount,
      receiver.created_at,
      jsonb_build_object(
        'rail', 'rw_momo',
        'collection_id', receiver.collection_id,
        'collection_title', collection.title,
        'provider', receiver.network,
        'momo_number_masked', public.mask_phone(receiver.momo_number),
        'receiver_user_id', receiver.receiver_user_id
      ) as extra
    from public.collection_receivers receiver
    join public.collections collection on collection.id = receiver.collection_id

    union all

    select
      'diaspora-destination:' || destination.id::text,
      destination.beneficiary_name,
      'Diaspora · ' || destination.bank_name || ' · ' || public.mask_iban(destination.iban),
      destination.status,
      'Diaspora · ' || destination.currency || ' account',
      destination.created_at,
      jsonb_build_object(
        'rail', 'diaspora_account',
        'destination_id', destination.id,
        'account_masked', public.mask_iban(destination.iban),
        'bank_name', destination.bank_name,
        'currency', destination.currency,
        'is_placeholder', destination.is_placeholder
      )
    from public.bank_transfer_destinations destination

    union all

    select
      'diaspora-profile:' || profile.id::text,
      'Collect ID ' || profile.public_id,
      coalesce(profile.country_code, 'Diaspora') || ' · Revolut · ••••' ||
        right(regexp_replace(profile.revolut_account, '[^A-Za-z0-9]', '', 'g'), 4),
      'active',
      'Diaspora · Revolut profile',
      profile.updated_at,
      jsonb_build_object(
        'rail', 'diaspora_account',
        'profile_id', profile.id,
        'country_code', profile.country_code,
        'revolut_name_masked', public.collect_admin_mask_name(profile.revolut_name),
        'account_last4', right(regexp_replace(profile.revolut_account, '[^A-Za-z0-9]', '', 'g'), 4),
        'has_revolut_link', profile.revolut_link is not null
      )
    from public.profiles profile
    where profile.country_code is distinct from 'RW'
      and profile.revolut_account is not null
  ), filtered as (
    select * from unified
    where (
      nullif(btrim(coalesce(p_status, '')), '') is null
      or status = btrim(p_status)
    ) and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or title ilike '%' || btrim(p_search) || '%'
      or subtitle ilike '%' || btrim(p_search) || '%'
    )
  ), counted as (
    select filtered.*, count(*) over () as total_count
    from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', id, 'title', title, 'subtitle', subtitle,
        'status', status, 'amount', amount, 'created_at', created_at
      ) || extra order by created_at desc
    ), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_list_collect_transactions(
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
set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('payments.read');

  with unified as (
    select
      'momo:' || sms.id::text as id,
      coalesce(event.transaction_id, 'Receipt ' || right(sms.body_hash, 8)) as title,
      'Rwanda · ' || case event.network
        when 'mtn_momo' then 'MTN MoMo'
        when 'airtel_money' then 'Airtel Money'
        else 'MoMo SMS'
      end || ' · ' || coalesce(collection.title, 'Payee not linked') as subtitle,
      coalesce(event.allocation_status::text, sms.parse_status) as status,
      case when event.amount_rwf is null then ''
        else 'RWF ' || to_char(event.amount_rwf, 'FM999G999G999G999') end as amount,
      coalesce(sms.received_at_device, sms.ingested_at) as created_at,
      jsonb_build_object(
        'rail', 'rw_momo',
        'raw_sms_id', sms.id,
        'event_id', event.id,
        'payment_id', payment.id,
        'collection_id', coalesce(payment.collection_id, event.collection_id, sms.collection_id),
        'payment_intent_id', payment.payment_intent_id,
        'reference', event.transaction_id,
        'sender_masked', public.collect_admin_mask_sender(sms.raw_sender)
      ) as extra
    from public.raw_payment_sms sms
    left join public.parsed_payment_events event on event.raw_sms_id = sms.id
    left join public.payments payment on payment.parsed_event_id = event.id
    left join public.collections collection
      on collection.id = coalesce(payment.collection_id, event.collection_id, sms.collection_id)

    union all

    select
      'diaspora:' || evidence.id::text,
      coalesce(bank_transaction.bank_transaction_id, event.transfer_reference,
        'Account receipt ' || right(evidence.body_hash, 8)),
      'Diaspora · ' || upper(evidence.channel) || ' · ' ||
        coalesce(collection.title, destination.beneficiary_name, 'Payee not linked'),
      coalesce(event.allocation_status, bank_transaction.status, evidence.parse_status),
      case when coalesce(bank_transaction.amount_minor, event.amount_minor) is null then ''
        else coalesce(bank_transaction.currency, event.currency, 'EUR') || ' ' ||
          to_char(coalesce(bank_transaction.amount_minor, event.amount_minor)::numeric / 100,
            'FM999G999G999D00') end,
      evidence.received_at,
      jsonb_build_object(
        'rail', 'diaspora_account',
        'raw_bank_event_id', event.id,
        'raw_evidence_id', evidence.id,
        'transaction_id', bank_transaction.id,
        'collection_id', allocation.collection_id,
        'payment_intent_id', allocation.bank_transfer_intent_id,
        'reference', coalesce(bank_transaction.transfer_reference, event.transfer_reference),
        'sender_masked', public.collect_admin_mask_sender(evidence.raw_sender)
      )
    from public.raw_payment_evidence evidence
    left join public.bank_evidence_events event on event.raw_evidence_id = evidence.id
    left join public.payment_evidence_links evidence_link
      on evidence_link.evidence_event_id = event.id
    left join public.bank_transactions bank_transaction
      on bank_transaction.id = evidence_link.bank_transaction_id
    left join public.bank_transaction_allocations allocation
      on allocation.bank_transaction_id = bank_transaction.id
    left join public.collections collection on collection.id = allocation.collection_id
    left join public.bank_transfer_destinations destination
      on destination.id = bank_transaction.destination_id
  ), filtered as (
    select * from unified
    where (
      nullif(btrim(coalesce(p_status, '')), '') is null
      or status = btrim(p_status)
    ) and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or title ilike '%' || btrim(p_search) || '%'
      or subtitle ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'reference', '') ilike '%' || btrim(p_search) || '%'
    )
  ), counted as (
    select filtered.*, count(*) over () as total_count
    from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      case when p_sort = 'amount_asc' then amount end asc nulls last,
      case when p_sort = 'amount_desc' then amount end desc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', id, 'title', title, 'subtitle', subtitle,
        'status', status, 'amount', amount, 'created_at', created_at
      ) || extra order by created_at desc
    ), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_get_collect_transaction(p_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  rail text := split_part(coalesce(p_id, ''), ':', 1);
  record_text text := split_part(coalesce(p_id, ''), ':', 2);
  record_id uuid;
  result jsonb;
begin
  perform public.assert_admin_permission('payments.read');
  if record_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return '{}'::jsonb;
  end if;
  record_id := record_text::uuid;

  if rail = 'momo' then
    select jsonb_build_object(
      'id', 'momo:' || sms.id::text,
      'transaction_id', coalesce(event.transaction_id, 'Receipt ' || right(sms.body_hash, 8)),
      'payment_route', 'Rwanda MoMo USSD + receipt SMS',
      'rail', 'rw_momo',
      'raw_sms_id', sms.id,
      'sms_sender', public.collect_admin_mask_sender(sms.raw_sender),
      'parse_status', sms.parse_status,
      'sender_name', public.collect_admin_mask_name(event.sender_name),
      'network', case event.network
        when 'mtn_momo' then 'MTN MoMo'
        when 'airtel_money' then 'Airtel Money'
        else 'Unknown MoMo provider' end,
      'reference', event.transaction_id,
      'amount', case when event.amount_rwf is null then null
        else 'RWF ' || to_char(event.amount_rwf, 'FM999G999G999G999') end,
      'payee', coalesce(receiver.label, 'MoMo payee') || ' · ' ||
        coalesce(public.mask_phone(receiver.momo_number), 'number unavailable'),
      'group_name', collection.title,
      'allocation_status', coalesce(event.allocation_status::text, sms.parse_status),
      'received_at', coalesce(sms.received_at_device, sms.ingested_at),
      'created_at', sms.created_at
    ) into result
    from public.raw_payment_sms sms
    left join public.parsed_payment_events event on event.raw_sms_id = sms.id
    left join public.payments payment on payment.parsed_event_id = event.id
    left join public.collections collection
      on collection.id = coalesce(payment.collection_id, event.collection_id, sms.collection_id)
    left join lateral (
      select route.* from public.collection_receivers route
      where route.collection_id = collection.id and route.is_active
      order by route.created_at desc limit 1
    ) receiver on true
    where sms.id = record_id;
  elsif rail = 'diaspora' then
    select jsonb_build_object(
      'id', 'diaspora:' || evidence.id::text,
      'transaction_id', coalesce(bank_transaction.bank_transaction_id,
        event.transfer_reference, 'Account receipt ' || right(evidence.body_hash, 8)),
      'payment_route', 'Diaspora bank / Revolut account transfer',
      'rail', 'diaspora_account',
      'raw_bank_event_id', event.id,
      'sms_sender', public.collect_admin_mask_sender(evidence.raw_sender),
      'source', upper(evidence.channel),
      'parse_status', evidence.parse_status,
      'payer_name', public.collect_admin_mask_name(
        coalesce(bank_transaction.payer_name, event.payer_name)),
      'provider', coalesce(destination.bank_name, 'Diaspora account'),
      'reference', coalesce(bank_transaction.transfer_reference, event.transfer_reference),
      'amount', case when coalesce(bank_transaction.amount_minor, event.amount_minor) is null then null
        else coalesce(bank_transaction.currency, event.currency, 'EUR') || ' ' ||
          to_char(coalesce(bank_transaction.amount_minor, event.amount_minor)::numeric / 100,
            'FM999G999G999D00') end,
      'payee', coalesce(destination.beneficiary_name, 'Diaspora payee') || ' · ' ||
        coalesce(public.mask_iban(destination.iban), 'account unavailable'),
      'group_name', collection.title,
      'allocation_status', coalesce(event.allocation_status,
        bank_transaction.status, evidence.parse_status),
      'received_at', evidence.received_at,
      'created_at', evidence.created_at
    ) into result
    from public.raw_payment_evidence evidence
    left join public.bank_evidence_events event on event.raw_evidence_id = evidence.id
    left join public.payment_evidence_links evidence_link
      on evidence_link.evidence_event_id = event.id
    left join public.bank_transactions bank_transaction
      on bank_transaction.id = evidence_link.bank_transaction_id
    left join public.bank_transaction_allocations allocation
      on allocation.bank_transaction_id = bank_transaction.id
    left join public.collections collection on collection.id = allocation.collection_id
    left join public.bank_transfer_destinations destination
      on destination.id = bank_transaction.destination_id
    where evidence.id = record_id;
  else
    return '{}'::jsonb;
  end if;
  return coalesce(result, '{}'::jsonb);
end;
$$;

create or replace function public.admin_list_collect_reconciliations(
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
set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('payment_events.read');

  with unified as (
    select
      'momo:' || event.id::text as id,
      coalesce(event.transaction_id, 'Unallocated MoMo receipt') as title,
      'Rwanda · ' || coalesce(collection.title, 'Select a group payee') as subtitle,
      event.allocation_status::text as status,
      case when event.amount_rwf is null then ''
        else 'RWF ' || to_char(event.amount_rwf, 'FM999G999G999G999') end as amount,
      event.created_at,
      jsonb_build_object(
        'rail', 'rw_momo',
        'event_id', event.id,
        'transaction_id', null,
        'collection_id', coalesce(event.collection_id, candidate.collection_id),
        'payment_intent_id', candidate.id,
        'can_allocate', event.id is not null,
        'reference', event.transaction_id,
        'age', now() - event.created_at
      ) as extra
    from public.parsed_payment_events event
    left join public.collections collection on collection.id = event.collection_id
    left join lateral (
      select intent.id, intent.collection_id
      from public.payment_intents intent
      where intent.status = 'pending'
        and intent.expires_at > now()
        and intent.expected_amount_rwf = event.amount_rwf
        and (event.collection_id is null or intent.collection_id = event.collection_id)
        and (
          (event.sender_phone_hash is not null and intent.sender_phone_hash = event.sender_phone_hash)
          or (event.detected_user_public_id is not null
            and intent.contributor_public_id = event.detected_user_public_id)
        )
      order by intent.created_at desc
      limit 1
    ) candidate on true
    where event.allocation_status in ('unallocated', 'ambiguous', 'needs_review')

    union all

    select
      'diaspora:' || bank_transaction.id::text,
      coalesce(bank_transaction.transfer_reference,
        bank_transaction.bank_transaction_id, 'Unallocated account receipt'),
      'Diaspora · ' || coalesce(collection.title, 'Select a group payee'),
      coalesce(exception.exception_type, bank_transaction.status),
      bank_transaction.currency || ' ' ||
        to_char(bank_transaction.amount_minor::numeric / 100, 'FM999G999G999D00'),
      bank_transaction.created_at,
      jsonb_build_object(
        'rail', 'diaspora_account',
        'event_id', null,
        'transaction_id', bank_transaction.id,
        'collection_id', candidate.collection_id,
        'payment_intent_id', candidate.id,
        'can_allocate', bank_transaction.status not in ('reconciled', 'returned'),
        'reference', bank_transaction.transfer_reference,
        'age', now() - bank_transaction.created_at
      )
    from public.bank_transactions bank_transaction
    left join public.bank_transaction_allocations allocation
      on allocation.bank_transaction_id = bank_transaction.id
    left join lateral (
      select intent.id, intent.collection_id
      from public.bank_transfer_intents intent
      where intent.status not in ('reconciled', 'returned', 'cancelled', 'expired')
        and intent.currency = bank_transaction.currency
        and intent.amount_minor = bank_transaction.amount_minor
        and (bank_transaction.transfer_reference is null
          or intent.transfer_reference = bank_transaction.transfer_reference)
      order by intent.created_at desc
      limit 1
    ) candidate on true
    left join public.collections collection on collection.id = candidate.collection_id
    left join lateral (
      select reconciliation.exception_type
      from public.reconciliation_exceptions reconciliation
      where reconciliation.bank_transaction_id = bank_transaction.id
        and reconciliation.status in ('open', 'reviewing')
      order by reconciliation.created_at desc limit 1
    ) exception on true
    where allocation.id is null
      and bank_transaction.status not in ('reconciled', 'returned')

    union all

    select
      'diaspora-exception:' || exception.id::text,
      replace(exception.exception_type, '_', ' '),
      'Diaspora · reconciliation exception without a canonical transaction',
      exception.status,
      '',
      exception.created_at,
      jsonb_build_object(
        'rail', 'diaspora_exception',
        'event_id', null,
        'transaction_id', null,
        'collection_id', null,
        'payment_intent_id', exception.bank_transfer_intent_id,
        'can_allocate', false,
        'age', now() - exception.created_at
      )
    from public.reconciliation_exceptions exception
    where exception.bank_transaction_id is null
      and exception.status in ('open', 'reviewing')
  ), filtered as (
    select * from unified
    where (
      nullif(btrim(coalesce(p_status, '')), '') is null
      or status = btrim(p_status)
    ) and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or title ilike '%' || btrim(p_search) || '%'
      or subtitle ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'reference', '') ilike '%' || btrim(p_search) || '%'
    )
  ), counted as (
    select filtered.*, count(*) over () as total_count
    from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', id, 'title', title, 'subtitle', subtitle,
        'status', status, 'amount', amount, 'created_at', created_at
      ) || extra order by created_at desc
    ), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_list_collect_ledgers(
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
set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('ledger.read');

  with unified as (
    select
      'momo:' || payment.id::text as id,
      coalesce(payment.transaction_id, 'Rwanda allocation ' || right(payment.id::text, 8)) as title,
      'Rwanda · payment clearing debit · group/member allocation credit' as subtitle,
      case when ledger.collection_credit = payment.amount_rwf
          and ledger.member_credit = payment.amount_rwf
        then 'balanced' else 'exception' end as status,
      'RWF ' || to_char(payment.amount_rwf, 'FM999G999G999G999') || ' =',
      payment.created_at,
      jsonb_build_object(
        'rail', 'rw_momo',
        'payment_id', payment.id,
        'collection_id', payment.collection_id,
        'debit_total', payment.amount_rwf,
        'credit_total', least(ledger.collection_credit, ledger.member_credit),
        'currency', 'RWF',
        'line_count', ledger.line_count
      ) as extra
    from public.payments payment
    join lateral (
      select
        coalesce(sum(entry.amount_rwf) filter (where entry.entry_type = 'collection_credit'), 0) as collection_credit,
        coalesce(sum(entry.amount_rwf) filter (where entry.entry_type = 'member_credit'), 0) as member_credit,
        count(*) as line_count
      from public.ledger_entries entry where entry.payment_id = payment.id
    ) ledger on true

    union all

    select
      'diaspora:' || journal.id::text,
      coalesce(journal.external_reference, 'Diaspora journal ' || right(journal.id::text, 8)),
      'Diaspora · ' || journal.description,
      case when totals.debit_total = totals.credit_total and totals.debit_total > 0
        then 'balanced' else 'exception' end,
      journal.currency || ' ' ||
        to_char(totals.debit_total::numeric / 100, 'FM999G999G999D00') || ' =',
      journal.posted_at,
      jsonb_build_object(
        'rail', 'diaspora_account',
        'journal_entry_id', journal.id,
        'transaction_id', journal.bank_transaction_id,
        'collection_id', journal.collection_id,
        'debit_total', totals.debit_total,
        'credit_total', totals.credit_total,
        'currency', journal.currency,
        'line_count', totals.line_count
      )
    from public.journal_entries journal
    join lateral (
      select
        coalesce(sum(line.amount_minor) filter (where line.direction = 'debit'), 0) as debit_total,
        coalesce(sum(line.amount_minor) filter (where line.direction = 'credit'), 0) as credit_total,
        count(*) as line_count
      from public.journal_lines line where line.journal_entry_id = journal.id
    ) totals on true
  ), filtered as (
    select * from unified
    where (
      nullif(btrim(coalesce(p_status, '')), '') is null
      or status = btrim(p_status)
    ) and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or title ilike '%' || btrim(p_search) || '%'
      or subtitle ilike '%' || btrim(p_search) || '%'
    )
  ), counted as (
    select filtered.*, count(*) over () as total_count
    from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', id, 'title', title, 'subtitle', subtitle,
        'status', status, 'amount', amount, 'created_at', created_at
      ) || extra order by created_at desc
    ), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

-- Admin review cannot relax the native receipt checks. The selected intent must
-- still match receiver, payer identity, amount, currency, and evidence window.
insert into public.admin_permissions (name, description)
values ('payments.allocate', 'Complete a strictly verified Rwanda MoMo receipt allocation')
on conflict (name) do update set description = excluded.description;

insert into public.admin_role_permissions (role_id, permission_name)
select role.id, 'payments.allocate'
from public.admin_roles role
where role.name in ('platform_owner', 'payments_admin', 'operations_admin')
on conflict (role_id, permission_name) do nothing;

create or replace function public.admin_manual_allocate_payment(
  p_event_id uuid,
  p_collection_id uuid,
  p_payment_intent_id uuid default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  event_row public.parsed_payment_events%rowtype;
  intent_row public.payment_intents%rowtype;
  receiver_hash text;
  payment_id uuid;
begin
  perform public.assert_admin_permission('payments.allocate');
  if p_payment_intent_id is null then
    raise exception 'A verified payment intent is required';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 8 then
    raise exception 'Allocation reason must be at least 8 characters';
  end if;

  select * into event_row from public.parsed_payment_events
  where id = p_event_id for update;
  select * into intent_row from public.payment_intents
  where id = p_payment_intent_id for update;
  if event_row.id is null or intent_row.id is null then
    raise exception 'Payment event and intent are required';
  end if;
  if intent_row.collection_id <> p_collection_id then
    raise exception 'Payment intent does not belong to the selected group';
  end if;

  if event_row.receiver_phone_hash is null then
    select receiver.momo_number_hash into receiver_hash
    from public.collection_receivers receiver
    where receiver.collection_id = p_collection_id
      and receiver.receiver_user_id = event_row.receiver_user_id
      and receiver.momo_number_hash = intent_row.receiver_momo_number_hash
      and receiver.is_active
    order by receiver.created_at desc limit 1;
    if receiver_hash is null then
      raise exception 'SMS receiver is not an active payee for the selected group';
    end if;
    update public.parsed_payment_events
    set receiver_phone_hash = receiver_hash,
        collection_id = p_collection_id
    where id = p_event_id;
  end if;

  payment_id := public.post_payment_from_event(
    p_event_id,
    p_payment_intent_id,
    p_collection_id,
    'Admin verified allocation: ' || btrim(p_reason)
  );
  perform public.create_audit_log(
    'payment.allocated.admin_verified', 'payment', payment_id,
    jsonb_build_object(
      'parsed_event_id', p_event_id,
      'payment_intent_id', p_payment_intent_id,
      'collection_id', p_collection_id,
      'reason', btrim(p_reason)
    )
  );
  return jsonb_build_object('status', 'allocated', 'payment_id', payment_id);
end;
$$;

revoke execute on function public.admin_list_collect_payees(text, text, integer, integer, text)
  from public, anon;
revoke execute on function public.admin_list_collect_transactions(text, text, integer, integer, text)
  from public, anon;
revoke execute on function public.admin_get_collect_transaction(text)
  from public, anon;
revoke execute on function public.admin_list_collect_reconciliations(text, text, integer, integer, text)
  from public, anon;
revoke execute on function public.admin_list_collect_ledgers(text, text, integer, integer, text)
  from public, anon;
revoke execute on function public.admin_manual_allocate_payment(uuid, uuid, uuid, text)
  from public, anon;

grant execute on function public.admin_list_collect_payees(text, text, integer, integer, text)
  to authenticated;
grant execute on function public.admin_list_collect_transactions(text, text, integer, integer, text)
  to authenticated;
grant execute on function public.admin_get_collect_transaction(text)
  to authenticated;
grant execute on function public.admin_list_collect_reconciliations(text, text, integer, integer, text)
  to authenticated;
grant execute on function public.admin_list_collect_ledgers(text, text, integer, integer, text)
  to authenticated;
grant execute on function public.admin_manual_allocate_payment(uuid, uuid, uuid, text)
  to authenticated;

update public.admin_navigation_items
set enabled = false,
    updated_at = now(),
    updated_reason = 'Replaced by the consolidated Collect Operations model'
where key in (
  'payment_intents', 'transactions', 'sms_parsing', 'allocations',
  'exceptions', 'ledger', 'receivers', 'sms',
  'bank_details', 'bank_detail_approvals', 'bank_intents',
  'bank_transactions', 'bank_evidence', 'bank_reconciliation',
  'bank_exceptions', 'bank_allocations', 'bank_journal'
);

insert into public.admin_navigation_items
  (key, label, icon_key, route_path, required_permission, display_order, enabled, metadata)
values
  ('collect_payees', 'Payees', 'account_balance_wallet', '/admin/payees',
    'receivers.read', 38, true, '{"operations_model":"collect","rails":["rw_momo","diaspora_account"]}'),
  ('collect_transactions', 'Transactions', 'receipt_long', '/admin/transactions',
    'payments.read', 40, true, '{"operations_model":"collect","rails":["rw_momo","diaspora_account"]}'),
  ('collect_reconciliations', 'Reconciliations', 'fact_check', '/admin/reconciliations',
    'payment_events.read', 42, true, '{"operations_model":"collect","exceptions_only":true}'),
  ('collect_ledgers', 'Ledgers', 'balance', '/admin/ledgers',
    'ledger.read', 44, true, '{"operations_model":"collect","balanced_projection":true}')
on conflict (key) do update set
  label = excluded.label,
  icon_key = excluded.icon_key,
  route_path = excluded.route_path,
  required_permission = excluded.required_permission,
  display_order = excluded.display_order,
  enabled = excluded.enabled,
  metadata = excluded.metadata,
  updated_at = now(),
  updated_reason = 'Consolidated Collect Operations model';

update public.admin_queue_specs
set enabled = false,
    updated_at = now(),
    updated_reason = 'Replaced by the consolidated Collect Operations model'
where rpc_name in (
  'admin_list_payment_intents', 'admin_list_payments',
  'admin_list_payment_events', 'admin_list_allocations',
  'admin_list_unallocated', 'admin_list_ledger',
  'admin_list_receivers', 'admin_list_sms_metadata',
  'admin_list_bank_destinations', 'admin_list_bank_destination_change_requests',
  'admin_list_bank_transfer_intents', 'admin_list_bank_transactions',
  'admin_list_bank_evidence', 'admin_list_reconciliation_runs',
  'admin_list_reconciliation_exceptions',
  'admin_list_bank_allocation_requests', 'admin_list_journal_entries'
);

insert into public.admin_queue_specs
  (rpc_name, title, subtitle, required_permission, display_order, enabled, metadata)
values
  ('admin_list_collect_payees', 'Payees',
    'Rwanda MoMo receivers and diaspora account payees.',
    'receivers.read', 20, true, '{}'),
  ('admin_list_collect_transactions', 'Transactions',
    'Every received message with parsed payment and linked payee.',
    'payments.read', 22, true, '{"detail_rpc":"admin_get_collect_transaction"}'),
  ('admin_list_collect_reconciliations', 'Reconciliations',
    'Exceptions and received payments requiring allocation.',
    'payment_events.read', 24, true, '{"allocation_actions":true}'),
  ('admin_list_collect_ledgers', 'Ledgers',
    'Balanced Rwanda allocation and diaspora journal projections.',
    'ledger.read', 26, true, '{"double_entry":true}')
on conflict (rpc_name) do update set
  title = excluded.title,
  subtitle = excluded.subtitle,
  required_permission = excluded.required_permission,
  display_order = excluded.display_order,
  enabled = excluded.enabled,
  metadata = excluded.metadata,
  updated_at = now(),
  updated_reason = 'Consolidated Collect Operations model';

delete from public.admin_queue_filter_options
where rpc_name in (
  'admin_list_collect_payees', 'admin_list_collect_transactions',
  'admin_list_collect_reconciliations', 'admin_list_collect_ledgers'
);

insert into public.admin_queue_filter_options
  (rpc_name, filter_kind, value, label, display_order, enabled)
select rpc_name, 'sort', 'created_at_desc', 'Newest', 10, true
from public.admin_queue_specs
where rpc_name in (
  'admin_list_collect_payees', 'admin_list_collect_transactions',
  'admin_list_collect_reconciliations', 'admin_list_collect_ledgers'
)
union all
select rpc_name, 'sort', 'created_at_asc', 'Oldest', 20, true
from public.admin_queue_specs
where rpc_name in (
  'admin_list_collect_payees', 'admin_list_collect_transactions',
  'admin_list_collect_reconciliations', 'admin_list_collect_ledgers'
);

insert into public.admin_queue_filter_options
  (rpc_name, filter_kind, value, label, display_order, enabled)
values
  ('admin_list_collect_payees', 'status', '', 'All', 10, true),
  ('admin_list_collect_payees', 'status', 'active', 'Active', 20, true),
  ('admin_list_collect_transactions', 'status', '', 'All', 10, true),
  ('admin_list_collect_transactions', 'status', 'allocated', 'Allocated', 20, true),
  ('admin_list_collect_transactions', 'status', 'needs_review', 'Needs review', 30, true),
  ('admin_list_collect_reconciliations', 'status', '', 'All', 10, true),
  ('admin_list_collect_reconciliations', 'status', 'unallocated', 'Unallocated', 20, true),
  ('admin_list_collect_reconciliations', 'status', 'ambiguous', 'Ambiguous', 30, true),
  ('admin_list_collect_reconciliations', 'status', 'needs_review', 'Needs review', 40, true),
  ('admin_list_collect_ledgers', 'status', '', 'All', 10, true),
  ('admin_list_collect_ledgers', 'status', 'balanced', 'Balanced', 20, true),
  ('admin_list_collect_ledgers', 'status', 'exception', 'Exception', 30, true);

insert into public.admin_queue_sla_policies (queue_key, target, owner, escalation)
values
  ('admin_list_collect_payees', 'Review payee changes before accepting contributions',
    'Collect operations', 'Escalate any unverified payee route immediately'),
  ('admin_list_collect_transactions', 'Review failed parsing or unmatched receipts within 4 business hours',
    'Payments operations', 'Escalate duplicates or member-impacting delays the same day'),
  ('admin_list_collect_reconciliations', 'Clear allocation exceptions by the next business day',
    'Payments operations', 'Escalate unresolved variance without bypassing maker-checker controls'),
  ('admin_list_collect_ledgers', 'Review every unbalanced posting immediately',
    'Finance operations', 'Stop reconciliation closure until debit and credit totals agree')
on conflict (queue_key) do update set
  target = excluded.target,
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
    when 'admin_list_collect_payees' then perform public.assert_admin_permission('receivers.read');
    when 'admin_list_collect_transactions' then perform public.assert_admin_permission('payments.read');
    when 'admin_list_collect_reconciliations' then perform public.assert_admin_permission('payment_events.read');
    when 'admin_list_collect_ledgers' then perform public.assert_admin_permission('ledger.read');
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

  select * into policy_row
  from public.admin_queue_sla_policies
  where queue_key = normalized_queue_key;
  if not found then return '{}'::jsonb; end if;
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

insert into public.audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
values (
  null,
  'admin.operations_model.consolidated',
  'system_setting',
  null,
  '{"pages":["payees","transactions","reconciliations","ledgers"],"rails":["rw_momo","diaspora_account"]}'::jsonb
);

commit;
