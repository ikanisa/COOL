# Recovery of platform approval/access state only. Exact synthetic local targets;
# this is not a production financial, Storage, secrets, or global-role backup.
require 'json'
require 'open3'
require 'digest'
require 'fileutils'
require 'time'
BASE='collect_platform_access_final_20260902'.freeze
abort('Usage: platform_admin_access_recovery.rb [--api-v2]') unless ARGV.empty? || ARGV==['--api-v2']
REVISION=ARGV==['--api-v2'] ? '_v2' : ''
SOURCE="collect_platform_recovery_source#{REVISION}_20260902".freeze
RESTORED="collect_platform_recovery_restored#{REVISION}_20260902".freeze
PACKET='/Volumes/PRO-G40/Agents/Codex/2026-05-15/Codex Professional Agents/desktop-output/flutter/engagements/collect/go-live-2026-09-02'.freeze
raw,err,status=Open3.capture3('docker','inspect','supabase_db_collect')
abort('Local database unavailable') unless status.success?
LOCAL_PASSWORD=JSON.parse(raw).first.fetch('Config').fetch('Env').to_h{|entry|entry.split('=',2)}.fetch('POSTGRES_PASSWORD')
def run(*args,input:'',env:{})
  out,err,status=Open3.capture3(env,*args,stdin_data:input,binmode:true)
  raise err.gsub(LOCAL_PASSWORD,'[LOCAL_PASSWORD]') unless status.success?
  out
end
def sql(db,statement)
  raise 'Unexpected local database' unless [BASE,SOURCE,RESTORED].include?(db)
  run('docker','exec','-i','supabase_db_collect','psql','-XqAt','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1',input:statement).strip
end
def dump(db)
  raise 'Unexpected dump source' unless [BASE,SOURCE].include?(db)
  run('docker','exec','supabase_db_collect','pg_dump','-U','postgres','-d',db,'--format=custom','--lock-wait-timeout=5s','--no-subscriptions')
end
def restore(db,archive)
  raise 'Unexpected restore destination' unless [SOURCE,RESTORED].include?(db)
  raise 'Refusing existing target' unless sql(BASE,"select count(*) from pg_database where datname='#{db}';")=='0'
  run('docker','exec','supabase_db_collect','createdb','-U','postgres','--template=template0',db)
  run('docker','exec','-i','--env','PGPASSWORD','supabase_db_collect','pg_restore','-w','-U','supabase_admin','-d',db,
    '--single-transaction','--exit-on-error',input:archive,env:{'PGPASSWORD'=>LOCAL_PASSWORD})
end
def fingerprint(db)
  tables=%w[auth.users auth.sessions collect_admin_access.whatsapp_approvals public.admin_user_roles public.audit_logs]
  records=tables.to_h do |table|
    result=sql(db,"set timezone='UTC'; select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]') from #{table} t;")
    [table,{rows:JSON.parse(result).length,sha256:Digest::SHA256.hexdigest(result)}]
  end
  schema=sql(db,<<~SQL)
    select jsonb_build_object(
      'functions',(select jsonb_agg(jsonb_build_array(n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),
        pg_get_functiondef(p.oid),p.proacl::text,pg_get_userbyid(p.proowner)) order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid))
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','auth','private','collect_member_actions','collect_admin_access') and p.prokind='f'),
      'relations',(select jsonb_agg(jsonb_build_array(n.nspname,c.relname,c.relkind,c.relrowsecurity,c.relforcerowsecurity,c.relacl::text,pg_get_userbyid(c.relowner)) order by n.nspname,c.relname)
        from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','auth','private','collect_member_actions','collect_admin_access') and c.relkind in ('r','v','S')),
      'namespaces',(select jsonb_agg(jsonb_build_array(nspname,nspacl::text,pg_get_userbyid(nspowner)) order by nspname)
        from pg_namespace where nspname in ('public','auth','private','collect_member_actions','collect_admin_access')),
      'policies',(select jsonb_agg(to_jsonb(p) order by schemaname,tablename,policyname) from pg_policies p
        where schemaname in ('public','auth','private','collect_member_actions','collect_admin_access')));
  SQL
  {records:records,functions_relations_rls_grants_ownership_sha256:Digest::SHA256.hexdigest(schema)}
end
raise 'Baseline must contain no user or financial records' unless sql(BASE,<<~SQL)=='t'
  select not exists(select 1 from auth.users) and not exists(select 1 from auth.sessions)
    and not exists(select 1 from public.payments) and not exists(select 1 from public.raw_payment_sms)
    and not exists(select 1 from public.bank_transactions) and not exists(select 1 from auth.refresh_tokens)
    and not exists(select 1 from collect_admin_access.whatsapp_approvals) and not exists(select 1 from pg_subscription);
SQL
restore(SOURCE,dump(BASE))
sql(SOURCE,<<~SQL)
  begin;
  insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
  select ('98600000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'authenticated','authenticated',
    '25078898600'||n,now(),'{}','{}' from generate_series(1,3)n;
  insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,reason,revoked_at)
  select id,'+'||phone,'Synthetic recovery approval',case when right(phone,1)='2' then clock_timestamp() else null end
    from auth.users where right(phone,1) in ('1','2');
  insert into public.admin_user_roles(user_id,role_id,reason,revoked_at)
  select u.id,r.id,'Synthetic recovery role',case when right(u.phone,1)='2' then clock_timestamp() else null end
    from auth.users u cross join public.admin_roles r where r.name='platform_owner';
  insert into auth.sessions(id,user_id,created_at)
  select ('98610000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
    ('98600000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,clock_timestamp() from generate_series(1,3)n;
  commit;
SQL
before=fingerprint(SOURCE)
archive=dump(SOURCE)
directory=PACKET+'/backend/recovery-synthetic'
FileUtils.mkdir_p(directory,mode:0700)
path=directory+"/collect_platform_approval_synthetic#{REVISION}.dump"
raise 'Archive exists; refusing overwrite' if File.exist?(path)
File.open(path,File::WRONLY|File::CREAT|File::EXCL,0600){|file|file.write(archive)}
started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
restore(RESTORED,archive)
seconds=Process.clock_gettime(Process::CLOCK_MONOTONIC)-started
after=fingerprint(RESTORED)
raise 'Recovered access data or schema differs' unless before==after
checks=[]
(1..3).each do |n|
  identity=JSON.parse(sql(RESTORED,<<~SQL).lines.last)
    begin read only;
    set local role authenticated;
    set local request.jwt.claims='{"sub":"98600000-0000-4000-8000-#{n.to_s.rjust(12,'0')}","role":"authenticated","session_id":"98610000-0000-4000-8000-#{n.to_s.rjust(12,'0')}"}';
    select public.admin_current_user();
    rollback;
  SQL
  raise 'Restored approval eligibility mismatch' unless n==1 ? identity['user_id']=='98600000-0000-4000-8000-000000000001' : identity=={}
  checks << {name:%w[approved_operator_allowed revoked_operator_denied unapproved_role_denied][n-1],status:'pass'}
end
raise 'Private approval privileges were lost' unless sql(RESTORED,<<~SQL)=='t'
  select (select relrowsecurity from pg_class where oid='collect_admin_access.whatsapp_approvals'::regclass)
    and not has_table_privilege('authenticated','collect_admin_access.whatsapp_approvals','select')
    and not has_function_privilege('authenticated','public.admin_bootstrap_whatsapp_approval(uuid,text,text)','execute');
SQL
puts JSON.pretty_generate(captured_at:Time.now.utc.iso8601,status:'pass',mode:'scoped synthetic platform-access recovery, same local cluster',
  source:SOURCE,restored:RESTORED,archive:path,archive_bytes:archive.bytesize,archive_sha256:Digest::SHA256.hexdigest(archive),
  restore_seconds:seconds.round(3),approval_data_and_access_schema_identical:true,private_rls_and_grants_preserved:true,
  fingerprint:after,checks:checks,
  limitations:['Five access-state tables fingerprinted, not every financial table','Same cluster and pre-existing global roles',
    'Synthetic session restoration, not real OTP or revocation-provider acceptance','No Storage bytes, provider settings/secrets, production RPO/RTO or production backup'])
