require 'open3'
require 'json'
require 'timeout'

# Fixed, synthetic two-session Admin reversal race in the 136–138-migration local
# fixture. The synthetic owner approval/session is seeded separately.
ROOT = File.expand_path('../..', __dir__)
PROJECT = 'collect_fin_concurrency_qa_20260929'
CONTAINER = "supabase_db_#{PROJECT}"
WORKDIR = File.join(ROOT, '.cache/financial-concurrency-20260929')
PSQL = ['docker', 'exec', '-i', CONTAINER, 'psql', '-XqAt',
        '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'].freeze
REQUEST_ID = '99600000-0000-4000-8000-000000000601'
LOCK_KEY = "hashtextextended('hybrid-momo-reversal:#{REQUEST_ID}', 0)"
CLAIMS = '{"sub":"99100000-0000-4000-8000-000000000001","role":"authenticated","session_id":"99600000-0000-4000-8000-000000000901"}'
REASON = 'Synthetic provider dispute confirmed by operator'

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
abort('Reversal fixture provenance mismatch') unless
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
           where status = 'posted' and transaction_id = 'RACE2500') <> 1
       or (select count(*) from collect_hybrid.momo_journal_entries
           where entry_type = 'receipt') <> 1
       or (select count(*) from collect_hybrid.momo_journal_entries
           where entry_type = 'reversal') <> 0
       or (select count(*) from collect_hybrid.momo_reversal_requests) <> 0
       or (select count(*) from auth.sessions
           where id = '99600000-0000-4000-8000-000000000901') <> 1
       or (select count(*) from collect_admin_access.whatsapp_approvals
           where user_id = '99100000-0000-4000-8000-000000000001') <> 1 then
      raise exception 'Exact posted approved reversal fixture required';
    end if;
  end $$;
SQL
payment_id = query(<<~SQL)
  select id from public.payments
  where status = 'posted' and transaction_id = 'RACE2500';
SQL
abort('Posted synthetic payment ID missing') unless
  payment_id.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)

lock_input = nil
workers = []
blocked_workers = 0
responses = []
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

  %w[a b].each do |tag|
    input, output, error, thread = Open3.popen3(*PSQL)
    input.write(<<~SQL)
      set application_name = 'collect_f08_reversal_#{tag}';
      begin;
      set local role authenticated;
      select set_config('request.jwt.claims', '#{CLAIMS}', true);
      select 'RESULT:' || public.admin_reverse_momo_payment(
        '#{payment_id}',
        '#{REASON}', '#{REQUEST_ID}'
      )::text;
      commit;
    SQL
    input.close
    workers << { tag: tag, output: output, error: error, thread: thread }
  end

  80.times do
    blocked_workers = query(<<~SQL).to_i
      select count(*) from pg_stat_activity
      where application_name in ('collect_f08_reversal_a',
                                 'collect_f08_reversal_b')
        and wait_event_type = 'Lock' and wait_event = 'advisory';
    SQL
    break if blocked_workers == 2
    sleep 0.1
  end
  abort("Reversal workers did not overlap: #{blocked_workers}") unless
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
    abort("Reversal worker #{worker[:tag]} failed: #{error}") unless result.success?
    response_line = output.lines.find { |line| line.start_with?('RESULT:') }
    abort("Reversal worker #{worker[:tag]} produced no response") unless response_line
    responses << JSON.parse(response_line.delete_prefix('RESULT:'))
  end
  abort('Reversal idempotence responses differ') unless
    responses.map { |response| response['reversal_journal_entry_id'] }.uniq.length == 1 &&
    responses.map { |response| response['payment_id'] }.uniq.length == 1 &&
    responses.count { |response| response['replay'] == false } == 1 &&
    responses.count { |response| response['replay'] == true } == 1
ensure
  lock_input&.close unless lock_input&.closed?
end

post = query(<<~SQL)
  do $$ begin
    if (select count(*) from public.payments
        where status = 'reversed' and transaction_id = 'RACE2500') <> 1
       or (select count(*) from collect_hybrid.momo_reversal_requests
           where request_id = '#{REQUEST_ID}' and actor_id =
             '99100000-0000-4000-8000-000000000001') <> 1
       or (select count(*) from collect_hybrid.momo_journal_entries journal
           join public.payments payment on payment.id = journal.payment_id
           where payment.transaction_id = 'RACE2500'
             and journal.entry_type = 'reversal') <> 1
       or not exists (select 1 from collect_hybrid.momo_journal_lines line
           join collect_hybrid.momo_journal_entries journal
             on journal.id = line.journal_entry_id
           join public.payments payment on payment.id = journal.payment_id
           where payment.transaction_id = 'RACE2500'
             and journal.entry_type = 'reversal'
           group by journal.id
           having count(*) = 2
             and sum(line.amount_rwf) filter
               (where line.direction = 'debit') = 2500
             and sum(line.amount_rwf) filter
               (where line.direction = 'credit') = 2500)
       or (select count(*) from public.ledger_entries ledger
           join public.payments payment on payment.id = ledger.payment_id
           where payment.transaction_id = 'RACE2500'
             and ledger.amount_rwf = -2500
             and ledger.metadata->>'reversal_request_id' = '#{REQUEST_ID}') <> 2
       or (select count(*) from public.ledger_entries ledger
           join public.payments payment on payment.id = ledger.payment_id
           where payment.transaction_id = 'RACE2500'
             and ledger.amount_rwf = 2500) <> 2
       or (select balance.confirmed_rwf
           from collect_hybrid.collection_balances balance
           join public.payment_intents intent
             on intent.collection_id = balance.collection_id
           where intent.id = '99600000-0000-4000-8000-000000000301')
             is distinct from 0
       or (select count(*) from collect_hybrid.momo_balance_snapshots snapshot
           join public.payments payment on payment.id = snapshot.payment_id
           where payment.transaction_id = 'RACE2500'
             and snapshot.event_type = 'reversal'
             and snapshot.delta_rwf = -2500
             and snapshot.group_balance_after_rwf = 0) <> 1 then
      raise exception 'Concurrent compensating reversal failed';
    end if;
  end $$;
  select 'CONCURRENT_REVERSAL_PASS';
SQL
abort('Post-reversal verification missing') unless post == 'CONCURRENT_REVERSAL_PASS'

puts JSON.pretty_generate(
  status: 'pass',
  fixture: PROJECT,
  migration_count: query('select count(*) from supabase_migrations.schema_migrations;').to_i,
  blocked_workers_at_advisory_lock: blocked_workers,
  reversal_requests: 1,
  reversal_journals: 1,
  compensating_legacy_entries: 2,
  reversal_debit_rwf: 2500,
  reversal_credit_rwf: 2500,
  group_balance_after_rwf: 0,
  worker_fresh_count: responses.count { |response| response['replay'] == false },
  worker_replay_count: responses.count { |response| response['replay'] == true },
  provider_calls: 0,
  scope: 'synthetic approved local Admin session; no real provider reversal'
)
