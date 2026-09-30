require 'open3'
require 'json'
require 'timeout'
require 'time'

# The test is intentionally fixed to the isolated, synthetic 136–138-migration
# Supabase CLI fixture. No database URL, container or payer ID is accepted.
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
abort('Concurrency fixture provenance mismatch') unless
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
       or (select count(*) from auth.users) <> 2
       or (select count(*) from public.payment_intents) <> 1
       or (select count(*) from public.raw_payment_sms) <> 2
       or (select count(*) from public.parsed_payment_events
           where transaction_id = 'RACE2500') <> 2
       or (select count(*) from public.payments) <> 0 then
      raise exception 'Exact committed synthetic race seed required';
    end if;
  end $$;
SQL

lock_input = nil
workers = []
blocked_workers = 0
worker_results = []
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
    event_id = "99600000-0000-4000-8000-00000000021#{index + 1}"
    input, output, error, thread = Open3.popen3(*PSQL)
    input.write(<<~SQL)
      set application_name = 'collect_f08_worker_#{tag}';
      begin;
      set local role service_role;
      select set_config('request.jwt.claims', '{"role":"service_role"}', true);
      select 'RESULT:' || public.allocate_parsed_payment_event('#{event_id}');
      commit;
    SQL
    input.close
    workers << { tag: tag, output: output, error: error, thread: thread }
  end

  80.times do
    blocked_workers = query(<<~SQL).to_i
      select count(*) from pg_stat_activity
      where application_name in ('collect_f08_worker_a', 'collect_f08_worker_b')
        and wait_event_type = 'Lock' and wait_event = 'advisory';
    SQL
    break if blocked_workers == 2
    sleep 0.1
  end
  abort("Workers did not overlap at advisory lock: #{blocked_workers}") unless
    blocked_workers == 2

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
    abort("Worker #{worker[:tag]} failed: #{error}") unless result.success?
    outcome = output.lines.find { |line| line.start_with?('RESULT:') }
    abort("Worker #{worker[:tag]} produced no result") unless outcome
    worker_results << outcome.delete_prefix('RESULT:').strip
  end
  abort("Unexpected worker results: #{worker_results.inspect}") unless
    worker_results.sort == %w[awaiting_provider_confirmation ignored]
ensure
  lock_input&.close unless lock_input&.closed?
end

post = query(<<~SQL)
  do $$ begin
    if (select count(*) from public.payments
        where provider_network = 'mtn_momo'
          and transaction_id = 'RACE2500' and status = 'review') <> 1
       or (select count(*) from public.parsed_payment_events
           where transaction_id = 'RACE2500'
             and allocation_status = 'needs_review') <> 1
       or (select count(*) from public.parsed_payment_events
           where transaction_id = 'RACE2500'
             and allocation_status = 'ignored') <> 1
       or (select status from public.payment_intents
           where id = '99600000-0000-4000-8000-000000000301') <> 'matched'
       or exists (select 1 from public.ledger_entries ledger
           join public.payments payment on payment.id = ledger.payment_id
           where payment.transaction_id = 'RACE2500')
       or exists (select 1 from collect_hybrid.momo_journal_entries journal
           join public.payments payment on payment.id = journal.payment_id
           where payment.transaction_id = 'RACE2500')
       or exists (select 1 from collect_hybrid.collection_balances balance
           join public.payment_intents intent
             on intent.collection_id = balance.collection_id
           where intent.id = '99600000-0000-4000-8000-000000000301'
             and balance.confirmed_rwf <> 0) then
      raise exception 'Concurrent duplicate boundary failed';
    end if;
  end $$;
  select 'CONCURRENT_DUPLICATE_PASS';
SQL
abort('Post-race verification missing') unless post == 'CONCURRENT_DUPLICATE_PASS'

puts JSON.pretty_generate(
  status: 'pass',
  fixture: PROJECT,
  migration_count: query('select count(*) from supabase_migrations.schema_migrations;').to_i,
  blocked_workers_at_advisory_lock: blocked_workers,
  worker_outcomes: worker_results.sort,
  review_payments_for_reference: 1,
  ignored_duplicate_events: 1,
  posted_payments_for_reference: 0,
  journal_entries_for_reference: 0,
  provider_calls: 0,
  scope: 'synthetic local Supabase fixture; real provider finality not exercised'
)
