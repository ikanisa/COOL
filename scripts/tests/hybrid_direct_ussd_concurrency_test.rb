require 'open3'
require 'json'

# Local-only disposable database cloned from the reviewed current-schema UAT
# source. It never accepts a URL, container name or production credential.
CONTAINER = 'supabase_db_collect'
SOURCE_DB = 'collect_hybrid_money_uat_20260903'
TEST_DB = 'collect_hybrid_concurrency_uat_20260903'
PSQL = %W[docker exec -i #{CONTAINER} psql -XqAt -U postgres -v ON_ERROR_STOP=1].freeze

def run!(*command, input: nil)
  output, error, status = Open3.capture3(*command, stdin_data: input)
  abort(error.empty? ? output : error) unless status.success?
  output
end

def sql(statement)
  run!(*PSQL, '-d', TEST_DB, input: statement)
end

def allocate(event_id)
  sql(<<~SQL).lines.map(&:strip).reject(&:empty?).last
    begin;
    set local role service_role;
    select set_config('request.jwt.claims','{"role":"service_role"}',true);
    select public.allocate_parsed_payment_event('#{event_id}');
    commit;
  SQL
end

def confirm(event_id, transaction_id, amount)
  payment_id = sql(
    "select id from public.payments where parsed_event_id='#{event_id}';",
  ).lines.map(&:strip).reject(&:empty?).last
  abort("Missing review payment for #{event_id}") if payment_id.to_s.empty?
  sql(<<~SQL).lines.map(&:strip).reject(&:empty?).last
    begin;
    set local role service_role;
    select set_config('request.jwt.claims','{"role":"service_role"}',true);
    select public.confirm_provider_payment(
      '#{payment_id}',
      'mtn_momo','#{transaction_id}','CONFIRM-#{transaction_id}',repeat('b',64),
      #{amount},now(),repeat('c',64)
    );
    commit;
  SQL
end

setup = <<~SQL
  set statement_timeout='30s';
  do $$ begin
    if current_database() <> '#{TEST_DB}'
       or to_regclass('collect_hybrid.momo_journal_entries') is null
       or exists(select 1 from public.payments)
       or exists(select 1 from public.raw_payment_sms) then
      raise exception 'Fresh isolated direct-USSD concurrency database required';
    end if;
  end $$;
  insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
  values('98000000-0000-4000-8000-000000000001','authenticated','authenticated',
    '250788980001',now(),'{}','{}');
  insert into public.collections(
    id,slug,creator_user_id,title,category,visibility,public_status,
    collection_type,contribution_visibility,allow_anonymous,diaspora_enabled,creation_origin
  ) values(
    '98000000-0000-4000-8000-000000000010','concurrency-direct-ussd',
    '98000000-0000-4000-8000-000000000001','Concurrency direct USSD',
    'Family / friends','private','private','ikimina','members',false,false,'admin_assisted'
  );
  insert into public.collection_members(collection_id,user_id,role,status)
  values('98000000-0000-4000-8000-000000000010',
    '98000000-0000-4000-8000-000000000001','owner','active');
  insert into collect_hybrid.member_records(id,collect_id,origin,created_by)
  values('98000000-0000-4000-8000-000000000020','880001','admin_assisted',
    '98000000-0000-4000-8000-000000000001');
  insert into collect_hybrid.member_momo_identities(member_id,member_name,momo_name,momo_number)
  values('98000000-0000-4000-8000-000000000020','CONCURRENT MEMBER',
    'CONCURRENT MEMBER','+250788980456');
  insert into public.collection_members(collection_id,member_record_id,role,status)
  values('98000000-0000-4000-8000-000000000010',
    '98000000-0000-4000-8000-000000000020','member','active');
  insert into public.collection_receivers(
    id,collection_id,receiver_user_id,momo_number,momo_number_hash,network,label,is_active
  ) values(
    '98000000-0000-4000-8000-000000000030',
    '98000000-0000-4000-8000-000000000010',
    '98000000-0000-4000-8000-000000000001','41258',repeat('b',64),
    'mtn_momo','Concurrency receiving route',true
  );
  insert into collect_hybrid.member_receiving_assignments(
    id,member_record_id,collection_id,collection_receiver_id,route_key,
    starts_at,reason,created_by
  ) values(
    '98000000-0000-4000-8000-000000000040',
    '98000000-0000-4000-8000-000000000020',
    '98000000-0000-4000-8000-000000000010',
    '98000000-0000-4000-8000-000000000030',repeat('0',64),
    now()-interval '1 minute','Synthetic concurrency route assignment',
    '98000000-0000-4000-8000-000000000001'
  );
  update public.feature_flags set enabled=true where key='hybrid_direct_ussd_allocation';
  insert into public.raw_payment_sms(
    id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,
    received_at_device,parse_status
  ) values
    ('98000000-0000-4000-8000-000000000101',
      '98000000-0000-4000-8000-000000000001','M-Money','concurrent receipt 100',
      encode(extensions.digest('concurrent receipt 100','sha256'),'hex'),repeat('b',64),now(),'parsed'),
    ('98000000-0000-4000-8000-000000000102',
      '98000000-0000-4000-8000-000000000001','M-Money','concurrent receipt 200',
      encode(extensions.digest('concurrent receipt 200','sha256'),'hex'),repeat('b',64),now(),'parsed'),
    ('98000000-0000-4000-8000-000000000103',
      '98000000-0000-4000-8000-000000000001','M-Money','same event receipt 500',
      encode(extensions.digest('same event receipt 500','sha256'),'hex'),repeat('b',64),now(),'parsed');
  insert into public.parsed_payment_events(
    id,raw_sms_id,receiver_user_id,is_mobile_money_payment,network,direction,
    amount_rwf,currency,transaction_id,receiver_phone_hash,confidence,payer_last3,
    payer_match_key,parser_schema_version
  ) select fixture.event_id,fixture.raw_id,
    '98000000-0000-4000-8000-000000000001',true,'mtn_momo','incoming',
    fixture.amount,'RWF',fixture.transaction_id,repeat('b',64),0.99,'456',
    identity.match_key,'collect.sms_parser.v4'
  from (values
    ('98000000-0000-4000-8000-000000000201'::uuid,
      '98000000-0000-4000-8000-000000000101'::uuid,100::bigint,'CONCURRENT100'::text),
    ('98000000-0000-4000-8000-000000000202'::uuid,
      '98000000-0000-4000-8000-000000000102'::uuid,200::bigint,'CONCURRENT200'::text),
    ('98000000-0000-4000-8000-000000000203'::uuid,
      '98000000-0000-4000-8000-000000000103'::uuid,500::bigint,'CONCURRENT500'::text)
  ) fixture(event_id,raw_id,amount,transaction_id)
  cross join collect_hybrid.member_momo_identities identity
  where identity.member_id='98000000-0000-4000-8000-000000000020';
SQL

begin
  run!('docker', 'exec', CONTAINER, 'sh', '-c',
    "PGPASSWORD=\"$POSTGRES_PASSWORD\" dropdb -U supabase_admin --if-exists --force #{TEST_DB}")
  run!('docker', 'exec', CONTAINER, 'sh', '-c',
    "PGPASSWORD=\"$POSTGRES_PASSWORD\" createdb -U supabase_admin --template #{SOURCE_DB} #{TEST_DB}")
  sql(setup)

  pair = %w[
    98000000-0000-4000-8000-000000000201
    98000000-0000-4000-8000-000000000202
  ].map { |id| Thread.new { allocate(id) } }.map(&:value).sort
  expected_pair = %w[awaiting_provider_confirmation awaiting_provider_confirmation]
  abort("Unexpected two-event results: #{pair.inspect}") unless pair == expected_pair

  unconfirmed_readback = JSON.parse(sql(<<~SQL))
    select jsonb_build_object(
      'review_payments',(select count(*) from public.payments where status='review'),
      'journals',(select count(*) from collect_hybrid.momo_journal_entries),
      'ledger_rows',(select count(*) from public.ledger_entries),
      'member_balances',(select count(*) from collect_hybrid.member_balances),
      'group_balances',(select count(*) from collect_hybrid.collection_balances)
    );
  SQL
  expected_unconfirmed = {
    'review_payments' => 2, 'journals' => 0, 'ledger_rows' => 0,
    'member_balances' => 0, 'group_balances' => 0
  }
  abort("Unconfirmed candidates changed financial state: #{unconfirmed_readback}") unless unconfirmed_readback == expected_unconfirmed

  confirmations = [
    ['98000000-0000-4000-8000-000000000201', 'CONCURRENT100', 100],
    ['98000000-0000-4000-8000-000000000202', 'CONCURRENT200', 200]
  ].map { |args| Thread.new { confirm(*args) } }.map(&:value)
  abort("Distinct confirmations failed: #{confirmations.inspect}") unless confirmations.uniq.length == 2

  two_event_readback = JSON.parse(sql(<<~SQL))
    select jsonb_build_object(
      'payments',(select count(*) from public.payments),
      'journals',(select count(*) from collect_hybrid.momo_journal_entries where entry_type='receipt'),
      'lines',(select count(*) from collect_hybrid.momo_journal_lines),
      'snapshots',(select count(*) from collect_hybrid.momo_balance_snapshots),
      'member_balance',(select confirmed_rwf from collect_hybrid.member_balances
        where member_record_id='98000000-0000-4000-8000-000000000020'),
      'group_balance',(select confirmed_rwf from collect_hybrid.collection_balances
        where collection_id='98000000-0000-4000-8000-000000000010'),
      'max_after',(select max(member_balance_after_rwf) from collect_hybrid.momo_balance_snapshots)
    );
  SQL
  expected = {
    'payments' => 2, 'journals' => 2, 'lines' => 4, 'snapshots' => 2,
    'member_balance' => 300, 'group_balance' => 300, 'max_after' => 300
  }
  abort("Two-event balance serialization failed: #{two_event_readback}") unless two_event_readback == expected

  same_event = Array.new(4) do
    Thread.new { allocate('98000000-0000-4000-8000-000000000203') }
  end.map(&:value).sort
  expected_results = Array.new(4, 'awaiting_provider_confirmation')
  abort("Unexpected same-event results: #{same_event.inspect}") unless same_event == expected_results

  same_confirmations = Array.new(4) do
    Thread.new do
      confirm('98000000-0000-4000-8000-000000000203', 'CONCURRENT500', 500)
    end
  end.map(&:value)
  abort("Same-event confirmation replay diverged: #{same_confirmations.inspect}") unless same_confirmations.uniq.length == 1
  post_confirmation_retry = allocate('98000000-0000-4000-8000-000000000203')
  abort("Confirmed event did not become allocated: #{post_confirmation_retry}") unless post_confirmation_retry == 'already_allocated'

  final_readback = JSON.parse(sql(<<~SQL))
    select jsonb_build_object(
      'same_event_payments',(select count(*) from public.payments
        where parsed_event_id='98000000-0000-4000-8000-000000000203'),
      'payments',(select count(*) from public.payments),
      'journals',(select count(*) from collect_hybrid.momo_journal_entries where entry_type='receipt'),
      'lines',(select count(*) from collect_hybrid.momo_journal_lines),
      'snapshots',(select count(*) from collect_hybrid.momo_balance_snapshots),
      'member_balance',(select confirmed_rwf from collect_hybrid.member_balances
        where member_record_id='98000000-0000-4000-8000-000000000020'),
      'group_balance',(select confirmed_rwf from collect_hybrid.collection_balances
        where collection_id='98000000-0000-4000-8000-000000000010')
    );
  SQL
  expected_final = {
    'same_event_payments' => 1, 'payments' => 3, 'journals' => 3,
    'lines' => 6, 'snapshots' => 3, 'member_balance' => 800,
    'group_balance' => 800
  }
  abort("Same-event idempotency failed: #{final_readback}") unless final_readback == expected_final

  puts JSON.pretty_generate(
    status: 'pass',
    database: TEST_DB,
    scope: 'local synthetic only; concurrent direct-USSD candidate creation, provider finalization, and balance serialization',
    two_event_results: pair,
    two_event_confirmations: confirmations,
    same_event_results: same_event,
    same_event_confirmations: same_confirmations,
    final_readback: final_readback
  )
ensure
  Open3.capture3('docker', 'exec', CONTAINER, 'sh', '-c',
    "PGPASSWORD=\"$POSTGRES_PASSWORD\" dropdb -U supabase_admin --if-exists --force #{TEST_DB}")
end
