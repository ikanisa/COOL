require 'open3'
require 'json'
require 'timeout'
require 'digest'

# Real overlapping SQL sessions in one exact, task-owned local fixture. The
# script never calls a provider. Synthetic users and notification rows are
# removed only after both worker connections have exited.
ROOT = File.expand_path('../..', __dir__)
PROJECT = 'collect_fin_concurrency_qa_20260929'
CONTAINER = "supabase_db_#{PROJECT}"
WORKDIR = File.join(ROOT, '.cache/financial-concurrency-20260929')
PSQL = ['docker', 'exec', '-i', CONTAINER, 'psql', '-XqAt',
        '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'].freeze
USER_A = '99860000-0000-4000-8000-000000000001'
USER_B = '99860000-0000-4000-8000-000000000002'
EVENT_ID = '99860000-0000-4000-8000-000000000020'
TOKEN = 'synthetic-concurrency-token-9986001'
WORKER_A = 'collect_o05_notification_claim_a'
WORKER_B = 'collect_o05_notification_claim_b'
MIGRATION = '20260929160000_notification_retry_schedule.sql'

def query(sql)
  output, error, status = Open3.capture3(*PSQL, stdin_data:
    "set statement_timeout = '20s';\nset timezone = 'UTC';\n#{sql}")
  raise(error.empty? ? output : error) unless status.success?
  output.strip
end

def fixture_digest
  query(<<~SQL)
    with rows(family, body) as (
      select 'auth_user', to_jsonb(t) from auth.users t
      union all select 'member_record', to_jsonb(t) from collect_hybrid.member_records t
      union all select 'profile', to_jsonb(t) from public.profiles t
      union all select 'notification_preference', to_jsonb(t) from public.notification_preferences t
      union all select 'notification_event', to_jsonb(t) from public.notification_events t
      union all select 'notification_device', to_jsonb(t) from public.notification_device_tokens t
      union all select 'notification_delivery', to_jsonb(t) from public.notification_deliveries t
      union all select 'notification_attempt', to_jsonb(t) from public.notification_delivery_attempts t
      union all select 'payment', to_jsonb(t) from public.payments t
      union all select 'provider_request', to_jsonb(t) from public.provider_finality_requests t
      union all select 'provider_confirmation', to_jsonb(t) from public.payment_provider_confirmations t
      union all select 'provider_rejection', to_jsonb(t) from collect_hybrid.payment_provider_rejections t
      union all select 'ledger', to_jsonb(t) from public.ledger_entries t
      union all select 'journal', to_jsonb(t) from collect_hybrid.momo_journal_entries t
      union all select 'journal_line', to_jsonb(t) from collect_hybrid.momo_journal_lines t
      union all select 'balance_snapshot', to_jsonb(t) from collect_hybrid.momo_balance_snapshots t
      union all select 'collection_balance', to_jsonb(t) from collect_hybrid.collection_balances t
      union all select 'member_balance', to_jsonb(t) from collect_hybrid.member_balances t
      union all select 'audit', to_jsonb(t) from public.audit_logs t
    )
    select encode(extensions.digest(coalesce(string_agg(
      family || ':' || body::text, E'\n' order by family, body::text), ''), 'sha256'), 'hex')
    from rows;
  SQL
end

def worker_start(name, workers)
  input, output, error, thread = Open3.popen3(*PSQL)
  worker = { name: name, input: input, output: output, error: error, thread: thread }
  workers << worker
  input.write(<<~SQL)
    set application_name = '#{name}';
    set statement_timeout = '20s';
    set timezone = 'UTC';
    select 'PID:' || pg_backend_pid();
    select 'WORKER_READY';
  SQL
  input.flush
  lines = worker_read_until(worker, 'WORKER_READY')
  pid_line = lines.find { |line| line.start_with?('PID:') }
  raise "Missing worker PID for #{name}" unless pid_line
  worker[:pid] = Integer(pid_line.delete_prefix('PID:'))
  worker
rescue StandardError
  input.close if input && !input.closed?
  raise
end

def worker_read_until(worker, marker)
  lines = []
  Timeout.timeout(15) do
    loop do
      line = worker[:output].gets
      raise "#{worker[:name]} ended before #{marker}: #{worker[:error].read}" if line.nil?
      line = line.strip
      break if line == marker
      lines << line
    end
  end
  lines
end

def worker_write(worker, sql)
  worker[:input].write(sql)
  worker[:input].flush
end

labels_raw, labels_error, labels_status = Open3.capture3(
  'docker', 'inspect', CONTAINER, '--format', '{{json .Config.Labels}}'
)
raise labels_error unless labels_status.success?
ports_raw, ports_error, ports_status = Open3.capture3(
  'docker', 'inspect', CONTAINER, '--format', '{{json .HostConfig.PortBindings}}'
)
raise ports_error unless ports_status.success?
labels = JSON.parse(labels_raw)
ports = JSON.parse(ports_raw)
config = File.read(File.join(WORKDIR, 'supabase/config.toml'))
raise 'Notification concurrency fixture provenance mismatch' unless
  labels['com.supabase.cli.project'] == PROJECT &&
  labels['com.docker.compose.project'] == PROJECT &&
  config.match?(/^project_id = "#{PROJECT}"$/) &&
  config.match?(/^port = 55722$/) &&
  ports.dig('5432/tcp', 0, 'HostPort') == '55722'

query(<<~SQL)
  do $$ begin
    if current_database() <> 'postgres'
       or current_setting('cron.launch_active_jobs') <> 'off'
       or current_setting('pg_net.batch_size') <> '0'
       or (select count(*) from supabase_migrations.schema_migrations) <>
         (case (select max(version) from supabase_migrations.schema_migrations)
           when '20260929160000' then 139
           else -1 end)
       or to_regprocedure('public.claim_notification_deliveries(integer,integer)') is null
       or to_regprocedure('public.claim_notification_deliveries(integer)') is not null
       or exists (select 1 from public.notification_device_tokens)
       or exists (select 1 from public.notification_deliveries)
       or exists (select 1 from auth.users where id::text like '99860000-%')
       or exists (select 1 from public.profiles where id::text like '99860000-%')
       or exists (select 1 from collect_hybrid.member_records where id::text like '99860000-%')
       or exists (select 1 from public.notification_events where id = '#{EVENT_ID}')
       or exists (select 1 from pg_stat_activity
         where application_name in ('#{WORKER_A}', '#{WORKER_B}')) then
      raise exception 'Exact 139-migration fixture, empty push queue and unused synthetic IDs required';
    end if;
  end $$;
SQL
migration_count = query('select count(*) from supabase_migrations.schema_migrations;').to_i
baseline_digest = fixture_digest
workers = []
seed_authorized = false
failure = nil
cleanup_failure = nil
result = nil

begin
  # These UUIDs were just proven absent. Cleanup remains safe even if the
  # client loses a response after this transaction commits.
  seed_authorized = true
  query(<<~SQL)
    begin;
    insert into auth.users(id, aud, role, phone, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data)
    values ('#{USER_A}', 'authenticated', 'authenticated', '250788908001', now(), '{}', '{}'),
           ('#{USER_B}', 'authenticated', 'authenticated', '250788908002', now(), '{}', '{}');
    update public.profiles set country_code = 'RW', currency_code = 'RWF'
    where id in ('#{USER_A}', '#{USER_B}');
    commit;
  SQL
  registration = query(<<~SQL)
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims', '{"sub":"#{USER_A}","role":"authenticated"}', true);
    select 'DEVICE:' || public.register_notification_device(
      'android', 'fcm', '#{TOKEN}', 'production', 'en', 'synthetic-o05-concurrency');
    commit;
  SQL
  registration_line = registration.lines.find { |line| line.start_with?('DEVICE:') }
  device_id = registration_line&.strip&.delete_prefix('DEVICE:')
  raise 'Actual authenticated registration did not return a device UUID' unless
    device_id && device_id.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
  query(<<~SQL)
    begin;
    insert into public.notification_events(id, user_id, type, title, body)
    values ('#{EVENT_ID}', '#{USER_A}', 'group_update', 'Synthetic concurrency QA',
      'No provider send: this fixture is deleted after the SQL race.');
    do $$ begin
      if (select count(*) from public.notification_device_tokens) <> 1
         or (select count(*) from public.notification_deliveries) <> 1
         or not exists (select 1 from public.notification_deliveries
           where event_id = '#{EVENT_ID}' and device_id = '#{device_id}'
             and status = 'queued' and attempt_count = 0) then
        raise exception 'Notification trigger did not create one synthetic queued delivery';
      end if;
    end $$;
    commit;
  SQL

  worker_a = worker_start(WORKER_A, workers)
  worker_b = worker_start(WORKER_B, workers)
  worker_write(worker_a, <<~SQL)
    begin;
    set local role service_role;
    select set_config('request.jwt.claims', '{"role":"service_role"}', true);
    select 'CLAIM:' || row_to_json(claimed)::text
    from public.claim_notification_deliveries(2, 1) claimed;
    select 'CLAIM_HELD';
  SQL
  claim_lines = worker_read_until(worker_a, 'CLAIM_HELD').select { |line| line.start_with?('CLAIM:') }
  raise 'Worker A did not claim exactly one delivery' unless claim_lines.length == 1
  claim = JSON.parse(claim_lines.first.delete_prefix('CLAIM:'))
  raise 'Worker A returned an unexpected claim' unless
    claim['device_id'] == device_id && claim['event_id'] == EVENT_ID &&
    claim['attempt_number'] == 1 && claim['claim_token'].is_a?(String) &&
    claim['claim_token'].match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
  held = JSON.parse(query(<<~SQL))
    select jsonb_build_object('pid', pid, 'state', state, 'transaction_open', xact_start is not null)
    from pg_stat_activity where pid = #{worker_a[:pid]} and application_name = '#{WORKER_A}';
  SQL
  raise 'Worker A was not holding its uncommitted claim transaction' unless
    held['state'] == 'idle in transaction' && held['transaction_open']

  # Worker B must finish while A is still holding its device/delivery locks.
  # A five-second statement timeout detects accidental blocking.
  worker_write(worker_b, <<~SQL)
    begin;
    set local statement_timeout = '5s';
    set local role service_role;
    select set_config('request.jwt.claims', '{"role":"service_role"}', true);
    select 'SKIPPED_COUNT:' || count(*) from public.claim_notification_deliveries(2, 1);
    commit;
    select 'SKIP_DONE';
  SQL
  skip_lines = worker_read_until(worker_b, 'SKIP_DONE')
  raise 'Overlapping worker B claimed a delivery already held by A' unless
    skip_lines.count { |line| line == 'SKIPPED_COUNT:0' } == 1
  raise 'Worker A connection ended before overlap was established' unless worker_a[:thread].alive?

  # Reuse B as an actual authenticated different-account registration. It must
  # wait for A's same-device row lock, then observe the committed live fence.
  worker_write(worker_b, <<~SQL)
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims', '{"sub":"#{USER_B}","role":"authenticated"}', true);
    do $$ begin
      begin
        perform public.register_notification_device(
          'android', 'fcm', '#{TOKEN}', 'production', 'en', 'synthetic-o05-concurrency');
        raise exception 'Concurrent token reassignment unexpectedly succeeded';
      exception when others then
        if sqlerrm <> 'notification_device_in_flight' then raise; end if;
      end;
    end $$;
    select 'REASSIGN_DENIED';
    commit;
    select 'REGISTER_DONE';
  SQL
  observed_wait = nil
  80.times do
    observed_wait = JSON.parse(query(<<~SQL))
      select coalesce((select jsonb_build_object(
        'pid', pid, 'state', state, 'wait_type', wait_event_type,
        'wait_event', wait_event, 'blocking_pids', pg_blocking_pids(pid))
        from pg_stat_activity where pid = #{worker_b[:pid]} and application_name = '#{WORKER_B}'), '{}'::jsonb);
    SQL
    break if observed_wait['wait_type'] == 'Lock' &&
             Array(observed_wait['blocking_pids']).include?(worker_a[:pid])
    sleep 0.1
  end
  raise "Registration did not wait behind the live claim: #{observed_wait.inspect}" unless
    observed_wait['wait_type'] == 'Lock' &&
    Array(observed_wait['blocking_pids']).include?(worker_a[:pid])

  worker_write(worker_a, "commit;\nselect 'CLAIM_COMMITTED';\n")
  worker_read_until(worker_a, 'CLAIM_COMMITTED')
  denied_lines = worker_read_until(worker_b, 'REGISTER_DONE')
  raise 'Registration was not rejected after the claim committed' unless denied_lines.include?('REASSIGN_DENIED')
  query(<<~SQL)
    do $$ begin
      if not exists (select 1 from public.notification_device_tokens
           where id = '#{device_id}' and user_id = '#{USER_A}' and enabled)
         or (select count(*) from public.notification_device_tokens) <> 1
         or (select count(*) from public.notification_deliveries) <> 1
         or not exists (select 1 from public.notification_deliveries
           where event_id = '#{EVENT_ID}' and device_id = '#{device_id}'
             and status = 'processing' and attempt_count = 1
             and claim_user_id = '#{USER_A}' and claim_token = '#{claim['claim_token']}'
             and claim_expires_at > clock_timestamp())
         or exists (select 1 from public.notification_delivery_attempts)
         or not public.notification_delivery_is_current(
           '#{claim['delivery_id']}', '#{claim['claim_token']}', 1) then
        raise exception 'Concurrent claim or registration changed owner, lease or attempt history';
      end if;
    end $$;
  SQL
  result = {
    status: 'pass', fixture: PROJECT, migration_count: migration_count,
    fencing_migration_sha256: Digest::SHA256.file(File.join(ROOT, 'supabase/migrations', MIGRATION)).hexdigest,
    claim_contract_version: 2, worker_sessions: 2,
    worker_a_uncommitted_claims: 1, overlapping_worker_b_claims: 0,
    registration_wait_observed: true,
    registration_wait_event: observed_wait['wait_event'],
    registration_blocked_by_claim_session: true,
    registration_after_claim_commit: 'notification_device_in_flight',
    original_token_owner_preserved: true, active_claim_attempt_number: 1,
    provider_calls: 0, provider_completion_rows: 0
  }
rescue StandardError => error
  failure = error
ensure
  begin
    # EOF closes each psql connection and rolls back an unfinished transaction.
    # If one backend is still blocked, terminate only our observed PID/name pair.
    workers.each do |worker|
      worker[:input].close unless worker[:input].closed?
    end
    workers.each do |worker|
      begin
        Timeout.timeout(5) { worker[:thread].value }
      rescue Timeout::Error
        raise "Worker #{worker[:name]} did not finish and has no verified PID" unless worker[:pid]
        query(<<~SQL)
          select pg_terminate_backend(pid) from pg_stat_activity
          where pid = #{worker[:pid]} and application_name = '#{worker[:name]}';
        SQL
        Timeout.timeout(5) { worker[:thread].value }
      end
      stderr = worker[:error].read
      unless worker[:thread].value.success? || failure
        raise "Worker #{worker[:name]} failed: #{stderr}"
      end
    end
    remaining_workers = query(<<~SQL).to_i
      select count(*) from pg_stat_activity
      where application_name in ('#{WORKER_A}', '#{WORKER_B}');
    SQL
    raise 'Worker SQL sessions remain; synthetic cleanup refused' unless remaining_workers.zero?
    if seed_authorized
      query(<<~SQL)
        begin;
        set local lock_timeout = '5s';
        delete from public.notification_events where user_id in ('#{USER_A}', '#{USER_B}');
        delete from public.notification_device_tokens
          where user_id in ('#{USER_A}', '#{USER_B}')
            and token_hash = encode(extensions.digest('#{TOKEN}', 'sha256'), 'hex');
        delete from auth.users where id in ('#{USER_A}', '#{USER_B}');
        do $$ declare fk record; referenced boolean; member_ids uuid[]:=ARRAY['#{USER_A}','#{USER_B}']::uuid[]; begin
          if exists(select 1 from auth.users where id=any(member_ids))
            or exists(select 1 from collect_hybrid.member_records where id=any(member_ids) and linked_user_id is not null) then
            raise exception 'Synthetic members remain linked; cleanup refused'; end if;
          -- Refuse any referenced row before DELETE; never depend on cascade behavior.
          for fk in select c.conrelid::regclass as relation,a.attname,c.confdeltype,
              cardinality(c.conkey) as key_count from pg_constraint c
              join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
              where c.contype='f' and c.confrelid='collect_hybrid.member_records'::regclass loop
            if fk.key_count<>1 then raise exception 'Unexpected composite member FK; cleanup refused'; end if;
            execute format('select exists(select 1 from %s where %I=any($1))',fk.relation,fk.attname)
              into referenced using member_ids;
            if referenced then raise exception 'Synthetic member referenced by %; cleanup refused',fk.relation; end if;
          end loop;
          delete from collect_hybrid.member_records where id=any(member_ids) and linked_user_id is null;
        end $$;
        do $$ begin
          if exists (select 1 from auth.users where id::text like '99860000-%')
             or exists (select 1 from public.profiles where id::text like '99860000-%')
       or exists (select 1 from collect_hybrid.member_records where id::text like '99860000-%')
             or exists (select 1 from public.notification_device_tokens)
             or exists (select 1 from public.notification_deliveries) then
            raise exception 'Synthetic notification cleanup incomplete';
          end if;
        end $$;
        commit;
      SQL
      after_digest = fixture_digest
      raise 'Existing fixture rows changed during concurrency test/cleanup' unless after_digest == baseline_digest
      if result
        result[:synthetic_rows_removed] = true
        result[:worker_sessions_remaining] = 0
        result[:existing_fixture_sha256_before] = baseline_digest
        result[:existing_fixture_sha256_after] = after_digest
        result[:snapshot_table_count] = 19
        result[:snapshot_scope] = 'auth_profile_member_notification_financial_and_audit_rows'
      end
    end
  rescue StandardError => error
    cleanup_failure = error
  end
end

raise "#{failure&.message}\nCleanup failed: #{cleanup_failure.message}" if cleanup_failure
raise failure if failure
puts JSON.pretty_generate(result)
