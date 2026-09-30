require 'open3'
require 'json'
require 'timeout'
require 'digest'

# Synthetic local QA only. This script commits its own graph to exercise real
# transaction overlap, then restores the exact baseline. Root owns execution.
ROOT = File.expand_path('../..', __dir__)
PROJECT = 'collect_fin_concurrency_qa_20260929'
CONTAINER = "supabase_db_#{PROJECT}"
WORKDIR = File.join(ROOT, '.cache/financial-concurrency-20260929')
PSQL = ['docker', 'exec', '-i', CONTAINER, 'psql', '-XqAt',
        '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'].freeze
PREFIX = '99830000'
MAKER = "#{PREFIX}-0000-4000-8000-000000000001"
CHECKER = "#{PREFIX}-0000-4000-8000-000000000002"
MEMBER = "#{PREFIX}-0000-4000-8000-000000000003"
GROUP = "#{PREFIX}-0000-4000-8000-000000000021"
WORKER_A = 'collect_reconciliation_141_a'
WORKER_B = 'collect_reconciliation_141_b'
MIGRATION = '20260929180000_notification_registration_sessions.sql'
TRACKED_XIDS = []
IMMUTABLE = {
  'collect_security.reconciliation_reviews' => 'reconciliation_review_immutable',
  'public.ledger_entries' => 'ledger_entries_prevent_delete',
  'collect_hybrid.momo_journal_entries' => 'hybrid_momo_journal_entries_immutable',
  'collect_hybrid.momo_journal_lines' => 'hybrid_momo_journal_lines_immutable',
  'collect_hybrid.momo_balance_snapshots' => 'hybrid_momo_snapshots_immutable'
}.freeze
SCHEMAS = "'public','collect_hybrid','collect_security','collect_admin_access'"

def query(sql, transaction: false)
  body = transaction ? "begin; select 'XID:' || pg_current_xact_id();\n#{sql}\ncommit;" : sql
  output, error, status = Open3.capture3(*PSQL, stdin_data:
    "set statement_timeout='20s'; set timezone='UTC';\n#{body}")
  output.lines.grep(/^XID:/).each { |line| TRACKED_XIDS << line.strip.delete_prefix('XID:') }
  raise(error.empty? ? output : error) unless status.success?
  output.lines.reject { |line| line.start_with?('XID:') }.join.strip
end

def uuid(number)
  "#{PREFIX}-0000-4000-8000-#{format('%012d',number)}"
end

def actor(user, session)
  claims = {sub: user, role: 'authenticated', aal: 'aal2', session_id: session}.to_json
  "set local role authenticated; select set_config('request.jwt.claims','#{claims}',true);"
end

def finalizer(review)
  "set local role service_role; select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true); select 'RESULT:' || public.finalize_approved_reconciliation_v2('#{review}')::text;"
end

def expect_finalizer_denied(review)
  <<~SQL
    set local role service_role;
    select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);
    do $$ declare denied boolean:=false; begin
      begin perform public.finalize_approved_reconciliation_v2('#{review}');
      exception when insufficient_privilege then
        if sqlerrm<>'reconciliation_actor_unavailable' then raise; end if; denied:=true;
      end;
      if not denied then raise exception 'Revoked actor finalized a payment'; end if;
    end $$;
  SQL
end

def application_tables
  JSON.parse(query(<<~SQL))
    select json_agg(format('%I.%I',n.nspname,c.relname) order by n.nspname,c.relname)
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where c.relkind='r' and (n.nspname in (#{SCHEMAS})
        or (n.nspname='auth' and c.relname in ('users','sessions')));
  SQL
end

def data_digest(tables)
  union=tables.map { |table| "select '#{table}'::text family,to_jsonb(t) body from #{table} t" }.join(' union all ')
  query("with rows as (#{union}) select encode(extensions.digest(coalesce(string_agg(family||':'||body::text,E'\\n' order by family,body::text),''),'sha256'),'hex') from rows;")
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

def financial_digest(payment)
  tables=%w[public.payments public.provider_finality_requests public.payment_provider_confirmations public.ledger_entries
    collect_hybrid.momo_journal_entries collect_hybrid.momo_journal_lines collect_hybrid.momo_balance_snapshots
    collect_hybrid.collection_balances collect_hybrid.member_balances collect_security.reconciliation_reviews]
  union=tables.map { |table| "select '#{table}'::text family,to_jsonb(t) body from #{table} t" }.join(' union all ')
  union += " union all select 'public.audit_logs',to_jsonb(t) from public.audit_logs t where entity_id='#{payment}'"
  query("with rows as (#{union}) select encode(extensions.digest(coalesce(string_agg(family||':'||body::text,E'\\n' order by family,body::text),''),'sha256'),'hex') from rows;")
end

def new_session(user, number)
  session=uuid(number)
  query("insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values('#{session}','#{user}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal2');",transaction: true)
  session
end

def approved_review(payment, maker_session, checker_session)
  out=query("#{actor(MAKER,maker_session)} select 'REVIEW:' || public.propose_payment_reconciliation_v2('#{payment}',repeat('b',64),'RECON141-#{payment[-2..]}',clock_timestamp()-interval '1 hour','Synthetic independent statement evidence');",transaction: true)
  review=out.lines.find { |line| line.start_with?('REVIEW:') }&.strip&.delete_prefix('REVIEW:')
  raise 'Proposal did not produce an actual review UUID' unless review&.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
  query("#{actor(CHECKER,checker_session)} select public.approve_payment_reconciliation_v2('#{review}','Synthetic independent checker approval'); select public.authorize_reconciliation_finalization_v2('#{review}');",transaction: true)
  review
end

def begin_worker(worker, sql)
  worker_write(worker,"begin; select 'XID:' || pg_current_xact_id();\n#{sql}\n")
end

def assert_gate_precedes_financial_locks(worker)
  query(<<~SQL)
    do $$ begin
      if exists(select 1 from pg_locks where pid=#{worker[:pid]} and granted
        and relation in ('public.payments'::regclass,'collect_security.reconciliation_reviews'::regclass)
        and mode in ('RowShareLock','RowExclusiveLock')) then
        raise exception 'Blocked finalizer acquired financial/review locks before outer gate'; end if;
    end $$;
  SQL
end

def assert_auth_wait_precedes_roster_lock(worker)
  query(<<~SQL)
    do $$ declare roster_key bigint:=hashtext('collect_admin_combined_roster')::bigint;
    begin
      -- Two-int advisory keys use objsubid2. Observe the specific ungranted
      -- shared141 gate request rather than assuming every advisory wait is it.
      if not exists(select 1 from pg_locks where pid=#{worker[:pid]}
        and locktype='advisory' and not granted and mode='ShareLock'
        and classid::bigint=193517 and objid::bigint=141 and objsubid=2) then
        raise exception 'Finalizer is not waiting on the shared Auth revocation gate'; end if;
      -- pg_advisory_xact_lock(hashtext(...)) resolves to the one-bigint form.
      -- Preserve sign extension when splitting that signed key into its two
      -- unsigned32-bit pg_locks fields; objsubid1 distinguishes the key space.
      if exists(select 1 from pg_locks where pid=#{worker[:pid]}
        and locktype='advisory' and granted and objsubid=1
        and classid::bigint=((roster_key >> 32) & 4294967295::bigint)
        and objid::bigint=(roster_key & 4294967295::bigint)) then
        raise exception 'Finalizer holds the Admin roster lock while waiting behind Auth revocation'; end if;
    end $$;
  SQL
end

def verify_posting(payment, amount)
  JSON.parse(query(<<~SQL))
    do $$ begin
      if not exists(select 1 from public.payments where id='#{payment}' and status='posted' and amount_rwf=#{amount})
        or (select count(*) from public.provider_finality_requests where payment_id='#{payment}' and status='processed')<>1
        or (select count(*) from public.payment_provider_confirmations where payment_id='#{payment}')<>1
        or (select count(*) from public.ledger_entries where payment_id='#{payment}')<>2
        or (select count(*) from collect_hybrid.momo_journal_entries where payment_id='#{payment}' and entry_type='receipt')<>1
        or not exists(select 1 from collect_hybrid.momo_journal_lines l
          join collect_hybrid.momo_journal_entries j on j.id=l.journal_entry_id where j.payment_id='#{payment}'
          group by j.id having count(*)=2 and sum(l.amount_rwf) filter(where direction='debit')=#{amount}
            and sum(l.amount_rwf) filter(where direction='credit')=#{amount})
        or (select count(*) from public.audit_logs where entity_id='#{payment}' and action='reconciliation.proposed')<>1
        or (select count(*) from public.audit_logs where entity_id='#{payment}' and action='reconciliation.approved')<>1
        or (select count(*) from public.audit_logs where entity_id='#{payment}' and action='reconciliation.finalized')<>1
        or (select count(*) from public.audit_logs where entity_id='#{payment}' and action='payment.provider_confirmed')<>1
        or not exists(select 1 from collect_security.reconciliation_reviews where payment_id='#{payment}' and consumed_at is not null)
        then raise exception 'Exactly-once reconciliation accounting/audit assertion failed'; end if;
    end $$;
    select jsonb_build_object('payment_id','#{payment}','amount_rwf',#{amount},'canonical_journals',1,
      'debit_rwf',#{amount},'credit_rwf',#{amount},'legacy_ledger_rows',2,'finalization_audits',1);
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
      TRACKED_XIDS << line.delete_prefix('XID:') if line.start_with?('XID:')
      lines << line
    end
  end
  lines
end

def worker_write(worker, sql)
  worker[:input].write(sql)
  worker[:input].flush
end

def await_blocked(waiter, blocker)
  state = nil
  80.times do
    state = JSON.parse(query(<<~SQL))
      select coalesce((select jsonb_build_object('pid',pid,'wait_type',wait_event_type,'wait_event',wait_event,'blocking_pids',pg_blocking_pids(pid))
        from pg_stat_activity where pid=#{waiter[:pid]} and application_name='#{waiter[:name]}'),'{}'::jsonb);
    SQL
    return state if state['wait_type']=='Lock' && state['wait_event']=='advisory' && Array(state['blocking_pids']).include?(blocker[:pid])
    sleep 0.1
  end
  raise "Session ordering did not establish expected lock wait: #{state.inspect}"
end

raise 'Set COLLECT_RECONCILIATION_QA=isolated_clone for this guarded synthetic harness' unless ENV['COLLECT_RECONCILIATION_QA']=='isolated_clone'
labels_raw, labels_error, labels_status=Open3.capture3('docker','inspect',CONTAINER,'--format','{{json .Config.Labels}}')
raise labels_error unless labels_status.success?
ports_raw, ports_error, ports_status=Open3.capture3('docker','inspect',CONTAINER,'--format','{{json .HostConfig.PortBindings}}')
raise ports_error unless ports_status.success?
labels=JSON.parse(labels_raw); ports=JSON.parse(ports_raw)
config=File.read(File.join(WORKDIR,'supabase/config.toml'))
raise 'Reconciliation fixture provenance mismatch' unless labels['com.supabase.cli.project']==PROJECT &&
  labels['com.docker.compose.project']==PROJECT && config.match?(/^project_id = "#{PROJECT}"$/) &&
  config.match?(/^port = 55722$/) && ports.dig('5432/tcp',0,'HostPort')=='55722'
query(<<~SQL)
  do $$ begin
    if current_database()<>'postgres' or current_user<>'postgres'
      or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
      or (select count(*) from supabase_migrations.schema_migrations)<>141
      or (select max(version) from supabase_migrations.schema_migrations)<>'20260929180000'
      or to_regprocedure('public._lock_notification_session_gate()') is null
      or exists(select 1 from auth.users where id::text like '#{PREFIX}-%')
      or exists(select 1 from auth.sessions where id::text like '#{PREFIX}-%')
      or exists(select 1 from public.profiles where id::text like '#{PREFIX}-%')
      or exists(select 1 from collect_hybrid.member_records where id::text like '#{PREFIX}-%')
      or exists(select 1 from public.collections where id::text like '#{PREFIX}-%' or slug='reconciliation-141-concurrency-synthetic')
      or exists(select 1 from public.payments where id::text like '#{PREFIX}-%' or transaction_id like 'RECON141-RACE%')
      or exists(select 1 from auth.users where phone in ('250788983001','250788983002','250788983003'))
      or exists(select 1 from public.notification_device_tokens)
      or exists(select 1 from public.notification_deliveries)
      or exists(select 1 from pg_stat_activity where application_name in ('#{WORKER_A}','#{WORKER_B}'))
      then raise exception 'Exact isolated141, owner, quiet providers and unused9983 graph required'; end if;
    if has_function_privilege('service_role','public.process_provider_finality_event(uuid,text,text,uuid,text,text,text,text,bigint,timestamptz,text,text,text)','EXECUTE')
      or has_function_privilege('service_role','public.confirm_provider_payment(uuid,text,text,text,text,bigint,timestamptz,text)','EXECUTE')
      or has_function_privilege('authenticated','public.finalize_approved_reconciliation_v2(uuid)','EXECUTE') then
      raise exception 'Financial gateway wrapper boundary is not closed'; end if;
  end $$;
SQL
trigger_values=IMMUTABLE.map { |table,name| "('#{table}'::regclass,'#{name}')" }.join(',')
query(<<~SQL)
  do $$ declare item record; begin
    for item in select * from (values #{trigger_values}) expected(relation,name) loop
      if (select count(*) from pg_trigger where tgrelid=item.relation and tgname=item.name
          and not tgisinternal and tgenabled='O')<>1
        or exists(select 1 from pg_trigger where tgrelid=item.relation and not tgisinternal
          and (tgtype::integer & 2)=2 and (tgtype::integer & 8)=8 and tgname<>item.name) then
        raise exception 'Unknown/disabled immutable trigger; refuse before seeding'; end if;
    end loop;
  end $$;
SQL
# All application rows, Auth identities/sessions, private reviews and realtime
# invalidations are included, not just the subset expected to change.
tables=application_tables
baseline=data_digest(tables)
controls_before=control_digest
workers=[]; seed_authorized=false; failure=nil; cleanup_failure=nil; result=nil
observed=[]; reviews=[]; postings=[]
maker_session=uuid(11); checker_session=uuid(12)
payments=(31..35).map { |n| uuid(n) }

begin
  # Verify the service gateway permission at the actual RPC boundary before
  # creating any candidate, not solely through catalog privileges.
  query(<<~SQL,transaction: true)
    set local role service_role;
    select set_config('request.jwt.claims','{"role":"service_role"}',true);
    do $$ declare denied boolean:=false; begin
      begin perform public.process_provider_finality_event(null,null,null,null);
      exception when insufficient_privilege then denied:=true; end;
      if not denied then raise exception 'Direct service gateway was callable'; end if;
    end $$;
  SQL
  seed_authorized=true
  query(<<~SQL,transaction: true)
    insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data) values
      ('#{MAKER}','authenticated','authenticated','250788983001',now(),'{}','{}'),
      ('#{CHECKER}','authenticated','authenticated','250788983002',now(),'{}','{}'),
      ('#{MEMBER}','authenticated','authenticated','250788983003',now(),'{}','{}');
    update public.profiles set country_code='RW',currency_code='RWF' where id in ('#{MAKER}','#{CHECKER}','#{MEMBER}');
    insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason) values
      ('#{MAKER}','+250788983001',clock_timestamp()-interval '2 minutes','Synthetic independent maker identity'),
      ('#{CHECKER}','+250788983002',clock_timestamp()-interval '2 minutes','Synthetic independent checker identity');
    insert into public.admin_user_roles(user_id,role_id,reason,created_at)
      select actor.id,r.id,'Synthetic reconciliation concurrency',clock_timestamp()-interval '1 minute'
      from (values('#{MAKER}'::uuid),('#{CHECKER}'::uuid)) actor(id)
      cross join public.admin_roles r where r.name='platform_owner';
    insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values
      ('#{maker_session}','#{MAKER}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal2'),
      ('#{checker_session}','#{CHECKER}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal2');
    insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type,
      contribution_visibility,allow_anonymous,diaspora_enabled,creation_origin) values
      ('#{GROUP}','reconciliation-141-concurrency-synthetic','#{MEMBER}','Synthetic concurrent reconciliation',
       'Family / friends','private','private','ikimina','members',false,false,'member_app');
    #{payments.each_with_index.map { |payment,i| "insert into public.payments(id,collection_id,contributor_user_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,anonymity_choice,posted_at) values('#{payment}','#{GROUP}','#{MEMBER}','#{MEMBER}',repeat('a',64),#{1234+i},'RECON141-RACE#{31+i}','mtn_momo','manual_admin','review','anonymous',null);" }.join("\n")}
    do $$ begin
      if (select count(*) from public.payments where collection_id='#{GROUP}' and member_record_id='#{MEMBER}')<>5
        or (select count(*) from public.admin_user_roles where user_id in ('#{MAKER}','#{CHECKER}') and revoked_at is null)<>2
        then raise exception 'Synthetic member bindings or independent approvals missing'; end if;
    end $$;
  SQL
  worker_a=worker_start(WORKER_A,workers); worker_b=worker_start(WORKER_B,workers)

  # One finalizer completes SQL but holds its transaction. Another actual
  # service-role call waits on the outer roster and then observes replay.
  review=approved_review(payments[0],maker_session,checker_session); reviews << review
  begin_worker(worker_a,"#{finalizer(review)} select 'FIRST_FINALIZATION_HELD';")
  first=worker_read_until(worker_a,'FIRST_FINALIZATION_HELD')
  first_result=JSON.parse(first.find { |line| line.start_with?('RESULT:') }.delete_prefix('RESULT:'))
  begin_worker(worker_b,"#{finalizer(review)} commit; select 'DUPLICATE_FINALIZATION_DONE';")
  observed << {scenario:'duplicate_finalization',waiter:worker_b[:pid],blocker:worker_a[:pid],state:await_blocked(worker_b,worker_a)}
  assert_gate_precedes_financial_locks(worker_b)
  worker_write(worker_a,"commit; select 'FIRST_FINALIZATION_COMMITTED';\n")
  worker_read_until(worker_a,'FIRST_FINALIZATION_COMMITTED')
  second=worker_read_until(worker_b,'DUPLICATE_FINALIZATION_DONE')
  replay=JSON.parse(second.find { |line| line.start_with?('RESULT:') }.delete_prefix('RESULT:'))
  raise 'Duplicate finalization did not produce one posting and one replay' unless
    first_result['payment_id']==payments[0] && first_result['replayed']==false &&
    replay['payment_id']==payments[0] && replay['replayed']==true
  postings << verify_posting(payments[0],1234)

  # Actual Auth deletion commits before a queued finalizer. Its exclusive
  # statement gate must precede the finalizer's roster/review/payment locks.
  review=approved_review(payments[1],maker_session,checker_session); reviews << review
  unchanged=financial_digest(payments[1])
  begin_worker(worker_b,"delete from auth.sessions where id='#{checker_session}'; select 'AUTH_REVOKE_HELD';")
  worker_read_until(worker_b,'AUTH_REVOKE_HELD')
  begin_worker(worker_a,"#{expect_finalizer_denied(review)} commit; select 'REVOKE_FIRST_DENIED';")
  observed << {scenario:'auth_revoke_first',waiter:worker_a[:pid],blocker:worker_b[:pid],state:await_blocked(worker_a,worker_b)}
  assert_gate_precedes_financial_locks(worker_a)
  assert_auth_wait_precedes_roster_lock(worker_a)
  worker_write(worker_b,"commit; select 'AUTH_REVOKE_COMMITTED';\n")
  worker_read_until(worker_b,'AUTH_REVOKE_COMMITTED'); worker_read_until(worker_a,'REVOKE_FIRST_DENIED')
  raise 'Revoke-first denial changed financial/review/payment audit rows' unless financial_digest(payments[1])==unchanged
  checker_session=new_session(CHECKER,14)

  # The opposite order is allowed to finish once. Auth deletion waits for the
  # complete transaction, including journal constraints, then revokes normally.
  review=approved_review(payments[2],maker_session,checker_session); reviews << review
  begin_worker(worker_a,"#{finalizer(review)} select 'FINALIZE_BEFORE_AUTH_HELD';")
  worker_read_until(worker_a,'FINALIZE_BEFORE_AUTH_HELD')
  begin_worker(worker_b,"delete from auth.sessions where id='#{checker_session}'; commit; select 'AUTH_AFTER_FINALIZE_DONE';")
  observed << {scenario:'finalize_before_auth_revoke',waiter:worker_b[:pid],blocker:worker_a[:pid],state:await_blocked(worker_b,worker_a)}
  worker_write(worker_a,"commit; select 'FINALIZE_BEFORE_AUTH_COMMITTED';\n")
  worker_read_until(worker_a,'FINALIZE_BEFORE_AUTH_COMMITTED'); worker_read_until(worker_b,'AUTH_AFTER_FINALIZE_DONE')
  raise 'Auth revocation did not commit after finalization' unless query("select not exists(select 1 from auth.sessions where id='#{checker_session}');")=='t'
  postings << verify_posting(payments[2],1236)
  checker_session=new_session(CHECKER,15)

  # Role revocation uses the actual gated Admin API; it shares the Auth gate
  # then owns the roster lock. The finalizer must see revocation after waiting.
  review=approved_review(payments[3],maker_session,checker_session); reviews << review
  unchanged=financial_digest(payments[3])
  begin_worker(worker_b,"#{actor(CHECKER,checker_session)} select public.admin_set_user_access('#{MAKER}',false,'Synthetic race role revocation'); select 'ROLE_REVOKE_HELD';")
  worker_read_until(worker_b,'ROLE_REVOKE_HELD')
  begin_worker(worker_a,"#{expect_finalizer_denied(review)} commit; select 'ROLE_REVOKE_FIRST_DENIED';")
  observed << {scenario:'role_revoke_first',waiter:worker_a[:pid],blocker:worker_b[:pid],state:await_blocked(worker_a,worker_b)}
  assert_gate_precedes_financial_locks(worker_a)
  worker_write(worker_b,"commit; select 'ROLE_REVOKE_COMMITTED';\n")
  worker_read_until(worker_b,'ROLE_REVOKE_COMMITTED'); worker_read_until(worker_a,'ROLE_REVOKE_FIRST_DENIED')
  raise 'Role-revoked denial changed financial/review/payment audit rows' unless financial_digest(payments[3])==unchanged

  # Reactivation itself requires the approved identity, and a fresh Auth session
  # after the new role grant. Old review/session evidence is not rewritten.
  query("#{actor(CHECKER,checker_session)} select public.admin_set_user_access('#{MAKER}',true,'Synthetic fresh role grant for reverse race');",transaction: true)
  maker_session=new_session(MAKER,16)
  review=approved_review(payments[4],maker_session,checker_session); reviews << review
  begin_worker(worker_a,"#{finalizer(review)} select 'FINALIZE_BEFORE_ROLE_HELD';")
  worker_read_until(worker_a,'FINALIZE_BEFORE_ROLE_HELD')
  begin_worker(worker_b,"#{actor(CHECKER,checker_session)} select public.admin_set_user_access('#{MAKER}',false,'Synthetic role revocation after posting'); commit; select 'ROLE_AFTER_FINALIZE_DONE';")
  observed << {scenario:'finalize_before_role_revoke',waiter:worker_b[:pid],blocker:worker_a[:pid],state:await_blocked(worker_b,worker_a)}
  worker_write(worker_a,"commit; select 'FINALIZE_BEFORE_ROLE_COMMITTED';\n")
  worker_read_until(worker_a,'FINALIZE_BEFORE_ROLE_COMMITTED'); worker_read_until(worker_b,'ROLE_AFTER_FINALIZE_DONE')
  postings << verify_posting(payments[4],1238)
  query(<<~SQL)
    do $$ begin
      if exists(select 1 from public.admin_user_roles where user_id='#{MAKER}' and revoked_at is null)
        or (select confirmed_rwf from collect_hybrid.collection_balances where collection_id='#{GROUP}') is distinct from 3708
        or (select confirmed_rwf from collect_hybrid.member_balances where collection_id='#{GROUP}' and member_record_id='#{MEMBER}') is distinct from 3708
        or (select count(*) from public.payments where collection_id='#{GROUP}' and status='review')<>2 then
        raise exception 'Final race balance/role/denial state mismatch'; end if;
    end $$;
  SQL
  result={status:'pass',fixture:PROJECT,migration_count:141,provider_calls:0,worker_sessions:2,
    scenarios:observed,postings:postings,duplicate_finalization_replayed:true,
    auth_revoke_first_preserved_financial_data:true,auth_wait_has_no_granted_roster_lock:true,
    role_revoke_first_preserved_financial_data:true,
    finalize_first_auth_and_role_revocations_serialized:true,gateway_wrapper_grants_closed:true,
    confirmed_group_and_member_balance_rwf:3708,
    source_sha256:Digest::SHA256.file(__FILE__).hexdigest,
    migration_sha256:Digest::SHA256.file(File.join(ROOT,'supabase/migrations',MIGRATION)).hexdigest}
rescue StandardError => error
  failure=error
ensure
  begin
    workers.each { |worker| worker[:input].close unless worker[:input].closed? }
    workers.each do |worker|
      begin
        Timeout.timeout(5) { worker[:thread].value }
      rescue Timeout::Error
        raise 'Cleanup cannot terminate an unverified backend' unless worker[:pid]
        query("select pg_terminate_backend(pid) from pg_stat_activity where pid=#{worker[:pid]} and application_name='#{worker[:name]}';")
        Timeout.timeout(5) { worker[:thread].value }
      end
      trailing=worker[:output].read
      trailing.lines.grep(/^XID:/).each { |line| TRACKED_XIDS << line.strip.delete_prefix('XID:') }
      stderr=worker[:error].read
      raise "Worker #{worker[:name]} failed: #{stderr}" unless worker[:thread].value.success? || failure
    end
    raise 'Workers remain; cleanup refused' unless query("select count(*) from pg_stat_activity where application_name in ('#{WORKER_A}','#{WORKER_B}');").to_i.zero?
    if seed_authorized
      raise 'Catalog changed; exact cleanup refused' unless application_tables==tables && control_digest==controls_before
      raise 'Invalid observed transaction identity; cleanup refused' unless TRACKED_XIDS.all? { |xid| xid.match?(/\A[0-9]+\z/) }
      cleanup_transactions=TRACKED_XIDS.uniq.map { |xid| "'#{xid}'" }.join(',')
      trigger_values=IMMUTABLE.map { |table,name| "('#{table}'::regclass,'#{name}')" }.join(',')
      union=tables.map { |table| "select '#{table}'::text family,to_jsonb(t) body from #{table} t" }.join(' union all ')
      full_digest_sql="with rows as (#{union}) select encode(extensions.digest(coalesce(string_agg(family||':'||body::text,E'\\n' order by family,body::text),''),'sha256'),'hex') from rows"
      query(<<~SQL,transaction: true)
        -- QA ONLY. All worker backends have exited. Any assertion/DELETE error
        -- rolls back both data cleanup and trigger states in this transaction.
        select pg_advisory_xact_lock(193517,141);
        set local lock_timeout='5s';
        lock table #{IMMUTABLE.keys.join(',')} in access exclusive mode;
        do $$ declare item record; fk record; referenced boolean;
          fresh_ids uuid[]:=array['#{MAKER}','#{CHECKER}','#{MEMBER}','#{GROUP}',#{payments.map { |v| "'#{v}'" }.join(',')}]::uuid[];
          member_ids uuid[]:=array['#{MAKER}','#{CHECKER}','#{MEMBER}']::uuid[];
          allowed_children regclass[]:=array['auth.sessions'::regclass,'public.profiles'::regclass,
            'public.admin_user_roles'::regclass,'collect_admin_access.whatsapp_approvals'::regclass,
            'collect_hybrid.member_records'::regclass,'public.notification_preferences'::regclass,
            'public.collections'::regclass,'public.payments'::regclass,'public.notification_events'::regclass,
            'public.notification_deliveries'::regclass,'public.notification_delivery_attempts'::regclass,
            'collect_security.reconciliation_reviews'::regclass,'public.provider_finality_requests'::regclass,
            'public.payment_provider_confirmations'::regclass,'public.ledger_entries'::regclass,
            'collect_hybrid.momo_journal_entries'::regclass,'collect_hybrid.momo_journal_lines'::regclass,
            'collect_hybrid.momo_balance_snapshots'::regclass,'collect_hybrid.collection_balances'::regclass,
            'collect_hybrid.member_balances'::regclass,'public.audit_logs'::regclass];
        begin
          if current_user<>'postgres' or current_setting('cron.launch_active_jobs')<>'off'
            or current_setting('pg_net.batch_size')<>'0'
            or (select count(*) from supabase_migrations.schema_migrations)<>141
            or (select max(version) from supabase_migrations.schema_migrations)<>'20260929180000'
            or exists(select 1 from pg_stat_activity where pid<>pg_backend_pid() and backend_type='client backend'
              and state<>'idle') then raise exception 'Quiet exact owner-only cleanup precondition lost'; end if;
          for item in select * from (values #{trigger_values}) expected(relation,name) loop
            if (select count(*) from pg_trigger where tgrelid=item.relation and tgname=item.name
                and not tgisinternal and tgenabled='O')<>1
              or exists(select 1 from pg_trigger where tgrelid=item.relation and not tgisinternal
                and (tgtype::integer & 2)=2 and (tgtype::integer & 8)=8 and tgname<>item.name) then
              raise exception 'Unknown/disabled immutable DELETE trigger on %; cleanup refused',item.relation; end if;
          end loop;
          select fresh_ids||coalesce(array_agg(id),'{}'::uuid[]) into fresh_ids
            from collect_security.reconciliation_reviews where payment_id=any(fresh_ids);
          select fresh_ids||coalesce(array_agg(id),'{}'::uuid[]) into fresh_ids
            from collect_hybrid.momo_journal_entries where payment_id=any(fresh_ids);
          select fresh_ids||coalesce(array_agg(id),'{}'::uuid[]) into fresh_ids
            from public.notification_events where user_id=any(member_ids);
          -- Unknown incoming references must be absent; never let a cascade
          -- silently remove an unexpected child outside this synthetic graph.
          for fk in select c.conrelid::regclass child,c.confrelid::regclass parent,
            (select string_agg(format('child.%I=parent.%I',ca.attname,pa.attname),' and ' order by k.ordinality)
              from unnest(c.conkey,c.confkey) with ordinality k(child_col,parent_col,ordinality)
              join pg_attribute ca on ca.attrelid=c.conrelid and ca.attnum=k.child_col
              join pg_attribute pa on pa.attrelid=c.confrelid and pa.attnum=k.parent_col) predicate
            from pg_constraint c where c.contype='f'
            and c.confrelid in ('auth.users'::regclass,'public.profiles'::regclass,'public.collections'::regclass,
              'public.payments'::regclass,'collect_hybrid.member_records'::regclass,
              'collect_hybrid.momo_journal_entries'::regclass,'public.notification_events'::regclass)
            and not c.conrelid=any(allowed_children) loop
            execute format('select exists(select 1 from %s child join %s parent on %s where parent.id=any($1))',fk.child,fk.parent,fk.predicate)
              into referenced using fresh_ids;
            if referenced then raise exception 'Unknown synthetic reference in %; cleanup refused',fk.child; end if;
          end loop;
        end $$;
        #{IMMUTABLE.map { |table,name| "alter table #{table} disable trigger #{name};" }.join("\n")}
        delete from public.notification_events where user_id in ('#{MAKER}','#{CHECKER}','#{MEMBER}');
        delete from collect_security.reconciliation_reviews where payment_id in (#{payments.map { |v| "'#{v}'" }.join(',')});
        delete from public.provider_finality_requests where payment_id in (#{payments.map { |v| "'#{v}'" }.join(',')});
        delete from public.payment_provider_confirmations where payment_id in (#{payments.map { |v| "'#{v}'" }.join(',')});
        delete from public.ledger_entries where payment_id in (#{payments.map { |v| "'#{v}'" }.join(',')});
        delete from collect_hybrid.momo_balance_snapshots where collection_id='#{GROUP}';
        delete from collect_hybrid.momo_journal_lines where journal_entry_id in
          (select id from collect_hybrid.momo_journal_entries where collection_id='#{GROUP}');
        delete from collect_hybrid.momo_journal_entries where collection_id='#{GROUP}';
        delete from collect_hybrid.member_balances where collection_id='#{GROUP}';
        delete from collect_hybrid.collection_balances where collection_id='#{GROUP}';
        delete from public.payments where id in (#{payments.map { |v| "'#{v}'" }.join(',')});
        delete from public.collections where id='#{GROUP}';
        delete from public.audit_logs where entity_id in ('#{MAKER}','#{CHECKER}','#{MEMBER}','#{GROUP}',#{payments.map { |v| "'#{v}'" }.join(',')})
          or actor_user_id in ('#{MAKER}','#{CHECKER}','#{MEMBER}');
        delete from auth.users where id in ('#{MAKER}','#{CHECKER}','#{MEMBER}');
        do $$ declare fk record; referenced boolean;
          member_ids uuid[]:=array['#{MAKER}','#{CHECKER}','#{MEMBER}']::uuid[];
        begin
          if exists(select 1 from auth.users where id=any(member_ids))
            or exists(select 1 from collect_hybrid.member_records where id=any(member_ids) and linked_user_id is not null)
            then raise exception 'Synthetic member still linked; cleanup refused'; end if;
          for fk in select c.conrelid::regclass relation,a.attname,cardinality(c.conkey) key_count
            from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
            where c.contype='f' and c.confrelid='collect_hybrid.member_records'::regclass loop
            if fk.key_count<>1 then raise exception 'Unexpected composite member reference'; end if;
            execute format('select exists(select 1 from %s where %I=any($1))',fk.relation,fk.attname) into referenced using member_ids;
            if referenced then raise exception 'Synthetic member still referenced by %',fk.relation; end if;
          end loop;
          delete from collect_hybrid.member_records where id=any(member_ids) and linked_user_id is null;
        end $$;
        #{IMMUTABLE.map { |table,name| "alter table #{table} enable trigger #{name};" }.join("\n")}
        -- These rows have no entity foreign key. Match only observed test XIDs
        -- plus this cleanup transaction; preserve all pre-existing events.
        delete from public.app_realtime_events where xmin::text in (#{cleanup_transactions})
          or xmin::text=pg_current_xact_id()::text;
        do $$ begin
          if (#{full_digest_sql})<>'#{baseline}' then raise exception 'Full baseline data restoration failed; cleanup rolled back'; end if;
          if (#{control_digest_sql.strip.delete_suffix(';')})<>'#{controls_before}' then
            raise exception 'Trigger/ACL/function fingerprint restoration failed; cleanup rolled back'; end if;
        end $$;
      SQL
      after=data_digest(tables); controls_after=control_digest
      raise 'Post-commit baseline/controls differ' unless after==baseline && controls_after==controls_before
      if result
        result[:synthetic_graph_removed]=true
        result[:worker_sessions_remaining]=0
        result[:baseline_table_count]=tables.length
        result[:baseline_tables]=tables
        result[:baseline_sha256_before]=baseline; result[:baseline_sha256_after]=after
        result[:controls_sha256_before]=controls_before; result[:controls_sha256_after]=controls_after
        result[:qa_only_temporarily_disabled_triggers]=IMMUTABLE
        result[:captured_transaction_ids]=TRACKED_XIDS.uniq
        result[:sequence_counters_restored]=false
        result[:sequence_note]='Data/trigger/ACL restoration is proven; PostgreSQL sequence allocation is not rolled back or reset.'
      end
    end
  rescue StandardError => error
    cleanup_failure=error
  end
end
raise "#{failure&.message}\nCleanup failed: #{cleanup_failure.message}" if cleanup_failure
raise failure if failure
puts JSON.pretty_generate(result)
