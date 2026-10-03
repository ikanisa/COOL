require 'open3'
require 'json'
require 'digest'
require 'timeout'

# NEW dedicated147 harness. Source-only until root invokes explicit offline guard.
ROOT=File.expand_path('../..',__dir__)
PROJECT='collect_fin_concurrency_qa_20260929'
CONTAINER="supabase_db_#{PROJECT}"
PREFIX='99730000'
ACTOR="#{PREFIX}-0000-4000-8000-000000000001"
CONTROLLER="#{PREFIX}-0000-4000-8000-000000000002"
CONTROL_SESSION="#{PREFIX}-0000-4000-8000-000000000012"
ACTOR_SESSION="#{PREFIX}-0000-4000-8000-000000000011"
WORKER_A='collect_runtime_147_a'
WORKER_B='collect_runtime_147_b'
FLAG='qa_runtime_147_concurrency'
TEMPLATE='qa_runtime_147_concurrency'
PHONE_HASH=Digest::SHA256.hexdigest('local-only-runtime-147-phone')
MIGRATION='supabase/migrations/20260930150000_runtime_control_governance.sql'
SCHEMAS="'public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations'"
PSQL=['docker','exec','-i',CONTAINER,'psql','-XqAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'].freeze
TRACKED_XIDS=[]
CHECKPOINT={}
CHECKPOINT_PATH=ENV['COLLECT_RUNTIME_CONTROL_CHECKPOINT']
def save_checkpoint
 return if CHECKPOINT.empty? || !CHECKPOINT_PATH
 CHECKPOINT['tracked_transaction_ids']=TRACKED_XIDS.uniq
 temp=CHECKPOINT_PATH+'.tmp'
 File.open(temp,File::WRONLY|File::CREAT|File::TRUNC,0600) {|f|f.write(JSON.pretty_generate(CHECKPOINT)+"\n");f.flush;f.fsync}
 File.rename(temp,CHECKPOINT_PATH)
end
def track_xid(xid)
 raise 'Malformed observed XID' unless xid.match?(/\A[0-9]+\z/)
 TRACKED_XIDS<<xid;save_checkpoint
end
def lit(value)
  value.nil? ? 'null' : "'#{value.to_s.gsub("'","''")}'"
end
def id(n)
  "#{PREFIX}-0000-4000-8000-#{format('%012d',n)}"
end
def query(sql, transaction: false)
  sql="begin; select 'XID:'||pg_current_xact_id();\n#{sql}\ncommit;" if transaction
  output,error,status=Open3.capture3(*PSQL,stdin_data:"set application_name='collect_runtime_147_control'; set statement_timeout='30s'; set lock_timeout='15s'; set timezone='UTC';\n#{sql}")
  output.lines.grep(/^XID:/).each { |line| track_xid(line.strip.delete_prefix('XID:')) }
  raise(error.empty? ? output : error) unless status.success?
  output.lines.reject { |line| line.start_with?('XID:') }.join.strip
end
def actor(session,user=ACTOR)
  "set local role authenticated; select set_config('request.jwt.claims',#{lit({sub:user,session_id:session,role:'authenticated',aal:'aal1'}.to_json)},true);"
end
def service
  "set local role service_role; select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
end
def result_from(output)
  line=(output.is_a?(Array) ? output : output.lines).find { |v| v.start_with?('RESULT:') }
  raise 'Missing typed RPC result' unless line
  JSON.parse(line.delete_prefix('RESULT:'))
end
def rejected(call,state,message)
  <<~SQL
    do $$ declare seen boolean:=false; begin
      begin perform #{call}; exception when sqlstate '#{state}' then
        if sqlerrm<>#{lit(message)} then raise; end if; seen:=true; end;
      if not seen then raise exception 'Expected denial #{message}'; end if;
    end $$;
  SQL
end
def snapshot_tables
  JSON.parse(query("select json_agg(format('%I.%I',n.nspname,c.relname) order by n.nspname,c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in ('r','p') and n.nspname in (#{SCHEMAS});"))
end
def digest_sql(tables)
  union=tables.map { |t| "select '#{t}'::text family,to_jsonb(t) body from #{t} t" }.join(' union all ')
  "with rows as (#{union}) select encode(extensions.digest(coalesce(string_agg(family||':'||body::text,E'\\n' order by family,body::text),''),'sha256'),'hex') from rows"
end
def fingerprints_sql(tables)
  parts=tables.map do |t|
    "select '#{t}' relation,count(*) row_count,encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by to_jsonb(t)::text),''),'sha256'),'hex') sha256 from #{t} t"
  end
  "select jsonb_object_agg(relation,jsonb_build_object('rows',row_count,'sha256',sha256)) from (#{parts.join(' union all ')}) fingerprints"
end
def controls_sql
  <<~SQL
    with controls(family,body) as (
      select 'trigger',jsonb_build_object('table',t.tgrelid::regclass::text,'name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid))
        from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in (#{SCHEMAS})
      union all select 'schema_acl',jsonb_build_object('schema',n.nspname,'owner',n.nspowner,'acl',n.nspacl)
        from pg_namespace n where n.nspname in (#{SCHEMAS})
      union all select 'relation_acl',jsonb_build_object('relation',c.oid::regclass::text,'owner',c.relowner,'acl',c.relacl,'rls',c.relrowsecurity,'force',c.relforcerowsecurity)
        from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in (#{SCHEMAS})
      union all select 'routine',jsonb_build_object('routine',p.oid::regprocedure::text,'owner',p.proowner,'acl',p.proacl,'source',p.prosrc,'config',p.proconfig,'security_definer',p.prosecdef)
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in (#{SCHEMAS})
      union all select 'column',jsonb_build_object('table',a.attrelid::regclass::text,'name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid))
        from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where n.nspname in (#{SCHEMAS}) and a.attnum>0 and not a.attisdropped
      union all select 'policy',jsonb_build_object('table',p.polrelid::regclass::text,'name',p.polname,'command',p.polcmd,'roles',p.polroles,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))
        from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in (#{SCHEMAS})
      union all select 'cron',jsonb_build_object('jobid',jobid,'active',active,'schedule',schedule,'command_sha256',encode(extensions.digest(command,'sha256'),'hex'),'jobname',jobname) from cron.job
      union all select 'constraint',jsonb_build_object('table',c.conrelid::regclass::text,'name',c.conname,'definition',pg_get_constraintdef(c.oid))
        from pg_constraint c join pg_namespace n on n.oid=c.connamespace where n.nspname in (#{SCHEMAS})
    ) select encode(extensions.digest(coalesce(string_agg(family||':'||body::text,E'\n' order by family,body::text),''),'sha256'),'hex') from controls
  SQL
end
def worker_start(name,workers)
  input,output,error,thread=Open3.popen3(*PSQL)
  w={name:name,input:input,output:output,error:error,thread:thread}; workers << w
  write(w,"set application_name='#{name}'; set statement_timeout='30s'; set timezone='UTC'; select 'PID:'||pg_backend_pid(); select 'READY';\n")
  w[:pid]=Integer(read_until(w,'READY').find { |line| line.start_with?('PID:') }.delete_prefix('PID:'))
  w
end
def write(w,sql)
  w[:input].write(sql); w[:input].flush
end
def read_until(w,marker)
  lines=[]
  Timeout.timeout(20) do
    loop do
      line=w[:output].gets
      raise "#{w[:name]} stopped: #{w[:error].read}" if line.nil?
      line=line.strip
      break if line==marker
      track_xid(line.delete_prefix('XID:')) if line.start_with?('XID:')
      lines << line
    end
  end
  lines
end
def start(w,sql,isolation: nil)
  opening=isolation ? "begin isolation level #{isolation}" : "begin"
  write(w,"#{opening}; select 'XID:'||pg_current_xact_id();\n#{sql}\n")
end
def blocked(waiter,holder)
  state=nil
  80.times do
    state=JSON.parse(query("select coalesce((select jsonb_build_object('pid',pid,'wait_type',wait_event_type,'wait_event',wait_event,'blocking_pids',pg_blocking_pids(pid)) from pg_stat_activity where pid=#{waiter[:pid]} and application_name='#{waiter[:name]}'),'{}'::jsonb);"))
    return state if state['wait_type']=='Lock' && Array(state['blocking_pids']).include?(holder[:pid])
    sleep 0.1
  end
  raise "Expected overlapping worker lock wait: #{state.inspect}"
end
def session(n)
  sid=id(10_000+n)
  query("insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values('#{sid}','#{ACTOR}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');",transaction:true)
  sid
end
def control_scope(alias_name='h')
 "(#{alias_name}.family in ('otp_policy','roster_resource_policy') or #{alias_name}.family='feature_flags' and #{alias_name}.identity->>'key' in ('#{FLAG}','hybrid_member_onboarding') or #{alias_name}.identity::text like '%#{PREFIX}-%' or #{alias_name}.identity->>'key'='#{TEMPLATE}')"
end
def owned_xids_sql
 scopes={
  'auth.users'=>"id in ('#{ACTOR}','#{CONTROLLER}')",'auth.sessions'=>"user_id in ('#{ACTOR}','#{CONTROLLER}')",
  'public.profiles'=>"id in ('#{ACTOR}','#{CONTROLLER}')",'public.admin_user_roles'=>"user_id in ('#{ACTOR}','#{CONTROLLER}')",
  'collect_admin_access.whatsapp_approvals'=>"user_id in ('#{ACTOR}','#{CONTROLLER}')",
  'collect_hybrid.member_records'=>"id in ('#{ACTOR}','#{CONTROLLER}')",
  'public.notification_preferences'=>"user_id in ('#{ACTOR}','#{CONTROLLER}')",
  'public.audit_logs'=>"actor_user_id in ('#{ACTOR}','#{CONTROLLER}')",
  'public.feature_flags'=>"key in ('#{FLAG}','hybrid_member_onboarding')",
  'public.policy_documents'=>"id::text like '#{PREFIX}-%'",'public.policy_document_sections'=>"id::text like '#{PREFIX}-%'",
  'public.notification_templates'=>"key='#{TEMPLATE}'",'public.notification_template_versions'=>"id::text like '#{PREFIX}-%'",
  'collect_security.runtime_control_heads'=>control_scope('t'),
  'collect_security.runtime_control_events'=>"actor_id in ('#{ACTOR}','#{CONTROLLER}') or identity_sha256 in (select collect_security.runtime_control_hash(identity) from collect_security.runtime_control_heads h where #{control_scope})",
  'collect_hybrid.roster_resource_reservations'=>"actor_id='#{ACTOR}' and request_id::text like '#{PREFIX}-%'",
  'collect_security.signed_otp_requests'=>"hook_id like 'qa_runtime_147_%' and phone_hash='#{PHONE_HASH}'",
  'collect_auth_security.otp_phone_locks'=>"phone_hash='#{PHONE_HASH}'",'public.otp_rate_limits'=>"phone_hash='#{PHONE_HASH}'"
 }
 union=scopes.map {|t,w|"select '#{t}' relation,xmin::text xmin,to_jsonb(t)-array['raw_app_meta_data','raw_user_meta_data','encrypted_password'] row_body from #{t} t where #{w}"}.join(' union all ')
 "select coalesce(jsonb_agg(jsonb_build_object('relation',relation,'xmin',xmin,'row',row_body) order by relation,row_body::text),'[]') from (#{union}) attribution"
end
def row_snapshot(relation,where)
 JSON.parse(query("select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]') from #{relation} t where #{where};"))
end
def restore_row(relation,rows,where)
 return "delete from #{relation} where #{where};" if rows.empty?
 raise 'Restore target must be one row' unless rows.length==1
 # Relation/where are fixed source literals. Baseline columns are catalog-owned.
 cols=rows.first.keys.sort.map {|x|raise('Malformed baseline column') unless x.match?(/\A[a-z_]+\z/);%Q{"#{x}"}}
 "update #{relation} t set (#{cols.join(',')})=(select #{cols.join(',')} from jsonb_populate_record(null::#{relation},#{lit(rows.first.to_json)}::jsonb)) where #{where};"
end
if __FILE__==$PROGRAM_NAME
 raise 'Set COLLECT_RUNTIME_CONTROLS_QA=isolated_clone' unless ENV['COLLECT_RUNTIME_CONTROLS_QA']=='isolated_clone'
 raise 'New absolute checkpoint required' unless CHECKPOINT_PATH && CHECKPOINT_PATH.start_with?('/') && !File.exist?(CHECKPOINT_PATH) && !File.symlink?(CHECKPOINT_PATH) && Dir.exist?(File.dirname(CHECKPOINT_PATH))
 migration_sha=ENV.fetch('COLLECT_RUNTIME_CONTROL_MIGRATION_SHA','')
 raise 'Exact frozen147 SHA required' unless migration_sha.match?(/\A[a-f0-9]{64}\z/) && Digest::SHA256.file(File.join(ROOT,MIGRATION)).hexdigest==migration_sha
 raw,err,status=Open3.capture3('docker','inspect',CONTAINER);raise err unless status.success?
 container=JSON.parse(raw).fetch(0);labels=container.fetch('Config').fetch('Labels');ports=container.fetch('HostConfig').fetch('PortBindings').fetch('5432/tcp')
 config=File.read(File.join(ROOT,'.cache/financial-concurrency-20260929/supabase/config.toml'));db=config[/^\[db\]\s*\n(.*?)(?=^\[|\z)/m,1]
 raise 'Exact project/port provenance required' unless container.dig('State','Running') && labels['com.supabase.cli.project']==PROJECT && labels['com.docker.compose.project']==PROJECT && config.match?(/^project_id = "#{PROJECT}"$/) && db&.match?(/^port = 55722$/) && !ports.empty? && ports.all? {|x|x['HostPort']=='55722'}
 query(<<~SQL)
  do $$ begin
   if current_user<>'postgres' or current_database()<>'postgres' or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
    or (select count(*) from supabase_migrations.schema_migrations)<>147 or (select max(version) from supabase_migrations.schema_migrations)<>'20260930150000'
    or exists(select 1 from auth.users where id::text like '#{PREFIX}-%' or phone in ('250788973001','250788973002'))
    or exists(select 1 from auth.sessions where id::text like '#{PREFIX}-%') or exists(select 1 from public.profiles where id::text like '#{PREFIX}-%')
    or exists(select 1 from public.feature_flags where key='#{FLAG}') or exists(select 1 from public.policy_documents where id::text like '#{PREFIX}-%')
    or exists(select 1 from public.notification_templates where key='#{TEMPLATE}')
    or exists(select 1 from collect_security.runtime_control_heads h where h.identity::text like '%#{PREFIX}-%' or h.identity->>'key'='#{FLAG}')
    or exists(select 1 from collect_security.signed_otp_requests where hook_id like 'qa_runtime_147_%')
    or exists(select 1 from public.otp_rate_limits where phone_hash='#{PHONE_HASH}') or exists(select 1 from collect_auth_security.otp_phone_locks where phone_hash='#{PHONE_HASH}')
    or exists(select 1 from collect_hybrid.roster_resource_reservations where actor_id in ('#{ACTOR}','#{CONTROLLER}') or request_id::text like '#{PREFIX}-%')
    or exists(select 1 from public.notification_device_tokens) or exists(select 1 from public.notification_deliveries)
    or exists(select 1 from pg_stat_activity where pid<>pg_backend_pid() and backend_type='client backend' and state<>'idle') then raise exception 'Exact quiet isolated147 and unused9973 namespace required';end if;
  end $$;
 SQL
 tables=snapshot_tables;before=query(digest_sql(tables)+';');controls_before=query(controls_sql+';');fingerprints=JSON.parse(query(fingerprints_sql(tables)+';'))
 originals={flag:row_snapshot('public.feature_flags',"key='hybrid_member_onboarding'"),otp:row_snapshot('collect_security.otp_policy','singleton'),roster:row_snapshot('collect_hybrid.roster_resource_policy','id'),heads:row_snapshot('collect_security.runtime_control_heads',control_scope('t'))}
 baseline_event_ids=JSON.parse(query("select coalesce(jsonb_agg(id order by id),'[]') from collect_security.runtime_control_events;"))
 CHECKPOINT.merge!('phase'=>'baseline_before_seed','fixture'=>PROJECT,'migration_sha256'=>migration_sha,'source_sha256'=>Digest::SHA256.file(__FILE__).hexdigest,'baseline_tables'=>tables,'baseline_sha256'=>before,'baseline_fingerprints'=>fingerprints,'controls_sha256'=>controls_before,'restore_rows'=>originals,'baseline_event_ids'=>baseline_event_ids)
 File.open(CHECKPOINT_PATH,File::WRONLY|File::CREAT|File::EXCL,0600) {|f|f.write(JSON.pretty_generate(CHECKPOINT)+"\n");f.flush;f.fsync}
 workers=[];seeded=false;failure=nil;cleanup_failure=nil;result=nil;observed=[]
 begin
  seeded=true
  query(<<~SQL,transaction:true)
   insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data) values
    ('#{ACTOR}','authenticated','authenticated','250788973001',now(),'{}','{}'),('#{CONTROLLER}','authenticated','authenticated','250788973002',now(),'{}','{}');
   update public.profiles set country_code='RW',currency_code='RWF' where id in ('#{ACTOR}','#{CONTROLLER}');
   insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason) values
    ('#{ACTOR}','+250788973001',clock_timestamp()-interval '2 minutes','Synthetic runtime actor approval'),('#{CONTROLLER}','+250788973002',clock_timestamp()-interval '2 minutes','Synthetic runtime controller approval');
   insert into public.admin_user_roles(user_id,role_id,reason,created_at) select x.id,r.id,'Synthetic runtime roles',clock_timestamp()-interval '1 minute' from (values('#{ACTOR}'::uuid),('#{CONTROLLER}'::uuid)) x(id) cross join public.admin_roles r where r.name='platform_owner';
   insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values
    ('#{ACTOR_SESSION}','#{ACTOR}',now(),now(),now()+interval '1 hour','aal1'),('#{CONTROL_SESSION}','#{CONTROLLER}',now(),now(),now()+interval '1 hour','aal1');
   insert into public.feature_flags(key,enabled,description) values('#{FLAG}',false,'Synthetic conflict flag');
   update public.feature_flags set enabled=true where key='hybrid_member_onboarding';
   insert into public.policy_documents(id,kind,locale,version,title) values('#{id(101)}','terms','en','qa-runtime-147-concurrent','Synthetic policy'),('#{id(102)}','terms','en','qa-runtime-147-edit-first','Synthetic policy'),('#{id(103)}','terms','en','qa-runtime-147-stale-publication','Synthetic policy');
   insert into public.policy_document_sections(id,policy_document_id,section_key,title,body) values('#{id(111)}','#{id(101)}','qa','Synthetic section','Synthetic body'),('#{id(112)}','#{id(102)}','qa','Synthetic section','Synthetic body'),('#{id(113)}','#{id(103)}','qa','Synthetic section','Synthetic body');
   insert into public.notification_templates(key,event_type_key,locale) values('#{TEMPLATE}','security_notice','en');
   insert into public.notification_template_versions(id,template_key,version,title_template,body_template) values('#{id(121)}','#{TEMPLATE}','qa-runtime-147-concurrent','Synthetic notice','Synthetic body');
   insert into collect_security.otp_policy(singleton,global_hourly_limit,global_daily_limit,enabled) values(true,100000,1000000,true)
    on conflict(singleton) do update set enabled=true,global_hourly_limit=100000,global_daily_limit=1000000;
  SQL
  a=worker_start(WORKER_A,workers);b=worker_start(WORKER_B,workers)
  flag=->(enabled,revision) {"public.admin_set_feature_flag_v2('#{FLAG}',#{enabled},#{revision},'Synthetic concurrent flag edit')"}
  start(a,"#{actor(ACTOR_SESSION)} select 'RESULT:'||#{flag.call(true,1)}::text;select 'FLAG_HELD';")
  winner=result_from(read_until(a,'FLAG_HELD'));raise 'First version invalid' unless winner['revision']==2 && winner['changed']
  start(b,"#{actor(CONTROL_SESSION,CONTROLLER)} #{rejected(flag.call(false,1),'40001','runtime_control_conflict')} commit;select 'FLAG_CONFLICT';")
  observed<<{scenario:'same_expected_revision_has_one_winner',state:blocked(b,a)}
  write(a,"commit;select 'FLAG_COMMIT';\n");read_until(a,'FLAG_COMMIT');read_until(b,'FLAG_CONFLICT')
  start(b,"select count(*) from collect_security.runtime_control_heads;select 'RR_SNAPSHOT';",isolation:'repeatable read');read_until(b,'RR_SNAPSHOT')
  start(a,"#{actor(ACTOR_SESSION)} select 'RESULT:'||#{flag.call(false,2)}::text;select 'RR_FLAG_HELD';");result_from(read_until(a,'RR_FLAG_HELD'))
  write(b,"#{actor(CONTROL_SESSION,CONTROLLER)} #{rejected(flag.call(true,2),'40001','could not serialize access due to concurrent update')} commit;select 'RR_CONFLICT';\n")
  observed<<{scenario:'stale_repeatable_read_configuration_conflicts',state:blocked(b,a)}
  write(a,"commit;select 'RR_COMMIT';\n");read_until(a,'RR_COMMIT');read_until(b,'RR_CONFLICT')
  publish="public.admin_update_runtime_control_v1('policy_documents','{\"id\":\"#{id(101)}\"}','{\"status\":\"published\"}',1,'Synthetic concurrent publication')"
  edit="public.admin_update_runtime_control_v1('policy_document_sections','{\"id\":\"#{id(111)}\"}','{\"body\":\"Late edit\"}',1,'Synthetic late section edit')"
  start(a,"#{actor(ACTOR_SESSION)} select #{publish};select 'PUBLISH_HELD';");read_until(a,'PUBLISH_HELD')
  start(b,"#{actor(CONTROL_SESSION,CONTROLLER)} #{rejected(edit,'55000','runtime_control_published_immutable')} commit;select 'SECTION_DENIED';")
  observed<<{scenario:'publication_fences_late_section_edit',state:blocked(b,a)}
  write(a,"commit;select 'PUBLISH_COMMIT';\n");read_until(a,'PUBLISH_COMMIT');read_until(b,'SECTION_DENIED')
  edited_publish="public.admin_update_runtime_control_v1('policy_documents','{\"id\":\"#{id(102)}\"}','{\"status\":\"published\"}',1,'Synthetic edit first publication')"
  early_edit="public.admin_update_runtime_control_v1('policy_document_sections','{\"id\":\"#{id(112)}\"}','{\"body\":\"Committed draft edit\"}',1,'Synthetic early section edit')"
  start(a,"#{actor(ACTOR_SESSION)} select #{early_edit};select 'EDIT_FIRST_HELD';");read_until(a,'EDIT_FIRST_HELD')
  start(b,"#{actor(CONTROL_SESSION,CONTROLLER)} select #{edited_publish};commit;select 'EDIT_FIRST_PUBLISHED';")
  observed<<{scenario:'draft_section_edit_precedes_publication',state:blocked(b,a)}
  write(a,"commit;select 'EDIT_FIRST_COMMIT';\n");read_until(a,'EDIT_FIRST_COMMIT');read_until(b,'EDIT_FIRST_PUBLISHED')
  raise 'Publication did not retain latest draft bytes' unless query("select body from public.policy_document_sections where id='#{id(112)}';")=='Committed draft edit'
  start(b,"select count(*) from public.policy_document_sections;select 'SECTION_RR_SNAPSHOT';",isolation:'repeatable read');read_until(b,'SECTION_RR_SNAPSHOT')
  stale_edit="public.admin_update_runtime_control_v1('policy_document_sections','{\"id\":\"#{id(113)}\"}','{\"body\":\"Committed snapshot fence edit\"}',1,'Synthetic section snapshot fence')"
  stale_publish="public.admin_update_runtime_control_v1('policy_documents','{\"id\":\"#{id(103)}\"}','{\"status\":\"published\"}',1,'Synthetic stale publication')"
  start(a,"#{actor(ACTOR_SESSION)} select #{stale_edit};select 'SECTION_RR_HELD';");read_until(a,'SECTION_RR_HELD')
  write(b,"#{actor(CONTROL_SESSION,CONTROLLER)} #{rejected(stale_publish,'40001','could not serialize access due to concurrent update')} commit;select 'SECTION_RR_DENIED';\n")
  observed<<{scenario:'stale_rr_publication_cannot_publish_old_section_snapshot',state:blocked(b,a)}
  write(a,"commit;select 'SECTION_RR_COMMIT';\n");read_until(a,'SECTION_RR_COMMIT');read_until(b,'SECTION_RR_DENIED')
  version_publish="public.admin_update_runtime_control_v1('notification_template_versions','{\"id\":\"#{id(121)}\"}','{\"status\":\"published\"}',1,'Synthetic template publication')"
  reinterpret="public.admin_update_runtime_control_v1('notification_templates','{\"key\":\"#{TEMPLATE}\"}','{\"locale\":\"rw\"}',1,'Synthetic late template reinterpretation')"
  start(a,"#{actor(ACTOR_SESSION)} select #{version_publish};select 'TEMPLATE_HELD';");read_until(a,'TEMPLATE_HELD')
  start(b,"#{actor(CONTROL_SESSION,CONTROLLER)} #{rejected(reinterpret,'55000','runtime_control_published_immutable')} commit;select 'TEMPLATE_DENIED';")
  observed<<{scenario:'published_template_fences_parent_reinterpretation',state:blocked(b,a)}
  write(a,"commit;select 'TEMPLATE_COMMIT';\n");read_until(a,'TEMPLATE_COMMIT');read_until(b,'TEMPLATE_DENIED')
  prefs=->(enabled,revision) {"public.set_notification_preferences_v2('{\"contribution_confirmations\":true,\"payment_reminders\":#{enabled},\"group_updates\":true,\"security_notices\":true}',#{revision})"}
  start(a,"#{actor(ACTOR_SESSION)} select 'RESULT:'||#{prefs.call(false,0)}::text;select 'PREF_HELD';");result_from(read_until(a,'PREF_HELD'))
  start(b,"#{actor(ACTOR_SESSION)} #{rejected(prefs.call(true,0),'40001','runtime_control_conflict')} commit;select 'PREF_CONFLICT';")
  observed<<{scenario:'same_user_preferences_cannot_stale_overwrite',state:blocked(b,a)}
  write(a,"commit;select 'PREF_COMMIT';\n");read_until(a,'PREF_COMMIT');read_until(b,'PREF_CONFLICT')
  fence_before=query("select jsonb_build_object('heads',(select jsonb_agg(to_jsonb(h) order by h.family) from collect_security.runtime_control_heads h where family in ('otp_policy','roster_resource_policy')),'events',(select count(*) from collect_security.runtime_control_events where family in ('otp_policy','roster_resource_policy')));")
  reserve=->(n) {"public.reserve_roster_resources('#{ACTOR}','#{ACTOR_SESSION}','#{id(200+n)}','#{'a'*64}','image',100,null)"}
  start(b,"select count(*) from collect_hybrid.roster_resource_reservations;select 'ROSTER_SNAPSHOT';",isolation:'repeatable read');read_until(b,'ROSTER_SNAPSHOT')
  start(a,"#{service} select 'RESULT:'||#{reserve.call(1)}::text;select 'ROSTER_HELD';");result_from(read_until(a,'ROSTER_HELD'))
  write(b,"#{service} #{rejected(reserve.call(2),'40001','could not serialize access due to concurrent update')} commit;select 'ROSTER_RR_DENIED';\n")
  observed<<{scenario:'actual146_reservation_physical_fence_survives147',state:blocked(b,a)}
  write(a,"commit;select 'ROSTER_COMMIT';\n");read_until(a,'ROSTER_COMMIT');read_until(b,'ROSTER_RR_DENIED')
  otp=->(n) {"public.reserve_signed_otp_v3('qa_runtime_147_#{n}','#{'b'*64}','#{PHONE_HASH}')"}
  start(b,"select count(*) from collect_security.signed_otp_requests;select 'OTP_SNAPSHOT';",isolation:'repeatable read');read_until(b,'OTP_SNAPSHOT')
  start(a,"#{service} select 'RESULT:'||#{otp.call(1)}::text;select 'OTP_HELD';");result_from(read_until(a,'OTP_HELD'))
  write(b,"#{service} #{rejected(otp.call(2),'40001','could not serialize access due to concurrent update')} commit;select 'OTP_RR_DENIED';\n")
  observed<<{scenario:'actual145_reservation_physical_fence_survives147',state:blocked(b,a)}
  write(a,"commit;select 'OTP_COMMIT';\n");read_until(a,'OTP_COMMIT');read_until(b,'OTP_RR_DENIED')
  raise 'Quota fences emitted fake config versions/audits' unless query("select jsonb_build_object('heads',(select jsonb_agg(to_jsonb(h) order by h.family) from collect_security.runtime_control_heads h where family in ('otp_policy','roster_resource_policy')),'events',(select count(*) from collect_security.runtime_control_events where family in ('otp_policy','roster_resource_policy')));")==fence_before
  start(a,"#{actor(CONTROL_SESSION,CONTROLLER)} select public.admin_set_user_access('#{ACTOR}',false,'Synthetic runtime role revocation');select 'ROLE_HELD';");read_until(a,'ROLE_HELD')
  start(b,"#{actor(ACTOR_SESSION)} #{rejected(flag.call(true,3),'42501','runtime_control_permission_required')} commit;select 'ROLE_DENIED';")
  observed<<{scenario:'effective_admin_revocation_fences_waiting_edit',state:blocked(b,a)}
  write(a,"commit;select 'ROLE_COMMIT';\n");read_until(a,'ROLE_COMMIT');read_until(b,'ROLE_DENIED')
  start(a,"delete from auth.sessions where id='#{ACTOR_SESSION}';select 'LOGOUT_HELD';");read_until(a,'LOGOUT_HELD')
  start(b,"#{actor(ACTOR_SESSION)} #{rejected(prefs.call(true,1),'42501','runtime_control_session_required')} commit;select 'LOGOUT_DENIED';")
  observed<<{scenario:'logout_fences_waiting_owned_preference_edit',state:blocked(b,a)}
  write(a,"commit;select 'LOGOUT_COMMIT';\n");read_until(a,'LOGOUT_COMMIT');read_until(b,'LOGOUT_DENIED')
  result={status:'pass',fixture:PROJECT,migration_count:147,worker_sessions:2,provider_calls:0,hosted_requests:0,scenarios:observed,no_fake_quota_revisions_or_events:true,source_sha256:Digest::SHA256.file(__FILE__).hexdigest,migration_sha256:migration_sha}
 rescue StandardError=>e
  failure=e
 ensure
  begin
   workers.each {|w|w[:input].close unless w[:input].closed?}
   workers.each do |w|
    begin Timeout.timeout(5) {w[:thread].value};rescue Timeout::Error
     raise 'Unidentified worker' unless w[:pid]
     query("select pg_terminate_backend(pid) from pg_stat_activity where pid=#{w[:pid]} and application_name='#{w[:name]}';");Timeout.timeout(5) {w[:thread].value}
    end
    w[:output].read.lines.grep(/^XID:/).each {|x|track_xid(x.strip.delete_prefix('XID:'))}
    err=w[:error].read;raise "Worker failed #{err}" unless w[:thread].value.success? || failure
   end
   raise 'Active worker remains' unless query("select count(*) from pg_stat_activity where application_name in ('#{WORKER_A}','#{WORKER_B}');")=='0'
   if seeded
    raise 'Controls drifted; no cleanup authorized' unless snapshot_tables==tables && query(controls_sql+';')==controls_before
    attribution=JSON.parse(query(owned_xids_sql+';'))
    # Historical rows contribute baseline XIDs. Only NEW/changed rows whose
    # XIDs were observed in this run are cleanup-owned; event subtransaction
    # XIDs are added only for exact actor/identity-scoped immutable new events.
    event_child_xids=JSON.parse(query("select coalesce(jsonb_agg(distinct xmin::text),'[]') from collect_security.runtime_control_events e where (actor_id in ('#{ACTOR}','#{CONTROLLER}') or identity_sha256 in (select collect_security.runtime_control_hash(identity) from collect_security.runtime_control_heads h where #{control_scope})) and not id=any(#{lit('{'+baseline_event_ids.join(',')+'}')}::uuid[]) and authority='live_operator' and actor_id in ('#{ACTOR}','#{CONTROLLER}') and session_id in ('#{ACTOR_SESSION}','#{CONTROL_SESSION}');"))
    synthetic_row_xids=attribution.reject {|v|['public.feature_flags','collect_security.runtime_control_heads','collect_security.runtime_control_events'].include?(v.fetch('relation'))}.map {|v|v.fetch('xmin')}
    xids=(TRACKED_XIDS+event_child_xids+synthetic_row_xids).uniq
    raise 'Missing/malformed attribution' if xids.empty? || xids.any? {|x|!x.match?(/\A[0-9]+\z/)}
    unattributed=query("select count(*) from collect_security.runtime_control_events e where (actor_id in ('#{ACTOR}','#{CONTROLLER}') or identity_sha256 in (select collect_security.runtime_control_hash(identity) from collect_security.runtime_control_heads h where #{control_scope})) and not id=any(#{lit('{'+baseline_event_ids.join(',')+'}')}::uuid[]) and xmin::text not in (#{xids.map {|x|lit(x)}.join(',')});")
    raise 'Unattributed scoped configuration event; cleanup denied' unless unattributed=='0'
    CHECKPOINT.merge!('phase'=>'cleanup_ready','owned_row_xid_attribution'=>attribution,'event_child_xids'=>event_child_xids,'synthetic_row_xids'=>synthetic_row_xids,'scenario_result'=>result,'primary_failure'=>failure&.message);save_checkpoint
    governed=%w[public.feature_flags public.policy_documents public.policy_document_sections public.notification_templates public.notification_template_versions public.notification_preferences collect_security.otp_policy collect_hybrid.roster_resource_policy]
    guards=governed.to_h {|t|[t,'runtime_control_governance']}.merge('collect_security.runtime_control_events'=>'runtime_control_event_immutable','collect_hybrid.roster_resource_reservations'=>'roster_resource_immutable')
    expected=guards.map {|t,n|"('#{t}'::regclass,'#{n}')"}.join(',')
    query(<<~SQL,transaction:true)
     select pg_advisory_xact_lock(193517,141);select pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
     set local lock_timeout='5s';lock table #{guards.keys.join(',')},collect_security.runtime_control_heads,public.app_realtime_events in access exclusive mode;
     do $$ declare x record;begin
      if current_user<>'postgres' or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
       or (select count(*) from supabase_migrations.schema_migrations)<>147 or (select max(version) from supabase_migrations.schema_migrations)<>'20260930150000'
       or exists(select 1 from pg_stat_activity where pid<>pg_backend_pid() and backend_type='client backend' and state<>'idle') then raise exception 'Quiet exact147 cleanup guard lost';end if;
      for x in select * from (values #{expected}) expected(relation,name) loop
       if (select count(*) from pg_trigger where tgrelid=x.relation and tgname=x.name and not tgisinternal and tgenabled='O')<>1
        or exists(select 1 from pg_trigger where tgrelid=x.relation and not tgisinternal and (tgtype::int & 2)=2 and (tgtype::int & 8)=8 and tgname<>x.name) then raise exception 'Unexpected DELETE guard; cleanup denied';end if;
      end loop;
      if exists(select 1 from collect_hybrid.roster_resource_completions where reservation_id in (select id from collect_hybrid.roster_resource_reservations where actor_id='#{ACTOR}'))
       or exists(select 1 from collect_hybrid.roster_source_verifications where reservation_id in (select id from collect_hybrid.roster_resource_reservations where actor_id='#{ACTOR}'))
       or exists(select 1 from collect_security.signed_otp_evidence where hook_id like 'qa_runtime_147_%') then raise exception 'Unknown downstream synthetic evidence';end if;
     end $$;
     #{guards.map {|t,n|"alter table #{t} disable trigger #{n};"}.join("\n")}
     delete from collect_security.signed_otp_requests where hook_id like 'qa_runtime_147_%' and phone_hash='#{PHONE_HASH}';
     delete from public.otp_rate_limits where phone_hash='#{PHONE_HASH}';delete from collect_auth_security.otp_phone_locks where phone_hash='#{PHONE_HASH}';
     delete from collect_hybrid.roster_resource_reservations where actor_id='#{ACTOR}' and request_id::text like '#{PREFIX}-%';
     delete from public.notification_template_versions where id::text like '#{PREFIX}-%';delete from public.notification_templates where key='#{TEMPLATE}';
     delete from public.policy_document_sections where id::text like '#{PREFIX}-%';delete from public.policy_documents where id::text like '#{PREFIX}-%';
     delete from public.notification_preferences where user_id in ('#{ACTOR}','#{CONTROLLER}');delete from public.feature_flags where key='#{FLAG}';
     #{restore_row('public.feature_flags',originals[:flag],"key='hybrid_member_onboarding'")}
     #{restore_row('collect_security.otp_policy',originals[:otp],'singleton')}
     #{restore_row('collect_hybrid.roster_resource_policy',originals[:roster],'id')}
     delete from collect_security.runtime_control_events e where (actor_id in ('#{ACTOR}','#{CONTROLLER}') or identity_sha256 in (select collect_security.runtime_control_hash(identity) from collect_security.runtime_control_heads h where #{control_scope})) and not id=any(#{lit('{'+baseline_event_ids.join(',')+'}')}::uuid[]) and xmin::text in (#{xids.map {|x|lit(x)}.join(',')});
     delete from collect_security.runtime_control_heads h where #{control_scope};
     insert into collect_security.runtime_control_heads select * from jsonb_populate_recordset(null::collect_security.runtime_control_heads,#{lit(originals[:heads].to_json)}::jsonb);
     delete from public.audit_logs where actor_user_id in ('#{ACTOR}','#{CONTROLLER}');
     delete from auth.users where id in ('#{ACTOR}','#{CONTROLLER}');
     do $$ declare fk record;referenced boolean;begin
      if exists(select 1 from collect_hybrid.member_records where id in ('#{ACTOR}','#{CONTROLLER}') and linked_user_id is not null) then raise exception 'Synthetic members remain linked';end if;
      for fk in select c.conrelid::regclass relation,a.attname,cardinality(c.conkey) key_count from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1] where c.contype='f' and c.confrelid='collect_hybrid.member_records'::regclass loop
       if fk.key_count<>1 then raise exception 'Unknown composite member reference';end if;
       execute format('select exists(select 1 from %s where %I=any($1))',fk.relation,fk.attname) into referenced using array['#{ACTOR}','#{CONTROLLER}']::uuid[];
       if referenced then raise exception 'Unknown synthetic member reference';end if;
      end loop;
      delete from collect_hybrid.member_records where id in ('#{ACTOR}','#{CONTROLLER}') and linked_user_id is null;
     end $$;
     #{guards.map {|t,n|"alter table #{t} enable trigger #{n};"}.join("\n")}
     delete from public.app_realtime_events where xmin::text in (#{xids.map {|x|lit(x)}.join(',')}) or xmin::text=pg_current_xact_id()::text;
     do $$ begin
      if (#{digest_sql(tables)}) is distinct from #{lit(before)} then raise notice 'RUNTIME_RESIDUAL_BASELINE:%',#{lit(fingerprints.to_json)}::jsonb;raise notice 'RUNTIME_RESIDUAL_CURRENT:%',(#{fingerprints_sql(tables)});raise exception 'Full baseline mismatch; cleanup rolled back';end if;
      if (#{controls_sql.strip}) is distinct from #{lit(controls_before)} then raise exception 'Control mismatch; cleanup rolled back';end if;
     end $$;
    SQL
    after=query(digest_sql(tables)+';');controls_after=query(controls_sql+';');raise 'Post-cleanup mismatch' unless before==after && controls_before==controls_after
    result&.merge!(baseline_tables:tables,baseline_table_count:tables.length,baseline_sha256_before:before,baseline_sha256_after:after,controls_sha256_before:controls_before,controls_sha256_after:controls_after,synthetic_rows_removed:true,worker_sessions_remaining:0,captured_transaction_ids:xids,checkpoint_path:CHECKPOINT_PATH,sequence_counters_restored:false)
   end
  rescue StandardError=>e
   cleanup_failure=e;CHECKPOINT.merge!('phase'=>'cleanup_failed','cleanup_error'=>e.message,'primary_failure'=>failure&.message);save_checkpoint
  end
 end
 raise "Primary failure: #{failure&.message || 'none'}; cleanup failed: #{cleanup_failure.message}" if cleanup_failure
 raise failure if failure
 CHECKPOINT.merge!('phase'=>'complete','result'=>result);save_checkpoint;puts JSON.pretty_generate(result)
end
