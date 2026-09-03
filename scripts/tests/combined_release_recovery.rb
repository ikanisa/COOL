# Full logical restore rehearsal using synthetic local data only. Fixed targets;
# no .env, remote URLs, production credentials, reset, clean or force options.
require 'json'
require 'open3'
require 'digest'
require 'fileutils'
require 'time'

abort('Usage: combined_release_recovery.rb [--resume-snapshot]') unless ARGV.empty? || ARGV==['--resume-snapshot']
RESUME_SNAPSHOT = ARGV==['--resume-snapshot']

BASE = 'postgres'.freeze
SOURCE = 'collect_combined_recovery_source_20260902'.freeze
RESTORED = 'collect_combined_recovery_restored_20260902'.freeze
PACKET = '/tmp/collect-release-recovery-20260902'.freeze
raw, error, status = Open3.capture3('docker','inspect','supabase_db_collect_release_replay_20260902')
abort('Local database container unavailable') unless status.success?
LOCAL_PASSWORD = JSON.parse(raw).first.fetch('Config').fetch('Env').to_h { |v| v.split('=',2) }.fetch('POSTGRES_PASSWORD')

def run(*command, input: '', env: {})
  out, error, status = Open3.capture3(env,*command, stdin_data: input, binmode: true)
  raise "Local recovery command failed: #{error.gsub(LOCAL_PASSWORD,'[LOCAL_PASSWORD]')}" unless status.success?
  out
end

def sql(database, statement)
  raise 'Unapproved local database' unless [BASE,SOURCE,RESTORED].include?(database)
  run('docker','exec','-i','supabase_db_collect_release_replay_20260902','psql','-XqAt','-U','postgres','-d',database,
    '-v','ON_ERROR_STOP=1',input: statement).strip
end

def dump(database)
  raise 'Unapproved dump source' unless [BASE,SOURCE].include?(database)
  run('docker','exec','supabase_db_collect_release_replay_20260902','pg_dump','-U','postgres','-d',database,
    '--format=custom','--lock-wait-timeout=5s','--no-subscriptions')
end

def create_and_restore(database, archive)
  raise 'Unapproved restore target' unless [SOURCE,RESTORED].include?(database)
  if sql(BASE,"select count(*) from pg_database where datname='#{database}';")=='0'
    run('docker','exec','supabase_db_collect_release_replay_20260902','createdb','-U','postgres','--template=template0',database)
  else
    # Only the exact empty source left by the transactional ownership failure
    # may be retried. Never overwrite an existing restored/populated database.
    empty = database==SOURCE && sql(database, "select not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname not in ('pg_catalog','information_schema') and c.relkind in ('r','v','S'));")=='t'
    raise 'Target already populated; refusing overwrite' unless empty
  end
  # pg_cron can be installed only in cron.database_name. Change this setting
  # only on this dedicated local container; keep all scheduled execution off.
  # Restore the setting even after a failed import. No extension is omitted.
  begin
    configure_cron_database(database)
    run('docker','exec','-i','--env','PGPASSWORD','supabase_db_collect_release_replay_20260902','pg_restore','-w','-U','supabase_admin','-d',database,
      '--single-transaction','--exit-on-error',input: archive,env: {'PGPASSWORD'=>LOCAL_PASSWORD})
  ensure
    configure_cron_database('postgres')
  end
end

def configure_cron_database(database)
  raise 'Unexpected scheduler database' unless [BASE,SOURCE,RESTORED].include?(database)
  run('docker','exec','-i','--env','PGPASSWORD','supabase_db_collect_release_replay_20260902',
    'psql','-w','-XqAt','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1',
    input: "alter system set cron.database_name='#{database}';\nalter system set cron.launch_active_jobs='off';",
    env: {'PGPASSWORD'=>LOCAL_PASSWORD})
  run('docker','restart','supabase_db_collect_release_replay_20260902')
  30.times do
    _out,_err,status=Open3.capture3('docker','exec','supabase_db_collect_release_replay_20260902',
      'pg_isready','-U','postgres','-d','postgres')
    if status.success?
      raise 'Scheduler must remain disabled' unless sql(BASE,"select current_setting('cron.launch_active_jobs')='off' and current_setting('cron.database_name')='#{database}';")=='t'
      return
    end
    sleep 0.5
  end
  raise 'Dedicated local restore container did not restart'
end

def fingerprint(database)
  tables = JSON.parse(sql(database, <<~SQL))
    select jsonb_agg(n.nspname||'.'||c.relname order by n.nspname,c.relname)
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where c.relkind='r' and n.nspname in ('public','auth','private','collect_member_actions','collect_admin_access','collect_hybrid','storage','supabase_migrations');
  SQL
  table_hashes = tables.to_h do |table|
    raise 'Unexpected relation identifier' unless table.match?(/\A[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*\z/)
    value = JSON.parse(sql(database, <<~SQL))
      set timezone='UTC';
      select jsonb_build_object('rows',count(*),'sha256',encode(extensions.digest(
        coalesce(string_agg(to_jsonb(t)::text,'' order by to_jsonb(t)::text),''),'sha256'),'hex')) from #{table} t;
    SQL
    [table,value]
  end
  schema = sql(database, <<~SQL)
    select jsonb_build_object(
      'functions',(select jsonb_agg(jsonb_build_array(n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),
        pg_get_functiondef(p.oid),p.proacl::text,pg_get_userbyid(p.proowner)) order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid))
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','auth','private','collect_member_actions','collect_admin_access','collect_hybrid','storage') and p.prokind='f'),
      'relations',(select jsonb_agg(jsonb_build_array(n.nspname,c.relname,c.relkind,c.relrowsecurity,c.relforcerowsecurity,c.relacl::text,
        pg_get_userbyid(c.relowner)) order by n.nspname,c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname in ('public','auth','private','collect_member_actions','collect_admin_access','collect_hybrid','storage') and c.relkind in ('r','v','S')),
      'columns',(select jsonb_agg(jsonb_build_array(n.nspname,c.relname,a.attnum,a.attname,format_type(a.atttypid,a.atttypmod),
        a.attnotnull,a.attidentity,a.attgenerated,pg_get_expr(d.adbin,d.adrelid)) order by n.nspname,c.relname,a.attnum)
        from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace
        left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
        where n.nspname in ('public','auth','private','collect_member_actions','collect_admin_access','collect_hybrid','storage') and c.relkind in ('r','v') and a.attnum>0 and not a.attisdropped),
      'views',(select jsonb_agg(jsonb_build_array(n.nspname,c.relname,pg_get_viewdef(c.oid)) order by n.nspname,c.relname)
        from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='v' and n.nspname in ('public','auth','private','collect_member_actions','collect_admin_access','collect_hybrid','storage')),
      'indexes',(select jsonb_agg(jsonb_build_array(n.nspname,c.relname,pg_get_indexdef(c.oid)) order by n.nspname,c.relname)
        from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='i' and n.nspname in ('public','auth','private','collect_member_actions','collect_admin_access','collect_hybrid','storage')),
      'triggers',(select jsonb_agg(jsonb_build_array(n.nspname,c.relname,t.tgname,pg_get_triggerdef(t.oid)) order by n.nspname,c.relname,t.tgname)
        from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
        where not t.tgisinternal and n.nspname in ('public','auth','private','collect_member_actions','collect_admin_access','collect_hybrid','storage')),
      'policies',(select jsonb_agg(to_jsonb(p) order by schemaname,tablename,policyname) from pg_policies p
        where schemaname in ('public','auth','private','collect_member_actions','collect_admin_access','collect_hybrid','storage')),
      'constraints',(select jsonb_agg(jsonb_build_array(n.nspname,c.relname,k.conname,pg_get_constraintdef(k.oid)) order by n.nspname,c.relname,k.conname)
        from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace
        where n.nspname in ('public','auth','private','collect_member_actions','collect_admin_access','collect_hybrid','storage')));
  SQL
  sequences = JSON.parse(sql(database, "select coalesce(jsonb_agg(n.nspname||'.'||c.relname order by n.nspname,c.relname),'[]') from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='S' and n.nspname in ('public','auth','private','collect_member_actions','collect_admin_access','collect_hybrid','storage');"))
  sequence_values = sequences.to_h do |sequence|
    raise 'Unexpected sequence identifier' unless sequence.match?(/\A[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*\z/)
    [sequence,JSON.parse(sql(database,"select jsonb_build_array(last_value,is_called) from #{sequence};"))]
  end
  {tables: table_hashes, sequences: sequence_values, schema_sha256: Digest::SHA256.hexdigest(schema)}
end

raise 'Wrong local source' unless sql(BASE,'select current_database();')==BASE
raise 'Unexpected source migration version' unless sql(BASE,'select count(*) from supabase_migrations.schema_migrations;')=='111'
raise 'Base contains non-UAT accounts or real financial records' unless sql(BASE, <<~SQL)=='t'
  select not exists(select 1 from auth.users where id not in
    ('99100000-0000-4000-8000-000000000001'))
    and not exists(select 1 from public.raw_payment_sms) and not exists(select 1 from public.payments)
    and not exists(select 1 from public.bank_transactions) and not exists(select 1 from auth.sessions)
    and not exists(select 1 from auth.refresh_tokens) and not exists(select 1 from pg_subscription);
SQL
actor='99000000-0000-4000-8000-000000000001'
group='99000000-0000-4000-8000-000000000010'
payment='99000000-0000-4000-8000-000000000020'
unless RESUME_SNAPSHOT
baseline_dump = dump(BASE)
create_and_restore(SOURCE,baseline_dump)
sql(SOURCE, <<~SQL)
  begin;
  insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
  values ('#{actor}','authenticated','authenticated','250788990001',now(),'{}','{}');
  insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type)
  values ('#{group}','recovery-synthetic','#{actor}','Synthetic recovery ledger','Other','private','private','other');
  insert into public.collection_members(collection_id,user_id,role,status) values ('#{group}','#{actor}','owner','active');
  insert into public.payments(id,collection_id,contributor_user_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,source)
  values ('#{payment}','#{group}','#{actor}','#{actor}',repeat('a',64),1234,'RECOVERY-SYNTHETIC-1','manual_admin');
  insert into public.ledger_entries(payment_id,collection_id,user_id,entry_type,amount_rwf)
  values ('#{payment}','#{group}','#{actor}','member_credit',1234),('#{payment}','#{group}',null,'collection_credit',1234);
  commit;
SQL
end
raise 'Unexpected recovery fixture state' unless sql(SOURCE, <<~SQL)=='t'
  select (select count(*)=2 from auth.users)
    and not exists(select 1 from auth.users where id not in ('#{actor}','99100000-0000-4000-8000-000000000001'))
    and (select count(*)=1 and bool_and(id='#{payment}' and amount_rwf=1234 and transaction_id='RECOVERY-SYNTHETIC-1') from public.payments)
    and (select count(*)=2 from public.ledger_entries)
    and not exists(select 1 from public.raw_payment_sms)
    and not exists(select 1 from public.bank_transactions)
    and not exists(select 1 from auth.sessions)
    and (select count(*)=111 from supabase_migrations.schema_migrations);
SQL
before = fingerprint(SOURCE)
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
archive = dump(SOURCE)
directory = PACKET+'/backend/recovery-synthetic'
FileUtils.mkdir_p(directory,mode:0700)
archive_path=directory+'/collect_synthetic_full_v111.dump'
raise 'Archive already exists; refusing overwrite' if File.exist?(archive_path)
File.open(archive_path,File::WRONLY|File::CREAT|File::EXCL,0600) { |file| file.write(archive) }
dump_seconds=Process.clock_gettime(Process::CLOCK_MONOTONIC)-started
started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
create_and_restore(RESTORED,archive)
restore_seconds=Process.clock_gettime(Process::CLOCK_MONOTONIC)-started
after=fingerprint(RESTORED)
raise 'Restored table or schema fingerprints differ' unless before==after
raise 'Restored authorization invariants differ' unless sql(RESTORED, <<~SQL)=='t'
  select (select count(*)=74 and bool_and(relrowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r')
    and not has_table_privilege('authenticated','public.profiles','select')
    and not has_function_privilege('anon','public.list_current_member_group_roster(uuid)','execute')
    and has_function_privilege('authenticated','public.list_current_member_group_roster(uuid)','execute');
SQL
readback=JSON.parse(sql(RESTORED, <<~SQL).lines.last)
  begin read only;
  set local role authenticated;
  set local request.jwt.claims='{"sub":"#{actor}","role":"authenticated"}';
  select jsonb_build_object('history',public.list_current_member_payment_history(),
    'history_page',public.list_current_member_history_page(),
    'recent_intents',public.list_current_member_recent_intents(),
    'balances',public.list_current_member_collection_balances(),'roster',public.list_current_member_group_roster('#{group}'));
  rollback;
SQL
raise 'Restored financial API readback failed' unless readback['history'].length==1 && readback['history'].first['amount_minor']==1234 &&
  readback['roster'].one? && readback['roster'].first['contributions']==[{'currency'=>'RWF','amount_minor'=>1234}]
page=readback.fetch('history_page')
raise 'Restored bounded history contract differs' unless page.fetch('items')==readback['history'] && page.fetch('total_count')==1 &&
  page.fetch('totals')=={'RWF'=>1234} && page.fetch('own_totals')=={'RWF'=>1234} && page['next_cursor'].nil? &&
  readback.fetch('recent_intents').fetch('items')==[] && readback.fetch('recent_intents').fetch('pending_count')==0
balance=readback['balances'].find { |row| row['collection_id']==group }
raise 'Restored ledger totals differ' unless balance && balance['supporter_count']==1 && balance['balances']==[
  {'currency'=>'RWF','amount_raised_minor'=>1234,'current_user_balance_minor'=>1234}]
summary={captured_at:Time.now.utc.iso8601,status:'pass',mode:'synthetic local logical snapshot and new-database restore; not production RPO/RTO',
  source:SOURCE,restored:RESTORED,archive:archive_path,archive_bytes:archive.bytesize,archive_sha256:Digest::SHA256.hexdigest(archive),
  dump_seconds:dump_seconds.round(3),restore_seconds:restore_seconds.round(3),table_count:before[:tables].length,
  migration_count:after.fetch(:tables).fetch('supabase_migrations.schema_migrations').fetch('rows'),
  identical_tables_sequences_and_schema:true,rls_and_grants_preserved:true,financial_rpc_readback:true,bounded_history_rpc_readback:true,
  limitations:['Same PostgreSQL cluster and pre-existing global roles','No Storage object bytes in this synthetic drill',
    'No Edge/Auth provider settings, secrets, role passwords or signing material backed up','Not a production backup or restore drill'],
  fingerprints:after}
puts JSON.pretty_generate(summary)
