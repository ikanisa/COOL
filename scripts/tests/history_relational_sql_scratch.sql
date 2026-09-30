\set ON_ERROR_STOP on
begin;

create function pg_temp.assert_true(ok boolean, label text)
returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
end;
$$;

insert into public.collections(id,title,readable_by) values
  ('30000000-0000-4000-8000-000000000001','Synthetic group',
    'aaaaaaaa-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000002','Secret group',
    'aaaaaaaa-0000-4000-8000-000000000002');

insert into public.payments(id,collection_id,contributor_user_id,amount_rwf,
  posted_at,transaction_id,anonymity_choice,contributor_public_id,status,currency)
select ('10000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  '30000000-0000-4000-8000-000000000001',
  case when n % 2 = 1 then 'aaaaaaaa-0000-4000-8000-000000000001'::uuid
    else 'aaaaaaaa-0000-4000-8000-000000000002'::uuid end,
  (n % 7 + 1) * 100,
  '2026-09-01 00:00:00+00'::timestamptz + (n / 3) * interval '1 minute',
  'TX-' || lpad(n::text,6,'0'),
  case when n % 4 = 0 then 'public_id' else 'anonymous' end,
  case when n % 4 = 0 then '123456' end,
  'posted','RWF'
from generate_series(1,120) n;

insert into public.payments(id,collection_id,contributor_user_id,amount_rwf,
  posted_at,transaction_id,anonymity_choice,status,currency) values
  ('10000000-0000-4000-8000-000000000121',
    '30000000-0000-4000-8000-000000000002',
    'aaaaaaaa-0000-4000-8000-000000000001',900,
    '2026-09-02 00:00:00+00','OWN-SECRET','anonymous','posted','RWF'),
  ('10000000-0000-4000-8000-000000000122',
    '30000000-0000-4000-8000-000000000002',
    'aaaaaaaa-0000-4000-8000-000000000002',900,
    '2026-09-02 00:00:00+00','PEER-SECRET','anonymous','posted','RWF'),
  ('10000000-0000-4000-8000-000000000123',
    '30000000-0000-4000-8000-000000000001',
    'aaaaaaaa-0000-4000-8000-000000000001',900,
    null,'UNPOSTED','anonymous','review','RWF'),
  ('10000000-0000-4000-8000-000000000124',
    '30000000-0000-4000-8000-000000000001',
    'aaaaaaaa-0000-4000-8000-000000000001',900,
    '2026-09-02 00:00:00+00','FOREIGN','anonymous','posted','EUR');

insert into public.collection_receivers(id,collection_id,momo_number_hash,
  momo_number,label,network,created_at) values
  ('40000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001','hash-a',
    '250788000001','Current','mtn_momo','2026-09-01 00:00:00+00'),
  ('40000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000001','hash-a',
    '250788000000','Historical','mtn_momo','2026-08-01 00:00:00+00');

insert into public.payment_intents(id,collection_id,contributor_user_id,
  expected_amount_rwf,receiver_momo_number_hash,status,created_at,expires_at)
select ('20000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  '30000000-0000-4000-8000-000000000001',
  'aaaaaaaa-0000-4000-8000-000000000001',100,'hash-a',
  case when n <= 3 then 'pending' else 'matched' end,
  now() - (60 - n) * interval '1 minute',
  case when n = 1 then now() - interval '1 hour'
    else now() + interval '1 day' end
from generate_series(1,60) n;
insert into public.payment_intents(id,collection_id,contributor_user_id,
  expected_amount_rwf,receiver_momo_number_hash,status,created_at,expires_at)
values ('20000000-0000-4000-8000-000000000061',
  '30000000-0000-4000-8000-000000000001',
  'aaaaaaaa-0000-4000-8000-000000000002',100,'hash-a',
  'pending',now(),now()+interval '1 day');

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}',
  true);

do $$
declare
  sort_mode text;
  expected jsonb;
  observed jsonb;
  page jsonb;
  cursor_value jsonb;
  original_revision text;
  iteration integer;
  intent_page jsonb;
  failed boolean;
begin
  for sort_mode in select unnest(array['newest','oldest','highest','lowest']) loop
    select coalesce(jsonb_agg('momo:' || payment.id order by
      case when sort_mode = 'highest' then payment.amount_rwf end desc,
      case when sort_mode = 'lowest' then payment.amount_rwf end,
      case when sort_mode = 'oldest' then payment.posted_at end,
      case when sort_mode <> 'oldest' then payment.posted_at end desc,
      payment.id), '[]'::jsonb)
    into expected
    from public.payments payment
    where payment.status = 'posted' and payment.currency = 'RWF'
      and (payment.collection_id = '30000000-0000-4000-8000-000000000001'
        or payment.contributor_user_id = auth.uid());

    observed := '[]'::jsonb;
    cursor_value := null;
    original_revision := null;
    for iteration in 1..15 loop
      page := collect_member_actions.history_page(null,'',sort_mode,cursor_value,13);
      perform pg_temp.assert_true(page->>'total_count' = '121',
        sort_mode || ' complete count');
      perform pg_temp.assert_true((page->'totals'->>'RWF')::bigint =
        (select sum(amount_rwf) from public.payments
          where status = 'posted' and currency = 'RWF'
            and (collection_id = '30000000-0000-4000-8000-000000000001'
              or contributor_user_id = auth.uid())),
        sort_mode || ' complete total');
      perform pg_temp.assert_true((page->'own_totals'->>'RWF')::bigint =
        (select sum(amount_rwf) from public.payments
          where status = 'posted' and currency = 'RWF'
            and contributor_user_id = auth.uid()),
        sort_mode || ' complete own total');
      perform pg_temp.assert_true(page->'own_collection_ids' =
        '["30000000-0000-4000-8000-000000000001", "30000000-0000-4000-8000-000000000002"]'::jsonb,
        sort_mode || ' complete own group IDs');
      perform pg_temp.assert_true(jsonb_array_length(page->'items') between 1 and 13,
        sort_mode || ' bounded page');
      if original_revision is null then original_revision := page->>'revision'; end if;
      perform pg_temp.assert_true(page->>'revision' = original_revision,
        sort_mode || ' stable revision');
      observed := observed || (select coalesce(jsonb_agg(item->>'payment_id'
        order by ordinality), '[]'::jsonb)
        from jsonb_array_elements(page->'items') with ordinality e(item,ordinality));
      cursor_value := page->'next_cursor';
      exit when cursor_value = 'null'::jsonb;
    end loop;
    perform pg_temp.assert_true(cursor_value = 'null'::jsonb,
      sort_mode || ' reaches terminal page');
    perform pg_temp.assert_true(observed = expected,
      sort_mode || ' keyset sequence and ties');
  end loop;

  page := collect_member_actions.history_page(
    '30000000-0000-4000-8000-000000000002', '', 'newest', null, 50);
  perform pg_temp.assert_true(page->>'total_count' = '1'
    and page->'items'->0->>'transaction_id' = 'OWN-SECRET',
    'own contribution survives private group restriction without peer leak');
  page := collect_member_actions.history_page(null,'secret group','newest',null,50);
  perform pg_temp.assert_true(page->>'total_count' = '0',
    'unreadable group title is not searchable');
  page := collect_member_actions.history_page(null,'TX-000002','newest',null,50);
  perform pg_temp.assert_true(page->>'total_count' = '0',
    'peer transaction reference is not searchable');
  page := collect_member_actions.history_page(null,'TX-000001','newest',null,50);
  perform pg_temp.assert_true(page->>'total_count' = '1',
    'own transaction reference is searchable');
  page := collect_member_actions.history_page(null,'synthetic group','newest',null,50);
  perform pg_temp.assert_true(page->>'total_count' = '120',
    'readable group title search includes complete match set');

  page := collect_member_actions.history_page(null,'','newest',null,13);
  failed := false;
  begin
    perform collect_member_actions.history_page(null,'','newest',
      jsonb_build_object('revision',repeat('f',32),
        'after',page->'next_cursor'->>'after'),13);
  exception when sqlstate 'P0001' then failed := true;
  end;
  perform pg_temp.assert_true(failed, 'tampered revision rejected');

  intent_page := collect_member_actions.recent_intents(null);
  perform pg_temp.assert_true(jsonb_array_length(intent_page->'items') = 50,
    'recent intent JSON limited at source');
  perform pg_temp.assert_true(intent_page->>'pending_count' = '2',
    'pending count excludes expired and other actors');
  perform pg_temp.assert_true(intent_page->'items'->0->>'id' =
    '20000000-0000-4000-8000-000000000060',
    'recent intents preserve newest order');
  perform pg_temp.assert_true(intent_page->'items'->0->>'receiver_label' = 'Current',
    'receiver lookup preserves latest historical match');
  intent_page := collect_member_actions.recent_intents(
    '20000000-0000-4000-8000-000000000001');
  perform pg_temp.assert_true(jsonb_array_length(intent_page->'items') = 1
    and intent_page->'items'->0->>'status' = 'expired'
    and intent_page->>'pending_count' = '2',
    'old exact ID resolves with derived expiry');
  intent_page := collect_member_actions.recent_intents(
    '20000000-0000-4000-8000-000000000061');
  perform pg_temp.assert_true(intent_page->'items' = '[]'::jsonb,
    'other actor intent is not exposed');

  page := collect_member_actions.history_page(null,'','newest',null,13);
  update public.payments set anonymity_choice = 'anonymous'
  where id = '10000000-0000-4000-8000-000000000004';
  failed := false;
  begin
    perform collect_member_actions.history_page(null,'','newest',
      page->'next_cursor',13);
  exception when sqlstate 'P0001' then failed := true;
  end;
  perform pg_temp.assert_true(failed, 'privacy change invalidates continuation');

  page := collect_member_actions.history_page(null,'','newest',null,13);
  update public.collections set readable_by =
    'aaaaaaaa-0000-4000-8000-000000000002'
  where id = '30000000-0000-4000-8000-000000000001';
  failed := false;
  begin
    perform collect_member_actions.history_page(null,'','newest',
      page->'next_cursor',13);
  exception when sqlstate 'P0001' then failed := true;
  end;
  perform pg_temp.assert_true(failed, 'permission change invalidates continuation');
end;
$$;

do $$
begin
  begin
    insert into public.payments(id,collection_id,contributor_user_id,
      amount_rwf,posted_at,anonymity_choice,status,currency)
    values ('10000000-0000-4000-8000-000000000125',
      '30000000-0000-4000-8000-000000000001',
      'aaaaaaaa-0000-4000-8000-000000000001',100,null,
      'anonymous','posted','RWF');
    raise exception 'Null posting instant accepted';
  exception when check_violation then null;
  end;
end;
$$;

select pg_temp.assert_true(not has_function_privilege('anon',
  'collect_member_actions.history_page(uuid,text,text,jsonb,integer)', 'EXECUTE'),
  'anonymous cannot execute history helper');
select pg_temp.assert_true(not has_function_privilege('anon',
  'collect_member_actions.recent_intents(uuid)', 'EXECUTE'),
  'anonymous cannot execute recent intent helper');
set local role authenticated;
select pg_temp.assert_true(collect_member_actions.history_page(
  null,'','newest',null,50)->>'total_count' = '61',
  'authenticated caller receives only own rows after permission loss');
select set_config('request.jwt.claims','{}',true);
do $$
begin
  perform collect_member_actions.recent_intents(null);
  raise exception 'Missing identity accepted';
exception when sqlstate '28000' then null;
end;
$$;
reset role;

select 'HISTORY_RELATIONAL_SCRATCH_PASS';
rollback;
