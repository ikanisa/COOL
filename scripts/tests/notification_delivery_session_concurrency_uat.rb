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
USER_A = '99730000-0000-4000-8000-000000000001'
USER_B = '99730000-0000-4000-8000-000000000002'
SESSION_A = '99730000-0000-4000-8000-000000000101'
SESSION_B = '99730000-0000-4000-8000-000000000102'
EVENT_ID = '99730000-0000-4000-8000-000000000020'
TOKEN = 'synthetic-concurrency-token-9973001'
WORKER_A = 'collect_o05_notification_claim_a'
WORKER_B = 'collect_o05_notification_claim_b'
MIGRATION = '20260929180000_notification_registration_sessions.sql'

TRACKED_XIDS = []
SCHEMAS = "'public','collect_hybrid','collect_security','collect_admin_access','auth'"

# These are owned literal QA statements, not a general SQL rewriter. Capture
# each explicit transaction boundary; statements without one are wrapped.
def capture_transaction_ids(sql)
  if sql.match?(/\bbegin\s*;/i)
    sql.gsub(/\bbegin\s*;/i,"begin; select 'XID:' || pg_current_xact_id();")
  else
    "begin; select 'XID:' || pg_current_xact_id();\n#{sql}\ncommit;"
  end
end

def query(sql)
  output, error, status = Open3.capture3(*PSQL, stdin_data:
    "set statement_timeout = '20s';\nset timezone = 'UTC';\n#{capture_transaction_ids(sql)}")
  output.lines.grep(/^XID:/).each { |line| TRACKED_XIDS << line.strip.delete_prefix('XID:') }
  raise(error.empty? ? output : error) unless status.success?
  output.lines.reject { |line| line.start_with?('XID:') }.join.strip
end

def application_tables
  JSON.parse(query(<<~SQL))
    select json_agg(format('%I.%I',n.nspname,c.relname) order by n.nspname,c.relname)
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where c.relkind='r' and n.nspname in (#{SCHEMAS});
  SQL
end

def fixture_digest_sql(tables)
  union=tables.map { |table| "select '#{table}'::text family,to_jsonb(t) body from #{table} t" }.join(' union all ')
  "with rows as (#{union}) select encode(extensions.digest(coalesce(string_agg(family||':'||body::text,E'\\n' order by family,body::text),''),'sha256'),'hex') from rows"
end

def fixture_digest(tables)
  query(fixture_digest_sql(tables)+';')
end

def control_digest_sql
  <<~SQL
    with controls(family,body) as (
      select 'trigger',jsonb_build_object('table',t.tgrelid::regclass::text,'name',t.tgname,
        'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid)) from pg_trigger t
        join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
        where n.nspname in (#{SCHEMAS},'auth')
      union all select 'relation_acl',jsonb_build_object('relation',c.oid::regclass::text,'acl',c.relacl,'owner',c.relowner)
        from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in (#{SCHEMAS},'auth')
      union all select 'routine',jsonb_build_object('routine',p.oid::regprocedure::text,'acl',p.proacl,
        'owner',p.proowner,'source',p.prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname in (#{SCHEMAS},'auth')
    ) select encode(extensions.digest(string_agg(family||':'||body::text,E'\n' order by family,body::text),'sha256'),'hex') from controls;
  SQL
end

def control_digest
  query(control_digest_sql)
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
      TRACKED_XIDS << line.delete_prefix('XID:') if line.start_with?('XID:')
      lines << line
    end
  end
  lines
end

def worker_write(worker, sql)
  worker[:input].write(sql.gsub(/\bbegin\s*;/i,"begin; select 'XID:' || pg_current_xact_id();"))
  worker[:input].flush
end

def await_blocked(waiter, blocker)
  state = nil
  80.times do
    state = JSON.parse(query(<<~SQL))
      select coalesce((select jsonb_build_object('wait_type',wait_event_type,'blocking_pids',pg_blocking_pids(pid))
        from pg_stat_activity where pid=#{waiter[:pid]} and application_name='#{waiter[:name]}'),'{}'::jsonb);
    SQL
    return state if state['wait_type']=='Lock' && Array(state['blocking_pids']).include?(blocker[:pid])
    sleep 0.1
  end
  raise "Session ordering did not establish expected lock wait: #{state.inspect}"
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
           when '20260929180000' then 141
           else -1 end)
       or to_regprocedure('public.claim_notification_deliveries(integer,integer)') is null
       or to_regprocedure('public.claim_notification_deliveries(integer)') is not null
       or exists (select 1 from public.notification_device_tokens)
       or exists (select 1 from public.notification_deliveries)
       or exists (select 1 from auth.users where id::text like '99730000-%')
       or exists (select 1 from public.profiles where id::text like '99730000-%')
       or exists (select 1 from collect_hybrid.member_records where id::text like '99730000-%')
       or exists (select 1 from public.notification_events where id = '#{EVENT_ID}')
       or exists (select 1 from pg_stat_activity
         where application_name in ('#{WORKER_A}', '#{WORKER_B}')) then
      raise exception 'Exact 141-migration fixture, empty push queue and unused synthetic IDs required';
    end if;
  end $$;
SQL
migration_count = query('select count(*) from supabase_migrations.schema_migrations;').to_i
tables = application_tables
baseline_digest = fixture_digest(tables)
baseline_controls = control_digest
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
    insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values
      ('#{SESSION_A}','#{USER_A}',now()-interval '10 minutes',now(),now()+interval '1 hour','aal1'),
      ('#{SESSION_B}','#{USER_B}',now()-interval '8 minutes',now(),now()+interval '1 hour','aal1');
    update public.profiles set country_code = 'RW', currency_code = 'RWF'
    where id in ('#{USER_A}', '#{USER_B}');
    commit;
  SQL
  registration = query(<<~SQL)
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims', '{"sub":"#{USER_A}","role":"authenticated","session_id":"#{SESSION_A}","aal":"aal1"}', true);
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
    select set_config('request.jwt.claims', '{"sub":"#{USER_B}","role":"authenticated","session_id":"#{SESSION_B}","aal":"aal1"}', true);
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
  # First registration wins the session row lock, logout must wait and then
  # disable the committed token. No provider is involved in these SQL races.
  query("begin; delete from public.notification_events where id='#{EVENT_ID}'; delete from public.notification_device_tokens where token_hash=encode(extensions.digest('#{TOKEN}','sha256'),'hex'); commit;")
  # B's newer session holds a replacement transaction while delayed A's old
  # still-live session attempts the same token. ON CONFLICT must compare the
  # committed timestamp after waiting on B, then reject A without changing B.
  query(<<~SQL)
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims','{"sub":"#{USER_A}","role":"authenticated","session_id":"#{SESSION_A}","aal":"aal1"}',true);
    select public.register_notification_device('android','fcm','#{TOKEN}');
    commit;
  SQL
  worker_write(worker_b, <<~SQL)
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims','{"sub":"#{USER_B}","role":"authenticated","session_id":"#{SESSION_B}","aal":"aal1"}',true);
    select public.register_notification_device('android','fcm','#{TOKEN}');
    select 'NEWER_B_REPLACEMENT_HELD';
  SQL
  worker_read_until(worker_b,'NEWER_B_REPLACEMENT_HELD')
  worker_write(worker_a, <<~SQL)
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims','{"sub":"#{USER_A}","role":"authenticated","session_id":"#{SESSION_A}","aal":"aal1"}',true);
    do $$ declare denied boolean:=false; begin
      begin perform public.register_notification_device('android','fcm','#{TOKEN}');
      exception when others then
        if sqlerrm<>'notification_registration_session_stale' or sqlstate<>'42501' then raise; end if;
        denied:=true;
      end;
      if not denied then raise exception 'Late live A replaced newer B'; end if;
    end $$;
    select public.unregister_notification_device('fcm','#{TOKEN}');
    commit;
    select 'OLDER_LIVE_A_DENIED';
  SQL
  await_blocked(worker_a,worker_b)
  worker_write(worker_b,"commit; select 'NEWER_B_REPLACEMENT_COMMITTED';\n")
  worker_read_until(worker_b,'NEWER_B_REPLACEMENT_COMMITTED')
  worker_read_until(worker_a,'OLDER_LIVE_A_DENIED')
  query(<<~SQL)
    do $$ begin
      if not exists(select 1 from auth.sessions where id='#{SESSION_A}')
        or not exists(select 1 from public.notification_device_tokens where user_id='#{USER_B}'
          and registration_session_id='#{SESSION_B}' and enabled) then
        raise exception 'Late live A registration or its cleanup changed B token'; end if;
    end $$;
    delete from public.notification_device_tokens where token_hash=encode(extensions.digest('#{TOKEN}','sha256'),'hex');
  SQL
  worker_write(worker_a, <<~SQL)
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims','{"sub":"#{USER_A}","role":"authenticated","session_id":"#{SESSION_A}","aal":"aal1"}',true);
    select public.register_notification_device('android','fcm','#{TOKEN}');
    select 'REGISTRATION_SESSION_HELD';
  SQL
  worker_read_until(worker_a,'REGISTRATION_SESSION_HELD')
  worker_write(worker_b, <<~SQL)
    begin;
    delete from auth.sessions where id='#{SESSION_A}';
    commit;
    select 'LOGOUT_AFTER_REGISTRATION_DONE';
  SQL
  await_blocked(worker_b,worker_a)
  worker_write(worker_a,"commit; select 'REGISTRATION_COMMITTED';\n")
  worker_read_until(worker_a,'REGISTRATION_COMMITTED')
  worker_read_until(worker_b,'LOGOUT_AFTER_REGISTRATION_DONE')
  query(<<~SQL)
    do $$ begin
      if exists(select 1 from auth.sessions where id='#{SESSION_A}')
        or not exists(select 1 from public.notification_device_tokens where registration_session_id='#{SESSION_A}' and not enabled)
        then raise exception 'Logout did not disable the just-committed session token'; end if;
    end $$;
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims','{"sub":"#{USER_B}","role":"authenticated","session_id":"#{SESSION_B}","aal":"aal1"}',true);
    select public.register_notification_device('android','fcm','#{TOKEN}');
    select set_config('request.jwt.claims','{"sub":"#{USER_A}","role":"authenticated","session_id":"#{SESSION_A}","aal":"aal1"}',true);
    do $$ begin
      begin perform public.register_notification_device('android','fcm','#{TOKEN}');
        raise exception 'Late logged-out registration unexpectedly succeeded';
      exception when others then
        if sqlerrm<>'notification_registration_session_required' then raise; end if;
      end;
    end $$;
    commit;
    do $$ begin
      if not exists(select 1 from public.notification_device_tokens where user_id='#{USER_B}'
        and registration_session_id='#{SESSION_B}' and enabled) then raise exception 'Late A registration changed B ownership'; end if;
    end $$;
  SQL
  # Reverse ordering: logout already holds the row, registration must wait and
  # then refuse rather than resurrecting a token after the session disappears.
  session_a2 = '99730000-0000-4000-8000-000000000103'
  query(<<~SQL)
    begin;
    delete from public.notification_device_tokens where token_hash=encode(extensions.digest('#{TOKEN}','sha256'),'hex');
    insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
    values('#{session_a2}','#{USER_A}',now()-interval '6 minutes',now(),now()+interval '1 hour','aal1');
    commit;
  SQL
  worker_write(worker_b, "begin; delete from auth.sessions where id='#{session_a2}'; select 'LOGOUT_HELD';\n")
  worker_read_until(worker_b,'LOGOUT_HELD')
  worker_write(worker_a, <<~SQL)
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims','{"sub":"#{USER_A}","role":"authenticated","session_id":"#{session_a2}","aal":"aal1"}',true);
    do $$ begin
      begin perform public.register_notification_device('android','fcm','#{TOKEN}');
        raise exception 'Registration after concurrent logout unexpectedly succeeded';
      exception when others then
        if sqlerrm<>'notification_registration_session_required' then raise; end if;
      end;
    end $$;
    commit;
    select 'REGISTRATION_AFTER_LOGOUT_DENIED';
  SQL
  await_blocked(worker_a,worker_b)
  worker_write(worker_b,"commit; select 'LOGOUT_COMMITTED';\n")
  worker_read_until(worker_b,'LOGOUT_COMMITTED')
  worker_read_until(worker_a,'REGISTRATION_AFTER_LOGOUT_DENIED')
  raise 'Late registration resurrected a token' unless query('select not exists(select 1 from public.notification_device_tokens);')=='t'
  # Multiple-session DELETE must take its exclusive gate before it can lock
  # either Auth row or the device registered by another session of that user.
  session_bulk_old = '99730000-0000-4000-8000-000000000104'
  session_bulk_new = '99730000-0000-4000-8000-000000000105'
  query(<<~SQL)
    begin;
    insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values
      ('#{session_bulk_old}','#{USER_A}',now()-interval '4 minutes',now(),now()+interval '1 hour','aal1'),
      ('#{session_bulk_new}','#{USER_A}',now()-interval '3 minutes',now(),now()+interval '1 hour','aal1');
    set local role authenticated;
    select set_config('request.jwt.claims','{"sub":"#{USER_A}","role":"authenticated","session_id":"#{session_bulk_old}","aal":"aal1"}',true);
    select public.register_notification_device('android','fcm','#{TOKEN}');
    commit;
  SQL
  worker_write(worker_a, <<~SQL)
    begin;
    select set_config('request.jwt.claims','{"sub":"#{USER_A}","role":"authenticated","session_id":"#{session_bulk_new}","aal":"aal1"}',true);
    -- Owner test hook stops at the real registration session boundary. The
    -- actual authenticated public RPC below completes registration afterwards.
    select public._lock_notification_registration_session();
    select 'BULK_REGISTRATION_SESSION_HELD';
  SQL
  worker_read_until(worker_a,'BULK_REGISTRATION_SESSION_HELD')
  worker_write(worker_b, <<~SQL)
    begin;
    delete from auth.sessions where user_id='#{USER_A}';
    commit;
    select 'BULK_LOGOUT_DONE';
  SQL
  bulk_wait = await_blocked(worker_b,worker_a)
  worker_write(worker_a, <<~SQL)
    set local role authenticated;
    select public.register_notification_device('android','fcm','#{TOKEN}');
    commit;
    select 'BULK_REPLACEMENT_COMMITTED';
  SQL
  worker_read_until(worker_a,'BULK_REPLACEMENT_COMMITTED')
  worker_read_until(worker_b,'BULK_LOGOUT_DONE')
  query(<<~SQL)
    do $$ begin
      if exists(select 1 from auth.sessions where user_id='#{USER_A}')
        or not exists(select 1 from public.notification_device_tokens where user_id='#{USER_A}'
          and registration_session_id='#{session_bulk_new}' and not enabled) then
        raise exception 'Bulk logout did not revoke the just-replaced session without deadlock'; end if;
    end $$;
  SQL

  # Invalidating Auth UPDATE wins first: a registration waits for the statement
  # transaction, then refuses the now-invalid assurance value.
  session_update = '99730000-0000-4000-8000-000000000106'
  query(<<~SQL)
    insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
      values('#{session_update}','#{USER_A}',now()-interval '2 minutes',now(),now()+interval '1 hour','aal1');
  SQL
  worker_write(worker_b,"begin; update auth.sessions set aal=null where id='#{session_update}'; select 'SESSION_UPDATE_HELD';\n")
  worker_read_until(worker_b,'SESSION_UPDATE_HELD')
  worker_write(worker_a, <<~SQL)
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims','{"sub":"#{USER_A}","role":"authenticated","session_id":"#{session_update}","aal":"aal1"}',true);
    do $$ begin
      begin perform public.register_notification_device('android','fcm','#{TOKEN}');
        raise exception 'Registration during revocation unexpectedly succeeded';
      exception when others then
        if sqlerrm<>'notification_registration_session_required' then raise; end if;
      end;
    end $$;
    commit;
    select 'REGISTRATION_AFTER_UPDATE_DENIED';
  SQL
  await_blocked(worker_a,worker_b)
  worker_write(worker_b,"commit; select 'SESSION_UPDATE_COMMITTED';\n")
  worker_read_until(worker_b,'SESSION_UPDATE_COMMITTED')
  worker_read_until(worker_a,'REGISTRATION_AFTER_UPDATE_DENIED')

  # A live registered token is disabled by the ordinary Auth ban operation.
  query(<<~SQL)
    begin;
    update auth.sessions set aal='aal1' where id='#{session_update}';
    set local role authenticated;
    select set_config('request.jwt.claims','{"sub":"#{USER_A}","role":"authenticated","session_id":"#{session_update}","aal":"aal1"}',true);
    select public.register_notification_device('android','fcm','#{TOKEN}');
    commit;
  SQL
  worker_write(worker_b,"begin; update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id='#{USER_A}'; select 'USER_BAN_HELD';\n")
  worker_read_until(worker_b,'USER_BAN_HELD')
  worker_write(worker_a, <<~SQL)
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims','{"sub":"#{USER_A}","role":"authenticated","session_id":"#{session_update}","aal":"aal1"}',true);
    do $$ begin
      begin perform public.register_notification_device('android','fcm','#{TOKEN}');
        raise exception 'Registration during user ban unexpectedly succeeded';
      exception when others then
        if sqlerrm<>'notification_registration_session_required' then raise; end if;
      end;
    end $$;
    commit;
    select 'REGISTRATION_AFTER_BAN_DENIED';
  SQL
  await_blocked(worker_a,worker_b)
  worker_write(worker_b,"commit; select 'USER_BAN_COMMITTED';\n")
  worker_read_until(worker_b,'USER_BAN_COMMITTED')
  worker_read_until(worker_a,'REGISTRATION_AFTER_BAN_DENIED')
  raise 'Auth ban left the current token enabled' unless query(<<~SQL)=='t'
    select exists(select 1 from public.notification_device_tokens where user_id='#{USER_A}'
      and not enabled and disabled_reason='registration_user_revoked');
  SQL

  # Mixed Auth transactions may first modify ordinary metadata, taking a user
  # row lock, then revoke a session. A reconciliation actor check shares the
  # gate before waiting for that user. The exclusive upgrade must fail with
  # 40001 instead of waiting for the shared reader and creating a deadlock.
  query("update auth.users set banned_until=null where id='#{USER_A}';")
  worker_write(worker_b, <<~SQL)
    begin;
    update auth.users set raw_user_meta_data='{"synthetic_gate_race":true}'::jsonb where id='#{USER_A}';
    select 'AUTH_METADATA_HELD';
  SQL
  worker_read_until(worker_b,'AUTH_METADATA_HELD')
  worker_write(worker_a, <<~SQL)
    begin;
    select public._lock_notification_session_gate();
    select collect_security.reconciliation_actor_current('#{USER_A}','#{session_update}');
    commit;
    select 'RECONCILIATION_ACTOR_CHECK_DONE';
  SQL
  await_blocked(worker_a,worker_b)
  worker_write(worker_b, <<~SQL)
    do $$ declare refused boolean:=false; begin
      begin delete from auth.sessions where id='#{session_update}';
      exception when serialization_failure then
        if sqlerrm<>'notification_auth_revocation_retry' then raise; end if;
        refused:=true;
      end;
      if not refused then raise exception 'Mixed Auth upgrade did not require transaction retry'; end if;
    end $$;
    rollback;
    select 'AUTH_GATE_UPGRADE_RETRY';
  SQL
  worker_read_until(worker_b,'AUTH_GATE_UPGRADE_RETRY')
  worker_read_until(worker_a,'RECONCILIATION_ACTOR_CHECK_DONE')
  query(<<~SQL)
    do $$ begin
      if not exists(select 1 from auth.sessions where id='#{session_update}')
        or exists(select 1 from auth.users where id='#{USER_A}' and raw_user_meta_data ? 'synthetic_gate_race') then
        raise exception 'Mixed Auth retry failed to restore the complete transaction'; end if;
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
    registration_before_logout_serialized: true, logout_disabled_committed_token: true,
    late_a_registration_preserved_b_owner: true, logout_before_registration_serialized: true,
    registration_after_logout_denied: true,
    older_live_session_rebind_denied_after_newer_commit: true,
    stale_session_unregister_preserved_newer_owner: true,
    bulk_logout_replacement_serialized: true, invalidating_session_update_serialized: true,
    user_ban_registration_serialized: true, user_ban_disabled_current_token: true,
    mixed_auth_metadata_reconciliation_upgrade_requires_40001: true,
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
      trailing = worker[:output].read
      trailing.lines.grep(/^XID:/).each { |line| TRACKED_XIDS << line.strip.delete_prefix('XID:') }
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
      raise 'Snapshot table/control catalog changed; cleanup refused' unless application_tables==tables && control_digest==baseline_controls
      raise 'Invalid observed transaction identity; cleanup refused' unless TRACKED_XIDS.all? { |xid| xid.match?(/\A[0-9]+\z/) }
      telemetry_xids=TRACKED_XIDS.uniq.map { |xid| "'#{xid}'" }.join(',')
      query(<<~SQL)
        begin;
        set local lock_timeout = '5s';
        select pg_advisory_xact_lock(193517,141);
        lock table public.app_realtime_events in access exclusive mode;
        do $$ begin
          if current_user<>'postgres' or current_setting('cron.launch_active_jobs')<>'off'
            or current_setting('pg_net.batch_size')<>'0'
            or (select count(*) from supabase_migrations.schema_migrations)<>141
            or (select max(version) from supabase_migrations.schema_migrations)<>'20260929180000'
            or exists(select 1 from pg_stat_activity where pid<>pg_backend_pid() and backend_type='client backend'
              and datname=current_database() and state<>'idle') then
            raise exception 'Quiet exact owner-only cleanup precondition lost'; end if;
          if exists(select 1 from pg_trigger where tgrelid='public.app_realtime_events'::regclass and not tgisinternal)
            or exists(select 1 from pg_constraint where contype='f' and confrelid='public.app_realtime_events'::regclass) then
            raise exception 'Unknown telemetry trigger/reference; cleanup refused'; end if;
        end $$;
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
          if exists (select 1 from auth.users where id::text like '99730000-%')
             or exists (select 1 from public.profiles where id::text like '99730000-%')
       or exists (select 1 from collect_hybrid.member_records where id::text like '99730000-%')
             or exists (select 1 from public.notification_device_tokens)
             or exists (select 1 from public.notification_deliveries) then
            raise exception 'Synthetic notification cleanup incomplete';
          end if;
        end $$;
        -- Preserve every earlier telemetry row, including the original141
        -- upgrade evidence. Only this run's observed XIDs may be removed.
        delete from public.app_realtime_events where xmin::text in (#{telemetry_xids})
          or xmin::text=pg_current_xact_id()::text;
        do $$ begin
          if (#{fixture_digest_sql(tables)})<>'#{baseline_digest}' then
            raise exception 'Full application/Auth baseline not restored; cleanup rolled back'; end if;
          if (#{control_digest_sql.strip.delete_suffix(';')})<>'#{baseline_controls}' then
            raise exception 'Trigger/ACL/function controls changed; cleanup rolled back'; end if;
        end $$;
        commit;
      SQL
      after_digest = fixture_digest(tables)
      raise 'Existing fixture rows/controls changed during concurrency test/cleanup' unless after_digest == baseline_digest && control_digest==baseline_controls
      if result
        result[:synthetic_rows_removed] = true
        result[:worker_sessions_remaining] = 0
        result[:existing_fixture_sha256_before] = baseline_digest
        result[:existing_fixture_sha256_after] = after_digest
        result[:snapshot_table_count] = tables.length
        result[:snapshot_tables] = tables
        result[:controls_sha256_before] = baseline_controls
        result[:controls_sha256_after] = control_digest
        result[:captured_transaction_ids] = TRACKED_XIDS.uniq
        result[:telemetry_disposition] = 'only observed test/cleanup transaction XIDs removed; prior rows preserved'
        result[:sequence_counters_restored] = false
        result[:snapshot_scope] = 'all_application_and_auth_tables_including_realtime_telemetry'
      end
    end
  rescue StandardError => error
    cleanup_failure = error
  end
end

raise "#{failure&.message}\nCleanup failed: #{cleanup_failure.message}" if cleanup_failure
raise failure if failure
puts JSON.pretty_generate(result)
