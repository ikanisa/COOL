require 'open3'
require 'json'
require 'timeout'

same_confirmation_conflict = !!ARGV.delete('--same-confirmation-conflict')
abort('Unknown argument') unless ARGV.empty?

# Two distinct synthetic provider confirmations race for the same review
# payment. Exactly one may post; the conflicting request must roll back.
ROOT = File.expand_path('../..', __dir__)
PROJECT = 'collect_fin_concurrency_qa_20260929'
CONTAINER = "supabase_db_#{PROJECT}"
WORKDIR = File.join(ROOT, '.cache/financial-concurrency-20260929')
PSQL = ['docker', 'exec', '-i', CONTAINER, 'psql', '-XqAt',
        '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'].freeze

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
abort('Conflict fixture provenance mismatch') unless
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
       or (select count(*) from public.provider_finality_requests) <> 0
       or (select count(*) from public.payment_provider_confirmations) <> 0
       or (select count(*) from public.ledger_entries) <> 0
       or (select count(*) from collect_hybrid.momo_journal_entries) <> 0 then
      raise exception 'Exact synthetic pre-conflict state required';
    end if;
  end $$;
SQL

payment_id = query("select id from public.payments where transaction_id = 'RACE2500';")
abort('Review payment ID missing') unless
  payment_id.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
lock_key = "hashtextextended('provider-finality-payment:' || '#{payment_id}', 0)"
lock_input = nil
workers = []
worker_states = []
results = []
begin
  lock_input, lock_output, lock_error, lock_thread = Open3.popen3(*PSQL)
  lock_input.write("select pg_advisory_lock(#{lock_key});\n\\echo LOCK_HELD\n")
  lock_input.flush
  Timeout.timeout(15) do
    loop do
      line = lock_output.gets
      abort("Lock session exited: #{lock_error.read}") if line.nil?
      break if line.strip == 'LOCK_HELD'
    end
  end

  %w[a b].each_with_index do |tag, index|
    input, output, error, thread = Open3.popen3(*PSQL)
    input.write("set application_name = 'collect_f08_conflict_#{tag}';\n\\echo WORKER_READY\n")
    input.flush
    Timeout.timeout(15) do
      loop do
        line = output.gets
        abort("Conflict worker #{tag} exited before ready: #{error.read}") if line.nil?
        break if line.strip == 'WORKER_READY'
      end
    end
    workers << { tag: tag, input: input, output: output, error: error,
                 thread: thread, index: index }
  end

  workers.each do |worker|
    suffix = same_confirmation_conflict ? 'SAME' : worker[:tag].upcase
    digest_character = worker[:index].zero? ? 'a' : 'b'
    worker[:input].write(<<~SQL)
      begin;
      set local role service_role;
      select set_config('request.jwt.claims', '{"role":"service_role"}', true);
      select 'RESULT:' || public.process_provider_finality_event(
        '99600000-0000-4000-8000-00000000051#{worker[:index] + 1}',
        'payment.confirmed', repeat('#{digest_character}', 64),
        '#{payment_id}', 'mtn_momo', 'RACE2500',
        'CONFIRM-RACE2500-#{suffix}',
        (select receiver_momo_number_hash from public.payments
          where id = '#{payment_id}'),
        2500, '2026-09-29 00:00:00+00'::timestamptz, repeat('#{digest_character}', 64), null, null
      )::text;
      commit;
    SQL
    worker[:input].close
  end

  80.times do
    worker_states = JSON.parse(query(<<~SQL))
      select coalesce(json_agg(json_build_object(
        'name', application_name, 'wait_type', wait_event_type,
        'wait_event', wait_event) order by application_name), '[]'::json)::text
      from pg_stat_activity
      where application_name in ('collect_f08_conflict_a',
                                 'collect_f08_conflict_b');
    SQL
    break if worker_states.length == 2 &&
             worker_states.all? { |worker| worker['wait_type'] == 'Lock' &&
                                   worker['wait_event'] == 'advisory' }
    sleep 0.1
  end
  abort("Conflict workers did not overlap: #{worker_states.inspect}") unless
    worker_states.length == 2 &&
    worker_states.all? { |worker| worker['wait_type'] == 'Lock' &&
                          worker['wait_event'] == 'advisory' }

  lock_input.write("select pg_advisory_unlock(#{lock_key});\n\\echo LOCK_RELEASED\n")
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
    results << { tag: worker[:tag], output: output, error: error,
                 exit_code: result.exitstatus }
  end
ensure
  lock_input&.close unless lock_input&.closed?
end

successes = results.select { |result| result[:exit_code] == 0 }
conflicts = results.select do |result|
  result[:exit_code] != 0 &&
    result[:error].include?('Payment was already finalized by a different confirmation')
end
abort('Expected one successful confirmation and one rejected conflict') unless
  successes.length == 1 && conflicts.length == 1 && results.length == 2 &&
  successes.first[:output].lines.any? { |line| line.start_with?('RESULT:') }

winner_confirmation = query(<<~SQL)
  select provider_confirmation_id
  from public.payment_provider_confirmations
  where payment_id = '#{payment_id}';
SQL
expected_confirmations = same_confirmation_conflict ? ['CONFIRM-RACE2500-SAME'] :
  %w[CONFIRM-RACE2500-A CONFIRM-RACE2500-B]
abort('Unknown winning provider confirmation') unless
  expected_confirmations.include?(winner_confirmation)

post = query(<<~SQL)
  do $$ begin
    if (select count(*) from public.payments
        where id = '#{payment_id}' and status = 'posted') <> 1
       or (select count(*) from public.provider_finality_requests
           where payment_id = '#{payment_id}' and status = 'processed') <> 1
       or (select count(*) from public.provider_finality_requests
           where payment_id = '#{payment_id}' and status = 'processing') <> 0
       or (select count(*) from public.payment_provider_confirmations
           where payment_id = '#{payment_id}') <> 1
       or (select count(*) from public.ledger_entries
           where payment_id = '#{payment_id}' and amount_rwf = 2500) <> 2
       or (select count(*) from collect_hybrid.momo_journal_entries
           where payment_id = '#{payment_id}' and entry_type = 'receipt') <> 1
       or not exists (select 1 from collect_hybrid.momo_journal_lines line
           join collect_hybrid.momo_journal_entries journal
             on journal.id = line.journal_entry_id
           where journal.payment_id = '#{payment_id}' and journal.entry_type = 'receipt'
           group by journal.id
           having count(*) = 2
             and sum(line.amount_rwf) filter (where line.direction = 'debit') = 2500
             and sum(line.amount_rwf) filter (where line.direction = 'credit') = 2500)
       or (select confirmed_rwf from collect_hybrid.collection_balances balance
           join public.payments payment on payment.collection_id = balance.collection_id
           where payment.id = '#{payment_id}') is distinct from 2500 then
      raise exception 'Conflicting provider finality accounting failed';
    end if;
  end $$;
  select 'CONFLICT_FINALITY_PASS';
SQL
abort('Conflict postcondition missing') unless post == 'CONFLICT_FINALITY_PASS'

puts JSON.pretty_generate(
  status: 'pass', fixture: PROJECT, migration_count: query('select count(*) from supabase_migrations.schema_migrations;').to_i,
  conflict_kind: same_confirmation_conflict ? 'same confirmation, different evidence' : 'different confirmation',
  blocked_workers_at_payment_advisory_lock: 2,
  successful_confirmations: 1, rejected_conflicts: 1,
  winning_provider_confirmation: winner_confirmation,
  processed_requests: 1, processing_requests: 0,
  provider_confirmation_rows: 1, posted_payments: 1,
  legacy_ledger_entries: 2, balanced_receipt_journals: 1,
  confirmed_group_balance_rwf: 2500,
  provider_calls: 0,
  scope: 'synthetic service-role conflict; no authenticated provider delivery'
)
