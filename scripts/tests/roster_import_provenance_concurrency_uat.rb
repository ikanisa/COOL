require 'open3'
require 'json'
require 'digest'
require 'timeout'

# SOURCE ONLY until root invokes the explicit exact-fixture guard below.
# Committed synthetic races require guarded restoration, unlike rollback UAT.
ROOT = File.expand_path('../..', __dir__)
PROJECT = 'collect_fin_concurrency_qa_20260929'
CONTAINER = "supabase_db_#{PROJECT}"
PREFIX = '99540000'
ACTOR = "#{PREFIX}-0000-4000-8000-000000000001"
CONTROLLER = "#{PREFIX}-0000-4000-8000-000000000002"
CONTROL_SESSION = "#{PREFIX}-0000-4000-8000-000000000012"
WORKER_A = 'collect_roster_142_a'
WORKER_B = 'collect_roster_142_b'
MIGRATION = 'supabase/migrations/20260930100000_roster_import_provenance.sql'
MIGRATION_SHA = '75a315d8a41c2c19f62f2fcd4557e27cb7c14e3f9ebe251f57b18e748d7349d7'
SCHEMAS = "'public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations'"
IMMUTABLE = %w[roster_import_sources roster_import_extractions roster_import_revisions roster_import_results roster_import_commits]
  .to_h { |table| ["collect_hybrid.#{table}",'roster_provenance_immutable'] }.freeze
PSQL = ['docker','exec','-i',CONTAINER,'psql','-XqAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'].freeze
TRACKED_XIDS = []
CHECKPOINT = {}
CHECKPOINT_PATH = ENV['COLLECT_ROSTER_CHECKPOINT']
def save_checkpoint
  return if CHECKPOINT.empty? || !CHECKPOINT_PATH
  CHECKPOINT['tracked_transaction_ids']=TRACKED_XIDS.uniq
  temp=CHECKPOINT_PATH+'.tmp'
  File.open(temp,File::WRONLY|File::CREAT|File::TRUNC,0600) { |f| f.write(JSON.pretty_generate(CHECKPOINT)+"\n"); f.flush; f.fsync }
  File.rename(temp,CHECKPOINT_PATH)
end
def track_xid(xid)
  raise 'Malformed observed XID' unless xid.match?(/\A[0-9]+\z/)
  TRACKED_XIDS << xid
  save_checkpoint
end

def lit(value)
  value.nil? ? 'null' : "'#{value.to_s.gsub("'","''")}'"
end
def id(n)
  "#{PREFIX}-0000-4000-8000-#{format('%012d',n)}"
end
def query(sql, transaction: false)
  sql="begin; select 'XID:'||pg_current_xact_id();\n#{sql}\ncommit;" if transaction
  output,error,status=Open3.capture3(*PSQL,stdin_data:"set application_name='collect_roster_142_control'; set statement_timeout='30s'; set lock_timeout='15s'; set timezone='UTC';\n#{sql}")
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
def source_call(n,session)
  "public.create_roster_import_source('#{ACTOR}','#{session}','#{id(100+n)}','pdf'," \
    "encode(extensions.digest('synthetic roster source #{n}','sha256'),'hex'),99,'synthetic-#{n}.pdf','application/pdf','application/pdf'," \
    "null,null,true,'roster-ai-extraction-v1','{\"provider\":\"openai\",\"model\":\"synthetic-model\",\"prompt_version\":\"roster-extraction-v1\"}')"
end
def candidate(n)
  {source_row:1,member_name:"Synthetic member #{n}",momo_name:"SYNTHETIC MEMBER #{n}",momo_number:format('+250789954%03d',n),confidence:1}
end
def rows(n,changed: false)
  c=candidate(n).reject { |key,_| [:source_row,:confidence].include?(key) }
  c[:member_name]="Reviewed member #{n}" if changed
  [c]
end
def review_call(n,source,parent,changed: false,request: 200+n)
  "public.admin_review_roster_import('#{source}','#{parent}',#{lit(rows(n,changed:changed).to_json)},'Reviewed synthetic race rows','#{id(request)}')"
end
def commit_call(n,review,title: "Synthetic roster race #{n}")
  "public.admin_commit_roster_import('#{id(300+n)}','#{review.fetch('import_id')}','#{review.fetch('revision_id')}'," \
    "'#{review.fetch('reviewed_rows_sha256')}',true,'create',null,#{lit(title)},'Reviewed every synthetic race member')"
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
def owned_xids_sql
  # BEGIN/EXCEPTION creates child XIDs; attribute these by immutable owned rows,
  # never by an XID range or by deleting every event absent from a backup.
  scopes={
    'auth.users'=>"id in ('#{ACTOR}','#{CONTROLLER}')",
    'auth.sessions'=>"user_id in ('#{ACTOR}','#{CONTROLLER}')",
    'public.profiles'=>"id in ('#{ACTOR}','#{CONTROLLER}')",
    'public.admin_user_roles'=>"user_id in ('#{ACTOR}','#{CONTROLLER}')",
    'collect_admin_access.whatsapp_approvals'=>"user_id in ('#{ACTOR}','#{CONTROLLER}')",
    'collect_hybrid.roster_import_sources'=>"actor_id='#{ACTOR}' and request_id::text like '#{PREFIX}-%'",
    'collect_hybrid.roster_import_extractions'=>"actor_id='#{ACTOR}'",
    'collect_hybrid.roster_import_revisions'=>"actor_id='#{ACTOR}'",
    'collect_hybrid.roster_import_results'=>"actor_id='#{ACTOR}'",
    'collect_hybrid.roster_import_commits'=>"actor_id='#{ACTOR}' and request_id::text like '#{PREFIX}-%'",
    'collect_hybrid.group_creation_requests'=>"actor_id='#{ACTOR}'",
    'collect_hybrid.roster_batches'=>"actor_id='#{ACTOR}'",
    'collect_hybrid.member_records'=>"created_by='#{ACTOR}' or id in ('#{ACTOR}','#{CONTROLLER}')",
    'public.audit_logs'=>"actor_user_id in ('#{ACTOR}','#{CONTROLLER}')"
  }
  owned_groups="select collection_id from collect_hybrid.roster_import_commits where actor_id='#{ACTOR}' and request_id::text like '#{PREFIX}-%' and response->>'mode'='create'"
  scopes['public.collections']="id in (#{owned_groups})"
  scopes['public.collection_members']="collection_id in (#{owned_groups})"
  scopes['public.collection_share_secrets']="collection_id in (#{owned_groups})"
  scopes['collect_hybrid.member_momo_identities']="member_id in (select id from collect_hybrid.member_records where created_by='#{ACTOR}')"
  parts=scopes.map do |t,where|
    "select '#{t}' relation,xmin::text xmin,to_jsonb(t)-'raw_app_meta_data'-'raw_user_meta_data'-'encrypted_password' row_body from #{t} t where #{where}"
  end
  "select coalesce(jsonb_agg(jsonb_build_object('relation',relation,'xmin',xmin,'row',row_body) order by relation,row_body::text),'[]') from (#{parts.join(' union all ')}) attribution"
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
      union all select 'constraint',jsonb_build_object('table',c.conrelid::regclass::text,'name',c.conname,'definition',pg_get_constraintdef(c.oid))
        from pg_constraint c join pg_namespace n on n.oid=c.connamespace where n.nspname in (#{SCHEMAS})
    ) select encode(extensions.digest(coalesce(string_agg(family||':'||body::text,E'\n' order by family,body::text),''),'sha256'),'hex') from controls
  SQL
end
def membership_digest
  query(digest_sql(%w[public.collections public.collection_members public.collection_share_secrets collect_hybrid.member_records
    collect_hybrid.member_momo_identities collect_hybrid.roster_batches collect_hybrid.group_creation_requests collect_hybrid.roster_import_commits])+';')
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
def start(w,sql)
  write(w,"begin; select 'XID:'||pg_current_xact_id();\n#{sql}\n")
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
def prepared(n,sid)
  source=result_from(query("#{service} select 'RESULT:'||#{source_call(n,sid)}::text;",transaction:true))
  preview=result_from(query("#{service} select 'RESULT:'||public.complete_roster_import_preview('#{source.fetch('import_id')}','#{ACTOR}','#{sid}',#{lit([candidate(n)].to_json)},'{\"processing_method\":\"openai_structured_extraction\",\"provider_response_sha256\":\"#{'b'*64}\",\"provider_response_id\":\"synthetic-response-#{n}\"}')::text;",transaction:true))
  [source,preview]
end
def reviewed(n,sid)
  source,preview=prepared(n,sid)
  result_from(query("#{actor(sid)} select 'RESULT:'||#{review_call(n,source.fetch('import_id'),preview.fetch('revision_id'))}::text;",transaction:true))
end
def check_ack(n,review,ack,replay)
  expected={ 'contract_version'=>1,'ok'=>true,'request_id'=>id(300+n),'import_id'=>review.fetch('import_id'),
    'revision_id'=>review.fetch('revision_id'),'reviewed_rows_sha256'=>review.fetch('reviewed_rows_sha256'),
    'collection_id'=>ack['collection_id'],'mode'=>'create','roster_count'=>1,'share_code_ready'=>true,'replayed'=>replay }
  raise 'Commit acknowledgement malformed or unbound' unless ack==expected && ack['collection_id'].is_a?(String) && ack['collection_id'].match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
  query(<<~SQL)
    do $$ begin
      if (select count(*) from collect_hybrid.roster_import_commits where request_id='#{id(300+n)}' and collection_id='#{ack['collection_id']}')<>1
        or (select count(*) from public.collection_members where collection_id='#{ack['collection_id']}' and role='member')<>1
        or (select count(*) from public.audit_logs where entity_id='#{ack['collection_id']}' and action='roster.import.committed')<>1 then
        raise exception 'Commit did not create exactly one member and audit'; end if;
    end $$;
  SQL
  ack
end

def cleanup_sql(tables:, before_sql:, controls_before:, flag_sql:, xids_sql:, trigger_guard:, residual_baseline_sql:)
  <<~SQL
        -- QA ONLY: exactly the five named provenance guards, with rollback on
        -- any failure and complete baseline/control comparison before COMMIT.
        select pg_advisory_xact_lock(193517,141);
        set local lock_timeout='5s';
        lock table #{IMMUTABLE.keys.join(',')},public.app_realtime_events in access exclusive mode;
        #{trigger_guard}
        create temp table roster_qa_group_cleanup on commit drop as
          select distinct c.collection_id as id from collect_hybrid.roster_import_commits c
            join collect_hybrid.roster_import_sources s on s.id=c.import_id
            where c.actor_id='#{ACTOR}' and s.actor_id='#{ACTOR}' and s.request_id::text like '#{PREFIX}-%'
              and c.request_id::text like '#{PREFIX}-%' and c.response->>'mode'='create';
        do $$ begin
          if exists(select 1 from public.collections where creator_user_id='#{ACTOR}' and id not in (select id from roster_qa_group_cleanup))
            or exists(select 1 from collect_hybrid.group_creation_requests where actor_id='#{ACTOR}' and collection_id not in (select id from roster_qa_group_cleanup))
            or exists(select 1 from collect_hybrid.roster_batches where actor_id='#{ACTOR}' and collection_id not in (select id from roster_qa_group_cleanup)) then
            raise exception 'Unattributed synthetic collection graph'; end if;
        end $$;
        do $$ declare fk record; referenced boolean;
          fresh_ids uuid[]:=array['#{ACTOR}','#{CONTROLLER}']::uuid[];
          allowed regclass[]:=array['auth.sessions'::regclass,'public.profiles'::regclass,'collect_admin_access.whatsapp_approvals'::regclass,
            'public.admin_user_roles'::regclass,'public.notification_preferences'::regclass,'public.notification_events'::regclass,
            'collect_hybrid.member_records'::regclass,'collect_hybrid.member_momo_identities'::regclass,
            'public.collections'::regclass,'public.collection_members'::regclass,'public.collection_share_secrets'::regclass,
            'collect_hybrid.group_creation_requests'::regclass,'collect_hybrid.roster_batches'::regclass,
            #{IMMUTABLE.keys.map { |x| "'#{x}'::regclass" }.join(',')},'public.audit_logs'::regclass,'public.feature_flags'::regclass];
        begin
          if current_user<>'postgres' or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
            or (select count(*) from supabase_migrations.schema_migrations)<>142
            or (select max(version) from supabase_migrations.schema_migrations)<>'20260930100000'
            or exists(select 1 from pg_stat_activity where pid<>pg_backend_pid() and backend_type='client backend' and state<>'idle') then
            raise exception 'Quiet exact142 cleanup precondition lost'; end if;
          if exists(select 1 from pg_trigger where tgrelid='public.app_realtime_events'::regclass and not tgisinternal)
            or exists(select 1 from pg_constraint where contype='f' and confrelid='public.app_realtime_events'::regclass) then
            raise exception 'Unknown telemetry guard/reference'; end if;
          select fresh_ids||coalesce(array_agg(id),'{}'::uuid[]) into fresh_ids from collect_hybrid.roster_import_sources where actor_id='#{ACTOR}';
          select fresh_ids||coalesce(array_agg(id),'{}'::uuid[]) into fresh_ids from collect_hybrid.roster_import_extractions where actor_id='#{ACTOR}';
          select fresh_ids||coalesce(array_agg(id),'{}'::uuid[]) into fresh_ids from collect_hybrid.roster_import_revisions where actor_id='#{ACTOR}';
          select fresh_ids||coalesce(array_agg(id),'{}'::uuid[]) into fresh_ids from roster_qa_group_cleanup;
          select fresh_ids||coalesce(array_agg(id),'{}'::uuid[]) into fresh_ids from collect_hybrid.member_records where created_by='#{ACTOR}';
          for fk in select c.conrelid::regclass child,c.confrelid::regclass parent,
            (select string_agg(format('child.%I=parent.%I',ca.attname,pa.attname),' and ' order by k.ordinality)
              from unnest(c.conkey,c.confkey) with ordinality k(child_col,parent_col,ordinality)
              join pg_attribute ca on ca.attrelid=c.conrelid and ca.attnum=k.child_col
              join pg_attribute pa on pa.attrelid=c.confrelid and pa.attnum=k.parent_col) predicate
            from pg_constraint c where c.contype='f' and c.confrelid in ('auth.users'::regclass,'public.profiles'::regclass,
              'public.collections'::regclass,'collect_hybrid.member_records'::regclass,'collect_hybrid.roster_import_sources'::regclass,
              'collect_hybrid.roster_import_extractions'::regclass,'collect_hybrid.roster_import_revisions'::regclass)
            and not c.conrelid=any(allowed) loop
            execute format('select exists(select 1 from %s child join %s parent on %s where parent.id=any($1))',fk.child,fk.parent,fk.predicate)
              into referenced using fresh_ids;
            if referenced then raise exception 'Unknown synthetic FK/reference from %',fk.child; end if;
          end loop;
        end $$;
        #{IMMUTABLE.map { |t,n| "alter table #{t} disable trigger #{n};" }.join("\n")}
        delete from collect_hybrid.roster_import_commits where actor_id='#{ACTOR}';
        delete from collect_hybrid.roster_import_results where actor_id='#{ACTOR}';
        delete from collect_hybrid.roster_import_revisions where actor_id='#{ACTOR}';
        delete from collect_hybrid.roster_import_extractions where actor_id='#{ACTOR}';
        delete from collect_hybrid.roster_import_sources where actor_id='#{ACTOR}';
        delete from collect_hybrid.roster_batches where actor_id='#{ACTOR}';
        delete from collect_hybrid.group_creation_requests where actor_id='#{ACTOR}';
        delete from public.collection_members where collection_id in (select id from roster_qa_group_cleanup);
        delete from public.collection_share_secrets where collection_id in (select id from roster_qa_group_cleanup);
        delete from public.collections where id in (select id from roster_qa_group_cleanup);
        delete from collect_hybrid.member_momo_identities where member_id in (select id from collect_hybrid.member_records where created_by='#{ACTOR}');
        -- Restore every column touched by the real feature-management RPC.
        update public.feature_flags set (enabled,updated_by,updated_reason,updated_at)=(
          select f.enabled,f.updated_by,f.updated_reason,f.updated_at from jsonb_populate_record(null::public.feature_flags,#{flag_sql}) f)
          where key='hybrid_member_onboarding';
        delete from public.notification_events where user_id in ('#{ACTOR}','#{CONTROLLER}');
        delete from public.audit_logs where actor_user_id in ('#{ACTOR}','#{CONTROLLER}');
        -- Save offline IDs before Auth deletion clears created_by references.
        create temp table roster_qa_member_cleanup on commit drop as
          select id from collect_hybrid.member_records where created_by='#{ACTOR}' or id in ('#{ACTOR}','#{CONTROLLER}');
        delete from auth.users where id in ('#{ACTOR}','#{CONTROLLER}');
        do $$ declare fk record; referenced boolean; members uuid[]:=(select array_agg(id) from roster_qa_member_cleanup); begin
          if exists(select 1 from collect_hybrid.member_records where id=any(members) and linked_user_id is not null) then
            raise exception 'Synthetic members remain linked'; end if;
          for fk in select c.conrelid::regclass relation,a.attname,cardinality(c.conkey) key_count
            from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
            where c.contype='f' and c.confrelid='collect_hybrid.member_records'::regclass loop
            if fk.key_count<>1 then raise exception 'Unexpected composite member reference'; end if;
            execute format('select exists(select 1 from %s where %I=any($1))',fk.relation,fk.attname) into referenced using members;
            if referenced then raise exception 'Synthetic member still referenced by %',fk.relation; end if;
          end loop;
          delete from collect_hybrid.member_records where id=any(members) and linked_user_id is null;
        end $$;
        #{IMMUTABLE.map { |t,n| "alter table #{t} enable trigger #{n};" }.join("\n")}
        delete from public.app_realtime_events where xmin::text in (#{xids_sql}) or xmin::text=pg_current_xact_id()::text;
        do $$ begin
          if (#{digest_sql(tables)}) is distinct from (#{before_sql}) then
            raise notice 'ROSTER_RESIDUAL_BASELINE:%', (#{residual_baseline_sql});
            raise notice 'ROSTER_RESIDUAL_CURRENT:%', (#{fingerprints_sql(tables)});
            raise exception 'Full data baseline not restored; cleanup rolled back'; end if;
          if (#{controls_sql.strip})<>'#{controls_before}' then raise exception 'Controls not restored; cleanup rolled back'; end if;
        end $$;
      SQL
end

if __FILE__ == $PROGRAM_NAME

raise 'Set COLLECT_ROSTER_PROVENANCE_QA=isolated_clone' unless ENV['COLLECT_ROSTER_PROVENANCE_QA']=='isolated_clone'
raise 'New absolute COLLECT_ROSTER_CHECKPOINT path required' unless CHECKPOINT_PATH && CHECKPOINT_PATH.start_with?('/') && !File.exist?(CHECKPOINT_PATH) && !File.symlink?(CHECKPOINT_PATH) && Dir.exist?(File.dirname(CHECKPOINT_PATH))
raise 'Frozen migration142 changed' unless Digest::SHA256.file(File.join(ROOT,MIGRATION)).hexdigest==MIGRATION_SHA
raw,err,status=Open3.capture3('docker','inspect',CONTAINER)
raise err unless status.success?
container=JSON.parse(raw).fetch(0); labels=container.fetch('Config').fetch('Labels')
ports=container.fetch('HostConfig').fetch('PortBindings').fetch('5432/tcp')
config=File.read(File.join(ROOT,'.cache/financial-concurrency-20260929/supabase/config.toml'))
db=config[/^\[db\]\s*\n(.*?)(?=^\[|\z)/m,1]
raise 'Exact task fixture provenance required' unless container.dig('State','Running') && labels['com.supabase.cli.project']==PROJECT &&
  labels['com.docker.compose.project']==PROJECT && config.match?(/^project_id = "#{PROJECT}"$/) && db&.match?(/^port = 55722$/) &&
  !ports.empty? && ports.all? { |v| v['HostPort']=='55722' }
query(<<~SQL)
  do $$ begin
    if current_database()<>'postgres' or current_user<>'postgres' or current_setting('cron.launch_active_jobs')<>'off'
      or current_setting('pg_net.batch_size')<>'0' or (select count(*) from supabase_migrations.schema_migrations)<>142
      or (select max(version) from supabase_migrations.schema_migrations)<>'20260930100000'
      or exists(select 1 from auth.users where id::text like '#{PREFIX}-%' or phone in ('250788954001','250788954002'))
      or exists(select 1 from auth.sessions where id::text like '#{PREFIX}-%')
      or exists(select 1 from public.profiles where id::text like '#{PREFIX}-%' or momo_number like '%789954%')
      or exists(select 1 from collect_hybrid.member_records where id::text like '#{PREFIX}-%' or created_by in ('#{ACTOR}','#{CONTROLLER}'))
      or exists(select 1 from collect_hybrid.member_momo_identities where momo_number like '+250789954%')
      or exists(select 1 from collect_hybrid.roster_import_sources where request_id::text like '#{PREFIX}-%' or actor_id in ('#{ACTOR}','#{CONTROLLER}'))
      or exists(select 1 from public.notification_device_tokens) or exists(select 1 from public.notification_deliveries)
      or exists(select 1 from pg_stat_activity where application_name in ('#{WORKER_A}','#{WORKER_B}')) then
      raise exception 'Exact isolated142, inactive providers and unused9954 namespace required'; end if;
  end $$;
SQL
triggers=IMMUTABLE.map { |table,name| "('#{table}'::regclass,'#{name}')" }.join(',')
trigger_guard=<<~SQL
  do $$ declare x record; begin
    for x in select * from (values #{triggers}) expected(relation,name) loop
      if (select count(*) from pg_trigger where tgrelid=x.relation and tgname=x.name and not tgisinternal and tgenabled='O')<>1
        or exists(select 1 from pg_trigger where tgrelid=x.relation and not tgisinternal and (tgtype::int & 2)=2 and (tgtype::int & 8)=8 and tgname<>x.name) then
        raise exception 'Unexpected immutable DELETE guard; refuse cleanup authorization'; end if;
    end loop;
  end $$;
SQL
query(trigger_guard)
tables=snapshot_tables; before=query(digest_sql(tables)+';'); controls_before=query(controls_sql+';')
flag=JSON.parse(query("select to_jsonb(f) from public.feature_flags f where key='hybrid_member_onboarding';"))
financial=%w[public.payments public.ledger_entries collect_hybrid.momo_journal_entries collect_hybrid.momo_journal_lines collect_hybrid.collection_balances collect_hybrid.member_balances]
financial_before=query(digest_sql(financial)+';')
baseline_fingerprints=JSON.parse(query(fingerprints_sql(tables)+';'))
CHECKPOINT.merge!('phase'=>'baseline_before_seed','source_sha256'=>Digest::SHA256.file(__FILE__).hexdigest,
  'migration_sha256'=>MIGRATION_SHA,'fixture'=>PROJECT,'baseline_tables'=>tables,'baseline_sha256'=>before,
  'baseline_fingerprints'=>baseline_fingerprints,'controls_sha256'=>controls_before,'feature_flag'=>flag)
# O_EXCL prevents replacing an earlier run's checkpoint, even after the guard.
File.open(CHECKPOINT_PATH,File::WRONLY|File::CREAT|File::EXCL,0600) { |f| f.write(JSON.pretty_generate(CHECKPOINT)+"\n"); f.flush; f.fsync }
workers=[]; seeded=false; failure=nil; cleanup_failure=nil; result=nil; observed=[]; acknowledgements=[]
begin
  seeded=true
  query(<<~SQL,transaction:true)
    insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data) values
      ('#{ACTOR}','authenticated','authenticated','250788954001',now(),'{}','{}'),
      ('#{CONTROLLER}','authenticated','authenticated','250788954002',now(),'{}','{}');
    update public.profiles set country_code='RW',currency_code='RWF' where id in ('#{ACTOR}','#{CONTROLLER}');
    insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason) values
      ('#{ACTOR}','+250788954001',clock_timestamp()-interval '2 minutes','Synthetic roster actor approval'),
      ('#{CONTROLLER}','+250788954002',clock_timestamp()-interval '2 minutes','Synthetic roster controller approval');
    insert into public.admin_user_roles(user_id,role_id,reason,created_at)
      select a.id,r.id,'Synthetic roster concurrency roles',clock_timestamp()-interval '1 minute'
      from (values('#{ACTOR}'::uuid),('#{CONTROLLER}'::uuid)) a(id) cross join public.admin_roles r where r.name='platform_owner';
    insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
      values('#{CONTROL_SESSION}','#{CONTROLLER}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
    update public.feature_flags set enabled=true where key='hybrid_member_onboarding';
  SQL
  a=worker_start(WORKER_A,workers); b=worker_start(WORKER_B,workers)
  sid=session(1)
  start(a,"#{service} select 'RESULT:'||#{source_call(1,sid)}::text; select 'SOURCE_HELD';")
  source=result_from(read_until(a,'SOURCE_HELD'))
  start(b,"#{service} #{rejected(source_call(1,sid),'55000','roster_import_in_progress')} commit; select 'SOURCE_DUPLICATE_DENIED';")
  observed << {scenario:'duplicate_source_single_provider_attempt',state:blocked(b,a)}
  write(a,"commit; select 'SOURCE_COMMITTED';\n"); read_until(a,'SOURCE_COMMITTED'); read_until(b,'SOURCE_DUPLICATE_DENIED')
  query("do $$ begin if (select count(*) from collect_hybrid.roster_import_sources where request_id='#{id(101)}')<>1 or (select count(*) from collect_hybrid.roster_import_extractions where import_id='#{source['import_id']}')<>1 then raise exception 'Duplicate source acquired second extraction ownership'; end if; end $$;")
  preview=result_from(query("#{service} select 'RESULT:'||public.complete_roster_import_preview('#{source['import_id']}','#{ACTOR}','#{sid}',#{lit([candidate(1)].to_json)},'{\"processing_method\":\"openai_structured_extraction\",\"provider_response_sha256\":\"#{'b'*64}\",\"provider_response_id\":\"synthetic-response-1\"}')::text;",transaction:true))
  start(a,"#{actor(sid)} select 'RESULT:'||#{review_call(1,source['import_id'],preview['revision_id'])}::text; select 'REVIEW_HELD';")
  review=result_from(read_until(a,'REVIEW_HELD'))
  start(b,"#{actor(sid)} select 'RESULT:'||#{review_call(1,source['import_id'],preview['revision_id'])}::text; commit; select 'REVIEW_RETRY_DONE';")
  observed << {scenario:'duplicate_review_same_revision',state:blocked(b,a)}
  write(a,"commit; select 'REVIEW_COMMITTED';\n"); read_until(a,'REVIEW_COMMITTED')
  raise 'Duplicate review returned another revision' unless result_from(read_until(b,'REVIEW_RETRY_DONE'))==review
  query("do $$ begin if (select count(*) from collect_hybrid.roster_import_revisions where import_id='#{source['import_id']}')<>2 then raise exception 'Duplicate review appended another revision'; end if; end $$;")
  start(a,"#{actor(sid)} select 'RESULT:'||#{commit_call(1,review)}::text; select 'COMMIT_HELD';")
  first=result_from(read_until(a,'COMMIT_HELD'))
  start(b,"#{actor(sid)} select 'RESULT:'||#{commit_call(1,review)}::text; commit; select 'COMMIT_RETRY_DONE';")
  observed << {scenario:'duplicate_commit_one_membership',state:blocked(b,a)}
  write(a,"commit; select 'COMMIT_COMMITTED';\n"); read_until(a,'COMMIT_COMMITTED')
  second=result_from(read_until(b,'COMMIT_RETRY_DONE'))
  acknowledgements << check_ack(1,review,first,false); check_ack(1,review,second,true)
  raise 'Replay collection changed' unless first['collection_id']==second['collection_id']
  membership_before=membership_digest
  # The successful commit output is deliberately ignored by a simulated caller.
  query("#{actor(sid)} select #{commit_call(1,review)};",transaction:true)
  check_ack(1,review,result_from(query("#{actor(sid)} select 'RESULT:'||#{commit_call(1,review)}::text;",transaction:true)),true)
  query("#{actor(sid)} #{rejected(commit_call(1,review,title:'Changed lost-response payload'),'55000','roster_request_conflict')}",transaction:true)
  raise 'Response-loss retry changed membership graph' unless membership_digest==membership_before

  # Independent imports/sessions exercise both orders for all revocation types.
  n=2
  %w[session role feature].each do |kind|
    %w[revoke_first commit_first].each do |order|
      query("#{actor(CONTROL_SESSION,CONTROLLER)} select public.admin_set_user_access('#{ACTOR}',true,'Synthetic role restoration for next case'); select public.admin_set_feature_flag('hybrid_member_onboarding',true,'Synthetic next-case feature enable');",transaction:true)
      case_session=session(n); case_review=reviewed(n,case_session)
      revoke=case kind
      when 'session' then "delete from auth.sessions where id='#{case_session}';"
      when 'role' then "#{actor(CONTROL_SESSION,CONTROLLER)} select public.admin_set_user_access('#{ACTOR}',false,'Synthetic roster role revocation');"
      when 'feature' then "#{actor(CONTROL_SESSION,CONTROLLER)} select public.admin_set_feature_flag('hybrid_member_onboarding',false,'Synthetic roster feature revocation');"
      end
      if order=='revoke_first'
        unchanged=membership_digest
        start(b,"#{revoke} select 'REVOKE_HELD';"); read_until(b,'REVOKE_HELD')
        code=kind=='feature' ? 'roster_feature_disabled' : 'roster_actor_unavailable'
        state=kind=='feature' ? '55000' : '42501'
        start(a,"#{actor(case_session)} #{rejected(commit_call(n,case_review),state,code)} commit; select 'REVOKED_COMMIT_DENIED';")
        observed << {scenario:"#{kind}_revoke_first",state:blocked(a,b)}
        write(b,"commit; select 'REVOKE_COMMITTED';\n"); read_until(b,'REVOKE_COMMITTED'); read_until(a,'REVOKED_COMMIT_DENIED')
        raise "#{kind} revoke-first mutated membership" unless membership_digest==unchanged
      else
        start(a,"#{actor(case_session)} select 'RESULT:'||#{commit_call(n,case_review)}::text; select 'MEMBERSHIP_HELD';")
        ack=result_from(read_until(a,'MEMBERSHIP_HELD'))
        start(b,"#{revoke} commit; select 'POST_COMMIT_REVOKE_DONE';")
        observed << {scenario:"commit_before_#{kind}_revoke",state:blocked(b,a)}
        write(a,"commit; select 'MEMBERSHIP_COMMITTED';\n"); read_until(a,'MEMBERSHIP_COMMITTED'); read_until(b,'POST_COMMIT_REVOKE_DONE')
        acknowledgements << check_ack(n,case_review,ack,false)
      end
      n+=1
    end
  end
  query("#{actor(CONTROL_SESSION,CONTROLLER)} select public.admin_set_user_access('#{ACTOR}',true,'Synthetic actor restoration for revision race'); select public.admin_set_feature_flag('hybrid_member_onboarding',true,'Synthetic feature restoration for revision race');",transaction:true)
  sid=session(n); source,preview=prepared(n,sid)
  start(a,"#{actor(sid)} select 'RESULT:'||#{review_call(n,source['import_id'],preview['revision_id'])}::text; select 'PARENT_REVIEW_HELD';")
  latest=result_from(read_until(a,'PARENT_REVIEW_HELD'))
  start(b,"#{actor(sid)} #{rejected(review_call(n,source['import_id'],preview['revision_id'],changed:true,request:900+n),'55000','roster_revision_superseded')} commit; select 'STALE_PARENT_DENIED';")
  observed << {scenario:'competing_parent_review_no_branch',state:blocked(b,a)}
  write(a,"commit; select 'PARENT_REVIEW_COMMITTED';\n"); read_until(a,'PARENT_REVIEW_COMMITTED'); read_until(b,'STALE_PARENT_DENIED')
  start(a,"#{actor(sid)} select 'RESULT:'||#{review_call(n,source['import_id'],latest['revision_id'],changed:true,request:950+n)}::text; select 'NEWER_REVIEW_HELD';")
  newer=result_from(read_until(a,'NEWER_REVIEW_HELD'))
  start(b,"#{actor(sid)} #{rejected(commit_call(n,latest),'55000','roster_revision_superseded')} commit; select 'SUPERSEDED_COMMIT_DENIED';")
  observed << {scenario:'latest_revision_invalidates_queued_commit',state:blocked(b,a)}
  write(a,"commit; select 'NEWER_REVIEW_COMMITTED';\n"); read_until(a,'NEWER_REVIEW_COMMITTED'); read_until(b,'SUPERSEDED_COMMIT_DENIED')
  acknowledgements << check_ack(n,newer,result_from(query("#{actor(sid)} select 'RESULT:'||#{commit_call(n,newer)}::text;",transaction:true)),false)
  raise 'Roster flow changed financial data' unless query(digest_sql(financial)+';')==financial_before
  result={status:'pass',fixture:PROJECT,migration_count:142,worker_sessions:2,provider_calls:0,hosted_auth_requests:0,
    scenarios:observed,commit_acknowledgements:acknowledgements,duplicate_source_attempts:1,
    duplicate_review_same_revision:true,duplicate_commit_single_membership:true,response_loss_exact_payload_retry:true,
    financial_rows_unchanged:true,source_sha256:Digest::SHA256.file(__FILE__).hexdigest,migration_sha256:MIGRATION_SHA}
rescue StandardError => e
  failure=e
ensure
  begin
    workers.each { |w| w[:input].close unless w[:input].closed? }
    workers.each do |w|
      begin Timeout.timeout(5) { w[:thread].value }
      rescue Timeout::Error
        raise 'Cannot terminate unidentified worker' unless w[:pid]
        query("select pg_terminate_backend(pid) from pg_stat_activity where pid=#{w[:pid]} and application_name='#{w[:name]}';")
        Timeout.timeout(5) { w[:thread].value }
      end
      w[:output].read.lines.grep(/^XID:/).each { |line| track_xid(line.strip.delete_prefix('XID:')) }
      error=w[:error].read
      raise "Worker failed: #{error}" unless w[:thread].value.success? || failure
    end
    raise 'Workers still present; cleanup denied' unless query("select count(*) from pg_stat_activity where application_name in ('#{WORKER_A}','#{WORKER_B}');")=='0'
    if seeded
      raise 'Catalog controls changed; cleanup denied' unless snapshot_tables==tables && query(controls_sql+';')==controls_before
      raise 'Unverified telemetry transaction IDs' unless !TRACKED_XIDS.empty? && TRACKED_XIDS.all? { |x| x.match?(/\A[0-9]+\z/) }
      xids=TRACKED_XIDS.uniq.map { |x| lit(x) }.join(',')
      attribution=JSON.parse(query(owned_xids_sql+';'))
      owned_xids=attribution.map { |v| v.fetch('xmin') }
      raise 'Invalid owned child transaction attribution' unless owned_xids.all? { |x| x.match?(/\A[0-9]+\z/) }
      CHECKPOINT.merge!('phase'=>'cleanup_ready','owned_row_xid_attribution'=>attribution,'scenario_result'=>result,
        'primary_failure'=>failure && "#{failure.class}: #{failure.message}")
      save_checkpoint
      xids=(TRACKED_XIDS+owned_xids).uniq.map { |x| lit(x) }.join(',')
      query(cleanup_sql(tables:tables,before_sql:lit(before),controls_before:controls_before,
        flag_sql:lit(flag.to_json)+'::jsonb',xids_sql:xids,trigger_guard:trigger_guard,
        residual_baseline_sql:lit(baseline_fingerprints.to_json)+'::jsonb'),transaction:true)
      after=query(digest_sql(tables)+';'); controls_after=query(controls_sql+';')
      raise 'Post-cleanup baseline mismatch' unless after==before && controls_after==controls_before
      if result
        result.merge!(baseline_tables:tables,baseline_table_count:tables.length,baseline_sha256_before:before,baseline_sha256_after:after,
          controls_sha256_before:controls_before,controls_sha256_after:controls_after,synthetic_graph_removed:true,worker_sessions_remaining:0,
          qa_only_temporarily_disabled_triggers:IMMUTABLE,captured_transaction_ids:TRACKED_XIDS.uniq,owned_row_xid_attribution:attribution,checkpoint_path:CHECKPOINT_PATH,
          telemetry_disposition:'Only observed top-level and exact owned-row child XIDs plus cleanup XID removed; all pre-existing rows retained.',
          sequence_counters_restored:false,sequence_note:'PostgreSQL nextval counters are not rolled back or reset.')
      end
    end
  rescue StandardError => e
    cleanup_failure=e
    CHECKPOINT.merge!('phase'=>'cleanup_failed','cleanup_error'=>e.message,'primary_failure'=>failure && "#{failure.class}: #{failure.message}")
    save_checkpoint
  end
end
raise "Primary failure: #{failure ? failure.class.to_s+': '+failure.message : 'none; scenarios completed'}\nCleanup failed: #{cleanup_failure.message}" if cleanup_failure
raise failure if failure
CHECKPOINT.merge!('phase'=>'complete','result'=>result)
save_checkpoint
puts JSON.pretty_generate(result)

end
