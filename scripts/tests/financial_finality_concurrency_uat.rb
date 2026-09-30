require 'open3'
require 'json'
require 'timeout'

# Two distinct synthetic provider request IDs race to confirm the one review
# candidate. The fixture and provider fields are fixed; no real provider call.
ROOT = File.expand_path('../..', __dir__)
PROJECT = 'collect_fin_concurrency_qa_20260929'
CONTAINER = "supabase_db_#{PROJECT}"
WORKDIR = File.join(ROOT, '.cache/financial-concurrency-20260929')
PSQL = ['docker', 'exec', '-i', CONTAINER, 'psql', '-XqAt',
        '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'].freeze
LOCK_KEY = "hashtextextended('mtn_momo:RACE2500', 0)"

def query(sql)
  output, error, result = Open3.capture3(*PSQL, stdin_data: sql)
  abort(error.empty? ? output : error) unless result.success?
  output.strip
end

labels_raw, labels_error, labels_status = Open3.capture3(
  'docker', 'inspect', CONTAINER, '--format', '{{json .Config.Labels}}'
)
abort(labels_error) unless labels_status.success?
labels = JSON.parse(labels_raw)
ports_raw, ports_error, ports_status = Open3.capture3(
  'docker', 'inspect', CONTAINER, '--format', '{{json .HostConfig.PortBindings}}'
)
abort(ports_error) unless ports_status.success?
ports = JSON.parse(ports_raw)
config = File.read(File.join(WORKDIR, 'supabase/config.toml'))
abort('Finality fixture provenance mismatch') unless
  labels['com.supabase.cli.project'] == PROJECT &&
  labels['com.docker.compose.project'] == PROJECT &&
  config.match?(/^project_id = "#{PROJECT}"$/) &&
  config.match?(/^port = 55722$/) &&
  ports.dig('5432/tcp', 0, 'HostPort') == '55722'

query(<<~SQL)
  do $$ begin
    if current_database() <> 'postgres'
       or (select count(*) from supabase_migrations.schema_migrations) <>
       (case (select max(version) from supabase_migrations.schema_migrations)
         when '20260929130000' then 136
         when '20260929140000' then 137
         when '20260929150000' then 138
         else -1 end)
       or (select count(*) from public.payments
           where status = 'review' and provider_network = 'mtn_momo'
             and transaction_id = 'RACE2500' and amount_rwf = 2500) <> 1
       or (select count(*) from public.parsed_payment_events
           where transaction_id = 'RACE2500'
             and allocation_status = 'ignored') <> 1
       or (select count(*) from public.payment_provider_confirmations) <> 0
       or (select count(*) from public.provider_finality_requests) <> 0
       or (select count(*) from public.ledger_entries) <> 0
       or (select count(*) from collect_hybrid.momo_journal_entries) <> 0 then
      raise exception 'Exact synthetic pre-finality race state required';
    end if;
  end $$;
SQL

lock_input = nil
workers = []
wait_events = []
responses = []
worker_states = []
begin
  lock_input, lock_output, lock_error, lock_thread = Open3.popen3(*PSQL)
  lock_input.write("select pg_advisory_lock(#{LOCK_KEY});\n\\echo LOCK_HELD\n")
  lock_input.flush
  Timeout.timeout(15) do
    loop do
      line = lock_output.gets
      abort("Lock session exited: #{lock_error.read}") if line.nil?
      break if line.strip == 'LOCK_HELD'
    end
  end

  %w[a b].each_with_index do |tag, index|
    request_id = "99600000-0000-4000-8000-00000000050#{index + 1}"
    input, output, error, thread = Open3.popen3(*PSQL)
    input.write("set application_name = 'collect_f08_finality_#{tag}';\n\\echo WORKER_READY\n")
    input.flush
    Timeout.timeout(15) do
      loop do
        line = output.gets
        abort("Finality worker #{tag} exited before ready: #{error.read}") if line.nil?
        break if line.strip == 'WORKER_READY'
      end
    end
    workers << { tag: tag, input: input, output: output, error: error, thread: thread,
                 request_id: request_id }
  end

  # Both database sessions exist before either enters the financial function.
  # The parent still holds the provider-reference lock until both are observed
  # waiting, so process startup cannot be mistaken for a failed overlap.
  workers.each do |worker|
    worker[:input].write(<<~SQL)
      begin;
      set local role service_role;
      select set_config('request.jwt.claims', '{"role":"service_role"}', true);
      select 'RESULT:' || public.process_provider_finality_event(
        '#{worker[:request_id]}', 'payment.confirmed', repeat('d', 64),
        (select id from public.payments where transaction_id = 'RACE2500'),
        'mtn_momo', 'RACE2500', 'CONFIRM-RACE2500',
        (select receiver_momo_number_hash from public.payments
          where transaction_id = 'RACE2500'),
        2500, '2026-09-29 00:00:00+00'::timestamptz, repeat('e', 64), null, null
      )::text;
      commit;
    SQL
    worker[:input].close
  end

  80.times do
    worker_states = JSON.parse(query(<<~SQL))
      select coalesce(json_agg(json_build_object(
        'name', application_name, 'state', state,
        'wait_type', wait_event_type, 'wait_event', wait_event)
        order by application_name), '[]'::json)::text
      from pg_stat_activity
      where application_name in ('collect_f08_finality_a',
                                 'collect_f08_finality_b');
    SQL
    wait_events = worker_states.map do |worker|
      worker['wait_event'] if worker['wait_type'] == 'Lock'
    end.compact
    break if worker_states.length == 2 && wait_events.length == 2 &&
             wait_events.include?('advisory')
    sleep 0.1
  end
  abort("Finality workers did not overlap at locks: #{worker_states.inspect}") unless
    worker_states.length == 2 && wait_events.length == 2 &&
    wait_events.include?('advisory')

  lock_input.write("select pg_advisory_unlock(#{LOCK_KEY});\n\\echo LOCK_RELEASED\n")
  lock_input.close
  Timeout.timeout(15) { abort('Lock release failed') unless lock_thread.value.success? }
  abort('Lock release marker absent') unless lock_output.read.include?('LOCK_RELEASED')
  lock_stderr = lock_error.read
  abort(lock_stderr) unless lock_stderr.empty?

  workers.each do |worker|
    output = nil
    error = nil
    result = nil
    Timeout.timeout(30) do
      output = worker[:output].read
      error = worker[:error].read
      result = worker[:thread].value
    end
    abort("Finality worker #{worker[:tag]} failed: #{error}") unless result.success?
    response_line = output.lines.find { |line| line.start_with?('RESULT:') }
    abort("Finality worker #{worker[:tag]} produced no response") unless response_line
    responses << JSON.parse(response_line.delete_prefix('RESULT:'))
  end
  abort('Finality workers did not return one payment ID') unless
    responses.map { |response| response['payment_id'] }.uniq.length == 1 &&
    responses.all? { |response| response['replayed'] == false }
ensure
  lock_input&.close unless lock_input&.closed?
end

post = query(<<~SQL)
  do $$ begin
    if (select count(*) from public.payments
        where provider_network = 'mtn_momo' and transaction_id = 'RACE2500'
          and status = 'posted' and amount_rwf = 2500) <> 1
       or (select count(*) from public.provider_finality_requests
           where event_type = 'payment.confirmed' and status = 'processed'
             and provider_reference = 'CONFIRM-RACE2500') <> 2
       or (select count(*) from public.payment_provider_confirmations
           where provider_confirmation_id = 'CONFIRM-RACE2500') <> 1
       or (select count(*) from public.ledger_entries ledger
           join public.payments payment on payment.id = ledger.payment_id
           where payment.transaction_id = 'RACE2500') <> 2
       or (select count(*) from collect_hybrid.momo_journal_entries journal
           join public.payments payment on payment.id = journal.payment_id
           where payment.transaction_id = 'RACE2500'
             and journal.entry_type = 'receipt') <> 1
       or not exists (select 1
           from collect_hybrid.momo_journal_lines line
           join collect_hybrid.momo_journal_entries journal
             on journal.id = line.journal_entry_id
           join public.payments payment on payment.id = journal.payment_id
           where payment.transaction_id = 'RACE2500'
           group by journal.id
           having count(*) = 2
             and sum(line.amount_rwf) filter
               (where line.direction = 'debit') = 2500
             and sum(line.amount_rwf) filter
               (where line.direction = 'credit') = 2500)
       or (select balance.confirmed_rwf
           from collect_hybrid.collection_balances balance
           join public.payment_intents intent
             on intent.collection_id = balance.collection_id
           where intent.id = '99600000-0000-4000-8000-000000000301')
             is distinct from 2500 then
      raise exception 'Concurrent finality accounting failed';
    end if;
  end $$;
  select 'CONCURRENT_FINALITY_PASS';
SQL
abort('Post-finality verification missing') unless post == 'CONCURRENT_FINALITY_PASS'

# Same request ID and payload returns a replay marker after both workers commit.
replay = query(<<~SQL)
  begin;
  set local role service_role;
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
  select public.process_provider_finality_event(
    '99600000-0000-4000-8000-000000000501',
    'payment.confirmed', repeat('d', 64),
    (select id from public.payments where transaction_id = 'RACE2500'),
    'mtn_momo', 'RACE2500', 'CONFIRM-RACE2500',
    (select receiver_momo_number_hash from public.payments
      where transaction_id = 'RACE2500'),
    2500, '2026-09-29 00:00:00+00'::timestamptz, repeat('e', 64), null, null
  )->>'replayed';
  commit;
SQL
abort('Same provider request did not report replay') unless replay.lines.last == 'true'

puts JSON.pretty_generate(
  status: 'pass',
  fixture: PROJECT,
  migration_count: query('select count(*) from supabase_migrations.schema_migrations;').to_i,
  blocked_workers: 2,
  observed_wait_events: wait_events.sort,
  processed_request_ids: 2,
  provider_confirmation_rows: 1,
  posted_payments_for_reference: 1,
  legacy_ledger_entries: 2,
  canonical_receipt_journals: 1,
  canonical_debit_rwf: 2500,
  canonical_credit_rwf: 2500,
  confirmed_group_balance_rwf: 2500,
  identical_request_replayed: true,
  provider_calls: 0,
  scope: 'synthetic service-role gateway; real provider evidence not exercised'
)
