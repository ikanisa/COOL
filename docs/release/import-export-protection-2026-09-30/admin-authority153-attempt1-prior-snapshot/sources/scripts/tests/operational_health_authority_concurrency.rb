require_relative 'runtime_control_concurrency_uat'
require 'time'

# Actual installed148 health reads against the normal gated access API and Auth
# session mutation. The final two cases establish Repeatable Read snapshots
# before revocation; advisory-lock waiting alone cannot refresh those snapshots.
HEALTH_PREFIX='99670000'
HEALTH_CONTROLLER="#{HEALTH_PREFIX}-0000-4000-8000-000000000099"
HEALTH_CONTROLLER_SESSION="#{HEALTH_PREFIX}-0000-4000-8000-000000010099"
HEALTH_SOURCE='supabase/migrations/20260930160000_redacted_operational_health.sql'
HEALTH_READ_KIND=ENV.fetch('COLLECT_AUTHORITY_READ_KIND','health')
HEALTH_PATCH_PATH=ENV['COLLECT_AUTHORITY_PATCH_SOURCE']
HEALTH_PATCH_SQL=if HEALTH_PATCH_PATH
 patch=File.read(HEALTH_PATCH_PATH)
 raise 'Reviewed transactional authority correction required' unless HEALTH_READ_KIND.start_with?('runtime_control') &&
  Digest::SHA256.hexdigest(patch)==ENV['COLLECT_AUTHORITY_PATCH_SHA'] &&
  patch.match?(/\A\s*begin;/i) && patch.match?(/commit;\s*\z/i)
 patch.sub(/\A\s*begin;/i,'').sub(/commit;\s*\z/i,'')
else '' end
def health_id(n)
 "#{HEALTH_PREFIX}-0000-4000-8000-#{format('%012d',n)}"
end
def health_auth(user,sid)
 "set local role authenticated; select set_config('request.jwt.claims',#{lit({sub:user,session_id:sid,role:'authenticated',aal:'aal1'}.to_json)},true);"
end
def health_read_sql(user,sid)
 query_sql,receipt_check=case HEALTH_READ_KIND
 when 'health'
  ["public.admin_system_health()","receipt->>'id'<>'system' or receipt->>'contract_version'<>'1'"]
 when 'runtime_control'
  ["public.admin_get_runtime_control_v1('feature_flags',jsonb_build_object('key','hybrid_sms_notifications'))",
   "receipt->>'family'<>'feature_flags' or receipt->>'contract_version'<>'1' or receipt->'identity' is distinct from jsonb_build_object('key','hybrid_sms_notifications')"]
 when 'runtime_control_events'
  ["public.admin_list_runtime_control_events_v1('feature_flags',50)",
   "receipt->>'contract_version'<>'1' or jsonb_typeof(receipt->'events') is distinct from 'array' or receipt::text like '%session_id%'"]
 when 'runtime_control_write'
  ["public.admin_update_runtime_control_v1('feature_flags',jsonb_build_object('key','hybrid_sms_notifications'),jsonb_build_object('enabled',#{HEALTH_CONTROL_BASELINE.fetch('enabled')}),#{HEALTH_CONTROL_BASELINE.fetch('revision')},'Synthetic current-authority no-op')",
   "receipt->>'contract_version'<>'1' or receipt->>'family'<>'feature_flags' or receipt->'changed' is distinct from 'false'::jsonb or receipt->'identity' is distinct from jsonb_build_object('key','hybrid_sms_notifications')"]
 when 'admin_permission'
  ["jsonb_build_object('contract_version',1,'ok',true)","receipt->'ok' is distinct from 'true'::jsonb"]
 else raise 'Explicit supported authority-read kind required'
 end
 HEALTH_PATCH_SQL+health_auth(user,sid)+<<~SQL
  do $$ declare receipt jsonb;begin
   begin
    #{HEALTH_READ_KIND=='admin_permission' ? "perform public.assert_admin_permission('settings.read');" : ''}
    receipt:=#{query_sql};
    if #{receipt_check} then raise exception 'Malformed actual authority receipt';end if;
    perform set_config('collect.health_read_probe','allowed',true);
   exception when insufficient_privilege or serialization_failure then
    perform set_config('collect.health_read_probe',sqlstate,true);
   end;
  end $$;
  select 'HEALTH_RESULT:'||current_setting('collect.health_read_probe');
 SQL
end
def health_result(w,marker)
 lines=read_until(w,marker)
 line=lines.find {|s|s.start_with?('HEALTH_RESULT:')}
 raise 'Missing actual health-read outcome' unless line
 line.delete_prefix('HEALTH_RESULT:')
end
def health_end(w,command,marker)
 write(w,"#{command}; reset role;select '#{marker}';\n")
 read_until(w,marker)
end
def health_role_revoke(user)
 health_auth(HEALTH_CONTROLLER,HEALTH_CONTROLLER_SESSION)+
  "select public.admin_set_user_access(#{lit(user)}::uuid,false,'Synthetic health authority race');"
end
def health_snapshot_save(cases)
 CHECKPOINT['cases']=cases;CHECKPOINT['cases_observed']=cases.length;save_checkpoint
end

if __FILE__==$PROGRAM_NAME
 raise 'Explicit root-only isolated authorization required' unless ENV['COLLECT_HEALTH_AUTHORITY_QA']=='isolated_clone'
 raise 'Fresh absolute checkpoint required' unless CHECKPOINT_PATH && CHECKPOINT_PATH.start_with?('/') && !File.exist?(CHECKPOINT_PATH)
 reviewed=ENV.fetch('COLLECT_OPERATIONAL_HEALTH_SHA','')
 schema_count=Integer(ENV.fetch('COLLECT_HEALTH_SCHEMA_COUNT','148'))
 latest={148=>'20260930160000',150=>'20260930180000',153=>'20260930220000'}[schema_count]
 raise 'Only exact reviewed148,150 or153 supported' unless latest
 raise 'Exact reviewed148 source required' unless reviewed.match?(/\A[a-f0-9]{64}\z/) && Digest::SHA256.file(File.join(ROOT,HEALTH_SOURCE)).hexdigest==reviewed
 raw,error,success=Open3.capture3('docker','inspect',CONTAINER);raise error unless success.success?
 c=JSON.parse(raw).first;labels=c.fetch('Config').fetch('Labels');ports=c.fetch('HostConfig').fetch('PortBindings').fetch('5432/tcp')
 raise 'Exact owned running Docker/55722 fixture required' unless c.dig('State','Running') && labels['com.supabase.cli.project']==PROJECT && labels['com.docker.compose.project']==PROJECT && !ports.empty? && ports.all? {|p|p['HostPort']=='55722'}
 query(<<~SQL)
  do $$begin
   if current_user<>'postgres' or current_database()<>'postgres' or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
    or (select count(*) from supabase_migrations.schema_migrations)<>#{schema_count} or (select max(version) from supabase_migrations.schema_migrations)<>#{lit(latest)}
    or exists(select 1 from auth.users where id::text like '#{HEALTH_PREFIX}-%' or phone like '250788967%')
    or exists(select 1 from public.audit_logs where actor_user_id::text like '#{HEALTH_PREFIX}-%')
    or exists(select 1 from public.notification_device_tokens) or exists(select 1 from public.notification_deliveries)
    or (select encode(extensions.digest(statements[1],'sha256'),'hex') from supabase_migrations.schema_migrations where version='20260930160000')<>#{lit(reviewed)} then
    raise exception 'Exact quiet148 and unused health-race namespace required';end if;
  end $$;
 SQL
 if schema_count>=150
  authority_source='supabase/migrations/20260930180000_operational_health_authority.sql'
  recovery_source='supabase/migrations/20260930170000_roster_fresh_auth_recovery.sql'
  authority_sha=Digest::SHA256.file(File.join(ROOT,authority_source)).hexdigest
  recovery_sha=Digest::SHA256.file(File.join(ROOT,recovery_source)).hexdigest
  query(<<~SQL)
   do $$begin
    if (select encode(extensions.digest(statements[1],'sha256'),'hex') from supabase_migrations.schema_migrations where version='20260930170000') is distinct from #{lit(recovery_sha)}
     or (select encode(extensions.digest(statements[1],'sha256'),'hex') from supabase_migrations.schema_migrations where version='20260930180000') is distinct from #{lit(authority_sha)} then
     raise exception 'Installed149150 source binding required';end if;
   end $$;
  SQL
 end
 if schema_count==153
  %w[20260930200000_admin_automation_navigation 20260930210000_shadow_supervisor_runs 20260930220000_runtime_control_authority].each do |migration|
   version=migration.split('_').first
   source_sha=Digest::SHA256.file(File.join(ROOT,'supabase/migrations',migration+'.sql')).hexdigest
   query("do $$begin if (select encode(extensions.digest(statements[1],'sha256'),'hex') from supabase_migrations.schema_migrations where version=#{lit(version)}) is distinct from #{lit(source_sha)} then raise exception 'Installed151153 source binding required';end if;end$$;")
  end
 end
 if HEALTH_READ_KIND=='runtime_control_write'
  HEALTH_CONTROL_BASELINE=JSON.parse(query("select jsonb_build_object('enabled',f.enabled,'revision',h.revision) from public.feature_flags f join collect_security.runtime_control_heads h on h.family='feature_flags' and h.identity=jsonb_build_object('key',f.key) where f.key='hybrid_sms_notifications';"))
  raise 'Typed current no-op fixture required' unless [true,false].include?(HEALTH_CONTROL_BASELINE['enabled']) && HEALTH_CONTROL_BASELINE['revision'].is_a?(Integer) && HEALTH_CONTROL_BASELINE['revision'].between?(1,1000000000)
 end
 tables=snapshot_tables;before=JSON.parse(query(fingerprints_sql(tables)));controls=query(controls_sql)
 baseline_realtime_ids=JSON.parse(query("select coalesce(jsonb_agg(id order by id),'[]') from public.app_realtime_events;"))
 CHECKPOINT.merge!({'kind'=>"actual#{schema_count}_#{HEALTH_READ_KIND}_authority_races",'installed_count'=>schema_count,'started_at'=>Time.now.utc.iso8601,'before'=>before,'controls_before'=>controls,'source_sha256'=>reviewed,'baseline_realtime_ids'=>baseline_realtime_ids});save_checkpoint
 workers=[];cases=[];failure=nil;seeded=false
 begin
  people=[1,2,3,4,5,6,99]
  seeded=true
  query(<<~SQL,transaction:true)
   insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
    values #{people.map {|n|"(#{lit(health_id(n))},'authenticated','authenticated','250788967#{format('%03d',n)}',now(),'{}','{}')"}.join(',')};
   insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
    values #{people.map {|n|"(#{lit(health_id(n))},'+250788967#{format('%03d',n)}',clock_timestamp()-interval '2 minutes','Synthetic health race identity')"}.join(',')};
   insert into public.admin_user_roles(user_id,role_id,reason,created_at)
    select u.id,r.id,'Synthetic health race grant',clock_timestamp()-interval '1 minute'
    from auth.users u cross join public.admin_roles r where u.id::text like '#{HEALTH_PREFIX}-%' and r.name='platform_owner';
   insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
    values #{people.map {|n|"(#{lit(health_id(10000+n))},#{lit(health_id(n))},clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1')"}.join(',')};
  SQL
  a=worker_start('collect_health148_read',workers);b=worker_start('collect_health148_revoke',workers)
  unless HEALTH_READ_KIND=='admin_permission'
  [[:role,1],[:auth,2]].each do |kind,n|
   uid=health_id(n);sid=health_id(10000+n)
   revoke=kind==:role ? health_role_revoke(uid) : "delete from auth.sessions where id=#{lit(sid)};"
   start(b,revoke+"select 'REVOKE_HELD';");read_until(b,'REVOKE_HELD')
   start(a,health_read_sql(uid,sid)+"select 'READ_FINISHED';")
   wait=blocked(a,b);health_end(b,'commit','REVOKE_COMMITTED')
   result=health_result(a,'READ_FINISHED');health_end(a,'rollback','READ_CLOSED')
   raise 'Revoke-first read was not denied' unless ['42501','40001'].include?(result)
   cases<<{name:"#{kind}_revoke_before_read",outcome:result,blocking:wait,status:'pass'};health_snapshot_save(cases)
  end
  [[:role,3],[:auth,4]].each do |kind,n|
   uid=health_id(n);sid=health_id(10000+n)
   start(a,health_read_sql(uid,sid)+"select 'READ_HELD';")
   result=health_result(a,'READ_HELD');raise 'Read-first live authority denied' unless result=='allowed'
   revoke=kind==:role ? health_role_revoke(uid) : "delete from auth.sessions where id=#{lit(sid)};"
   start(b,revoke+"select 'REVOKE_FINISHED';")
   wait=blocked(b,a);health_end(a,HEALTH_PATCH_PATH ? 'rollback' : 'commit','READ_RELEASED');read_until(b,'REVOKE_FINISHED');health_end(b,'commit','REVOKE_COMMITTED')
   start(a,health_read_sql(uid,sid)+"select 'LATE_READ_FINISHED';")
   late=health_result(a,'LATE_READ_FINISHED');health_end(a,'rollback','LATE_READ_CLOSED')
   raise 'Post-revocation read was not denied' unless ['42501','40001'].include?(late)
   cases<<{name:"read_before_#{kind}_revoke",outcome:result,late_outcome:late,blocking:wait,reader_transaction:HEALTH_PATCH_PATH ? 'rolled_back_patch' : 'committed_read',status:'pass'};health_snapshot_save(cases)
  end
  end
  # Establish the snapshot with owner-only reads; then use the real authenticated
  # RPC. A successful pre-revocation snapshot is a reproduced security failure.
  [[:role,5],[:auth,6]].each do |kind,n|
   uid=health_id(n);sid=health_id(10000+n)
   start(a,"select count(*) from public.admin_user_roles;select 'SNAPSHOT_ESTABLISHED';",isolation:'repeatable read');read_until(a,'SNAPSHOT_ESTABLISHED')
   revoke=kind==:role ? health_role_revoke(uid) : "delete from auth.sessions where id=#{lit(sid)};"
   start(b,revoke+"select 'REVOKE_HELD';");read_until(b,'REVOKE_HELD')
   if HEALTH_READ_KIND=='admin_permission'
    # Commit revocation before evaluating the established snapshot, so the
    # stale-authority result cannot be attributed to an uncommitted revoke.
    health_end(b,'commit','RR_REVOKE_COMMITTED');wait=false
    write(a,health_read_sql(uid,sid)+"select 'RR_READ_FINISHED';\n")
   else
    write(a,health_read_sql(uid,sid)+"select 'RR_READ_FINISHED';\n")
    wait=blocked(a,b);health_end(b,'commit','RR_REVOKE_COMMITTED')
   end
   result=health_result(a,'RR_READ_FINISHED');health_end(a,'rollback','RR_READ_CLOSED')
   cases<<{name:"established_rr_#{kind}_revoke",outcome:result,blocking:wait,status:['42501','40001'].include?(result) ? 'pass' : 'unsafe_snapshot'};health_snapshot_save(cases)
  end
 rescue Exception=>e
  failure={class:e.class.name,message:e.message};CHECKPOINT['failure']=failure;save_checkpoint
 ensure
  workers.each do |w|
   begin
    health_end(w,'rollback','ROOT_CLOSED') if w[:thread].alive?
    w[:input].close unless w[:input].closed?;Timeout.timeout(10) {w[:thread].value}
   rescue Exception=>e
    CHECKPOINT['worker_close_failure']={class:e.class.name,message:e.message};save_checkpoint
   end
  end
 end
 if seeded
  scopes={
   'auth.users'=>"id::text like '#{HEALTH_PREFIX}-%'",'auth.sessions'=>"user_id::text like '#{HEALTH_PREFIX}-%'",
   'public.profiles'=>"id::text like '#{HEALTH_PREFIX}-%'",'public.admin_user_roles'=>"user_id::text like '#{HEALTH_PREFIX}-%'",
   'collect_admin_access.whatsapp_approvals'=>"user_id::text like '#{HEALTH_PREFIX}-%'",
   'collect_hybrid.member_records'=>"id::text like '#{HEALTH_PREFIX}-%'",'public.audit_logs'=>"actor_user_id::text like '#{HEALTH_PREFIX}-%'"
  }
  union=scopes.map {|table,where|"select '#{table}' relation,xmin::text xmin from #{table} where #{where}"}.join(' union all ')
  attribution=JSON.parse(query("select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (#{union}) x;"))
  raise 'Unattributed health race rows; preserve for inspection' unless attribution.all? {|r|TRACKED_XIDS.include?(r['xmin'])}
  known_xids=TRACKED_XIDS.map {|x|lit(x)}.join(',')
  baseline_ids=lit('{'+baseline_realtime_ids.join(',')+'}')+'::uuid[]'
  query(<<~SQL,transaction:true)
   delete from public.audit_logs where actor_user_id::text like '#{HEALTH_PREFIX}-%';
   delete from auth.users where id::text like '#{HEALTH_PREFIX}-%';
   -- Auth deletion intentionally preserves the product member record. Remove
   -- only this unused, attributed synthetic identity; retain genuine baseline.
   do $$begin
    if exists(select 1 from collect_hybrid.member_records where id::text like '#{HEALTH_PREFIX}-%'
      and xmin::text not in (#{known_xids},pg_current_xact_id()::text)) then raise exception 'Unattributed synthetic member after Auth cleanup';end if;
   end $$;
   delete from collect_hybrid.member_records where id::text like '#{HEALTH_PREFIX}-%'
     and xmin::text in (#{known_xids},pg_current_xact_id()::text);
   do $$begin
    if exists(select 1 from public.app_realtime_events where not(id=any(#{baseline_ids}))
      and xmin::text not in (#{known_xids},pg_current_xact_id()::text)) then raise exception 'Unattributed new realtime event; preserve';end if;
   end $$;
   delete from public.app_realtime_events where not(id=any(#{baseline_ids}))
    and xmin::text in (#{known_xids},pg_current_xact_id()::text);
  SQL
  CHECKPOINT['cleanup_attributed_rows']=attribution;save_checkpoint
 end
 after=JSON.parse(query(fingerprints_sql(tables)));after_controls=query(controls_sql)
 count=query("select count(*) from pg_stat_activity where application_name in ('collect_health148_read','collect_health148_revoke');").to_i
 restored=before==after && controls==after_controls && count==0
 expected_cases=HEALTH_READ_KIND=='admin_permission' ? 2 : 6
 CHECKPOINT.merge!({'status'=>!failure && restored && cases.length==expected_cases && cases.all? {|r|r[:status]=='pass'} ? 'pass' : 'fail',
  'all_tables_restored'=>before==after,'all_controls_restored'=>controls==after_controls,'worker_sessions_remaining'=>count,
  'finished_at'=>Time.now.utc.iso8601,'provider_called'=>false,'hosted_called'=>false});save_checkpoint
 puts JSON.pretty_generate(CHECKPOINT.reject {|k,_|k=='before'})
 raise 'Health authority acceptance failed; retain observed cases and restoration evidence' unless CHECKPOINT['status']=='pass'
end
