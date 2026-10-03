require 'open3'
require 'json'
require 'digest'
require 'timeout'

# SOURCE ONLY until root invokes the explicit exact-fixture guard below.
# Committed synthetic races require guarded restoration, unlike rollback UAT.
ROOT = File.expand_path('../..', __dir__)
PROJECT = 'collect_fin_concurrency_qa_20260929'
CONTAINER = "supabase_db_#{PROJECT}"
PREFIX = '99880000'
ACTOR = "#{PREFIX}-0000-4000-8000-000000000001"
CONTROLLER = "#{PREFIX}-0000-4000-8000-000000000002"
CONTROL_SESSION = "#{PREFIX}-0000-4000-8000-000000000012"
WORKER_A = 'collect_roster_149_a'
WORKER_B = 'collect_roster_149_b'
MIGRATION = 'supabase/migrations/20260930170000_roster_fresh_auth_recovery.sql'
MIGRATION_SHA = ENV.fetch('COLLECT_ROSTER_FRESH_AUTH_MIGRATION_SHA')
AUTHORITY_MIGRATION = 'supabase/migrations/20260930180000_operational_health_authority.sql'
AUTHORITY_SHA = ENV.fetch('COLLECT_ROSTER_AUTHORITY_MIGRATION_SHA')
MIGRATION_COUNT = 150
LATEST_MIGRATION = '20260930180000'
SCHEMAS = "'public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations','cron'"
IMMUTABLE = %w[roster_import_sources roster_import_extractions roster_import_revisions roster_import_results roster_import_commits]
  .to_h { |table| ["collect_hybrid.#{table}",'roster_provenance_immutable'] }.merge('collect_hybrid.roster_import_recovery_intents'=>'roster_recovery_intent_immutable').merge(
    'collect_hybrid.roster_recovery_transfers'=>'roster_transfer_immutable',
    'collect_hybrid.roster_resource_reservations'=>'roster_resource_immutable',
    'collect_hybrid.roster_resource_completions'=>'roster_resource_immutable',
    'collect_hybrid.roster_source_verifications'=>'roster_resource_immutable'
  ).freeze
CLEANUP_GUARDS = IMMUTABLE.merge(
  'public.feature_flags'=>'runtime_control_governance',
  'public.notification_preferences'=>'runtime_control_governance',
  'collect_security.runtime_control_events'=>'runtime_control_event_immutable'
).freeze
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
  output,error,status=Open3.capture3(*PSQL,stdin_data:"set application_name='collect_roster_149_control'; set statement_timeout='30s'; set lock_timeout='15s'; set timezone='UTC';\n#{sql}")
  output.lines.grep(/^XID:/).each { |line| track_xid(line.strip.delete_prefix('XID:')) }
  raise(error.empty? ? output : error) unless status.success?
  output.lines.reject { |line| line.start_with?('XID:') }.join.strip
end
def actor(session,user=ACTOR,exp: Time.now.to_i+3600)
  "set local role authenticated; select set_config('request.jwt.claims',#{lit({sub:user,session_id:session,role:'authenticated',aal:'aal1',exp:exp}.to_json)},true);"
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
  {source_row:1,member_name:"Synthetic member #{n}",momo_name:"SYNTHETIC MEMBER #{n}",momo_number:format('+250789988%03d',n),confidence:1}
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
    'collect_hybrid.roster_import_recovery_intents'=>"actor_id='#{ACTOR}'",
    'collect_hybrid.roster_import_editor_drafts'=>"actor_id='#{ACTOR}'",
    'collect_hybrid.roster_recovery_transfers'=>"actor_id='#{ACTOR}'",
    'collect_hybrid.roster_resource_reservations'=>"actor_id='#{ACTOR}' and request_id::text like '#{PREFIX}-%'",
    'collect_hybrid.roster_resource_completions'=>"reservation_id in (select id from collect_hybrid.roster_resource_reservations where actor_id='#{ACTOR}' and request_id::text like '#{PREFIX}-%')",
    'collect_hybrid.roster_source_verifications'=>"reservation_id in (select id from collect_hybrid.roster_resource_reservations where actor_id='#{ACTOR}' and request_id::text like '#{PREFIX}-%')",
    'collect_hybrid.group_creation_requests'=>"actor_id='#{ACTOR}'",
    'collect_hybrid.roster_batches'=>"actor_id='#{ACTOR}'",
    'collect_hybrid.member_records'=>"created_by='#{ACTOR}' or id in ('#{ACTOR}','#{CONTROLLER}')",
    'public.audit_logs'=>"actor_user_id in ('#{ACTOR}','#{CONTROLLER}')"
  }
  scopes['collect_security.runtime_control_heads']=governance_scope('t')
  scopes['collect_security.runtime_control_events']="identity_sha256 in (select collect_security.runtime_control_hash(identity) from collect_security.runtime_control_heads h where #{governance_scope('h')}) and not id=any(#{lit('{'+CHECKPOINT.fetch('baseline_governance_event_ids').join(',')+'}')}::uuid[])"
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
def governance_scope(name)
  "(#{name}.family='feature_flags' and #{name}.identity=jsonb_build_object('key','hybrid_member_onboarding')) or " \
    "(#{name}.family='notification_preferences' and #{name}.identity in (jsonb_build_object('user_id','#{ACTOR}'::uuid),jsonb_build_object('user_id','#{CONTROLLER}'::uuid)))"
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
      union all select 'cron',to_jsonb(j) from cron.job j
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
def prepared(n,sid,ttl: nil)
  sha=Digest::SHA256.hexdigest("synthetic roster source #{n}")
  reservation=result_from(query("#{service} select 'RESULT:'||public.reserve_roster_resources('#{ACTOR}','#{sid}','#{id(100+n)}','#{sha}','text',99,null)::text;",transaction:true))
  if ttl
    # Owner-only short-deadline fixture seeding. The real BEFORE guard runs;
    # provenance is not UPDATEd, guards are not disabled, and preview/finish use RPCs.
    call="with s as (insert into collect_hybrid.roster_import_sources(request_id,actor_id,session_id,source_kind,source_sha256,source_size,client_filename,declared_mime,detected_type,ai_consent,input_sha256,expires_at) values('#{id(100+n)}','#{ACTOR}','#{sid}','text','#{sha}',99,'synthetic-#{n}.txt','text/plain','utf8_text',false,collect_hybrid.roster_digest(jsonb_build_array('#{ACTOR}'::uuid,'#{sid}'::uuid,'text','#{sha}',99::bigint,'synthetic-#{n}.txt','text/plain','utf8_text',null,null,false,null,null)),clock_timestamp()+interval '#{Integer(ttl)} seconds') returning *) select 'RESULT:'||jsonb_build_object('import_id',id,'expires_at',expires_at)::text from s"
    source=result_from(query(call+';',transaction:true))
  else
    call="public.create_roster_import_source('#{ACTOR}','#{sid}','#{id(100+n)}','text','#{sha}',99,'synthetic-#{n}.txt','text/plain','utf8_text',null,null,false,null,null)"
    source=result_from(query("#{service} select 'RESULT:'||#{call}::text;",transaction:true))
  end
  preview=result_from(query("#{service} select 'RESULT:'||public.complete_roster_import_preview('#{source.fetch('import_id')}','#{ACTOR}','#{sid}',#{lit([candidate(n)].to_json)},'{\"processing_method\":\"deterministic\",\"provider_response_sha256\":null,\"provider_response_id\":null}')::text; select public.finish_roster_resources('#{reservation.fetch('reservation_id')}','#{ACTOR}','#{sid}','preview_ready');",transaction:true))
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

# These helpers only run after the main exact-fixture and reviewed-SHA guards.
def fresh_session(n)
  session(n)
end
def etag(import,sid)
  query("select collect_hybrid.roster_interrupted_etag('#{import}','#{sid}');")
end
def transfer_call(request,import,etag)
  "public.admin_transfer_interrupted_roster_import('#{id(request)}','#{import}','#{etag}',true)"
end
def authority_mutation(kind,dst)
  case kind
  when 'current_session' then "delete from auth.sessions where id='#{dst}' and user_id='#{ACTOR}';"
  when 'approval' then "update collect_admin_access.whatsapp_approvals set revoked_at=clock_timestamp() where user_id='#{ACTOR}';"
  when 'role' then "update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='#{ACTOR}' and revoked_at is null;"
  when 'moderate_permission','read_permission' then "delete from public.admin_role_permissions where role_id=(select id from public.admin_roles where name='platform_owner') and permission_name='#{kind=='moderate_permission' ? 'collections.moderate' : 'users.read'}';"
  else raise 'Unknown owned authority case'
  end
end
def restore_authority(kind,permissions)
  case kind
  when 'approval' then "update collect_admin_access.whatsapp_approvals set revoked_at=null where user_id='#{ACTOR}';"
  when 'role' then "update public.admin_user_roles set revoked_at=null where user_id='#{ACTOR}';"
  when 'moderate_permission','read_permission' then "insert into public.admin_role_permissions select * from jsonb_populate_recordset(null::public.admin_role_permissions,#{lit(permissions.to_json)}::jsonb) on conflict(role_id,permission_name) do nothing;"
  else 'select 1;'
  end
end
def draft_call(import,parent,checkpoint,previous=nil,n: 1)
  payload={parent_revision_id:parent,rows:rows(n),title:'Synthetic recovery editor',reason:'Saved synthetic race reason'}.to_json
  "public.admin_save_roster_import_draft('#{import}','#{id(checkpoint)}',#{previous ? lit(previous) : 'null'},#{lit(payload)},'#{Digest::SHA256.hexdigest(payload)}')"
end
def review_intent(import,parent,request,n: 1)
  payload={p_import_id:import,p_parent_revision_id:parent,p_rows:rows(n),p_reason:'Reviewed synthetic race rows',p_request_id:id(request)}.to_json
  sha=Digest::SHA256.hexdigest(payload)
  ["public.admin_stage_roster_import_intent('#{id(request)}','#{import}','review',#{lit(payload)},'#{sha}')",sha]
end
def denial_sql(call,states:,messages:)
  # Catch only the stated contract failures. Preserve unexpected SQLSTATE/message.
  # A caught40001 aborts the operation's subtransaction; no automatic retry occurs.
  <<~SQL
    do $qa$ declare caught boolean:=false; state text; message text; begin
      begin perform #{call}; exception when others then
        get stacked diagnostics state=returned_sqlstate,message=message_text;
        if not state=any(array[#{states.map { |x|lit(x) }.join(',')}])
          or (state<>'40001' and not message=any(array[#{messages.map { |x|lit(x) }.join(',')}])) then raise; end if;
        perform set_config('collect.qa.last_denial',jsonb_build_object('denied',true,'sqlstate',state,'message',message)::text,true);
        caught:=true;
      end;
      if not caught then raise exception 'Expected contract denial; operation unexpectedly succeeded'; end if;
    end $qa$;
    select 'RESULT:'||current_setting('collect.qa.last_denial');
  SQL
end
def begin_worker(w,isolation: 'read committed',snapshot: false)
  write(w,"begin isolation level #{isolation}; select 'XID:'||pg_current_xact_id();#{snapshot ? " select count(*) from collect_hybrid.roster_import_sources;" : ''} select 'TRANSACTION_READY';\n")
  read_until(w,'TRANSACTION_READY')
end
def overlap(holder,waiter,hold_sql,wait_sql,name,observed,repeatable: false,hold_result: true)
  # Establish the waiter's RR snapshot BEFORE the holder changes any row.
  begin_worker(waiter,isolation:'repeatable read',snapshot:true) if repeatable
  begin_worker(holder)
  write(holder,"#{hold_sql}\nselect 'HELD';\n")
  first=read_until(holder,'HELD')
  begin_worker(waiter) unless repeatable
  write(waiter,"#{wait_sql}\ncommit; select 'WAITER_DONE';\n")
  observation=blocked(waiter,holder)
  observed << {scenario:name,repeatable_read_preestablished:repeatable,lock_wait:observation}
  write(holder,"commit; select 'HOLDER_DONE';\n");read_until(holder,'HOLDER_DONE')
  second=read_until(waiter,'WAITER_DONE')
  [hold_result ? result_from(first) : nil,result_from(second)]
end
def check_transfer(ack,request,from,sid,source_etag,recover: true)
  keys=%w[contract_version ok state request_id from_import_id root_import_id to_import_id actor_id destination_session_id destination_reference_id initial_revision_id checkpoint_id draft_sha256 source_etag original_proof_sha256 expires_at]
  raise 'Transfer acknowledgement keys/type/binding invalid' unless ack.keys.sort==keys.sort && ack['contract_version']==1 && ack['ok']==true && ack['state']=='transferred' && ack['request_id']==id(request) && ack['from_import_id']==from && ack['actor_id']==ACTOR && ack['destination_session_id']==sid && ack['source_etag']==source_etag && ack['to_import_id']!=from
  %w[root_import_id to_import_id destination_reference_id initial_revision_id checkpoint_id].each { |key|raise 'Transfer acknowledgement UUID invalid' unless ack.fetch(key).match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/) }
  %w[draft_sha256 source_etag original_proof_sha256].each { |key|raise 'Transfer acknowledgement SHA invalid' unless ack.fetch(key).match?(/\A[a-f0-9]{64}\z/) }
  query(<<~SQL)
    do $$ begin
      if (select count(*) from collect_hybrid.roster_recovery_transfers where request_id='#{id(request)}' and from_import_id='#{from}' and to_import_id='#{ack.fetch('to_import_id')}')<>1
       or (select count(*) from collect_hybrid.roster_import_revisions where import_id='#{ack.fetch('to_import_id')}')<>1
       or exists(select 1 from collect_hybrid.roster_import_recovery_intents where import_id='#{ack.fetch('to_import_id')}')
       or exists(select 1 from collect_hybrid.roster_import_extractions where import_id='#{ack.fetch('to_import_id')}')
       or exists(select 1 from collect_hybrid.roster_import_commits where import_id='#{ack.fetch('to_import_id')}')
       or (select s.expires_at<>root.expires_at from collect_hybrid.roster_import_sources s join collect_hybrid.roster_import_sources root on root.id='#{ack.fetch('root_import_id')}' where s.id='#{ack.fetch('to_import_id')}') then
        raise exception 'Transfer did not create exactly one reset, TTL-preserving branch'; end if;
    end $$;
  SQL
  return ack unless recover
  recovery=result_from(query("#{actor(sid)} select 'RESULT:'||public.admin_recover_roster_import('#{ack.fetch('destination_reference_id')}',null)::text;",transaction:true))
  initial=recovery.fetch('initial_preview')
  raise 'Transfer copied approval or lost proof' unless initial.fetch('can_submit')==false && initial.fetch('requires_human_review')==true && initial.fetch('recovery_lineage').fetch('original_proof_sha256')==ack.fetch('original_proof_sha256') && recovery.fetch('intent').nil?
  draft=recovery.fetch('draft')
  raise 'Recovered editor not rebound to initial unapproved revision' unless JSON.parse(draft.fetch('payload')).fetch('parent_revision_id')==ack.fetch('initial_revision_id') && Digest::SHA256.hexdigest(draft.fetch('payload'))==draft.fetch('payload_sha256')
  ack
end

def graph_sql
  # Upload UUIDs define roots. Only immutable transfer edges add random branches.
  <<~SQL
    create temp table roster_qa_import_graph on commit drop as
      with recursive graph(id) as (
        select id from collect_hybrid.roster_import_sources where actor_id='#{ACTOR}' and request_id::text like '#{PREFIX}-%'
        union select t.to_import_id from collect_hybrid.roster_recovery_transfers t join graph g on g.id=t.from_import_id
          where t.actor_id='#{ACTOR}'
      ) select distinct id from graph;
    create temp table roster_qa_group_graph on commit drop as
      select distinct c.collection_id id from collect_hybrid.roster_import_commits c join roster_qa_import_graph g on g.id=c.import_id
      where c.actor_id='#{ACTOR}' and c.request_id::text like '#{PREFIX}-%' and c.response->>'mode'='create';
    create temp table roster_qa_member_graph on commit drop as
      select distinct member_record_id id from public.collection_members where collection_id in (select id from roster_qa_group_graph) and member_record_id is not null
      union select id from collect_hybrid.member_records where id in ('#{ACTOR}','#{CONTROLLER}');
    create temp table roster_qa_resource_graph on commit drop as
      select r.id from collect_hybrid.roster_resource_reservations r join collect_hybrid.roster_import_sources s on s.request_id=r.request_id
        join roster_qa_import_graph g on g.id=s.id where r.actor_id='#{ACTOR}' and r.request_id::text like '#{PREFIX}-%'
      union select id from collect_hybrid.roster_resource_reservations where actor_id='#{ACTOR}' and request_id::text like '#{PREFIX}-%';
    do $$ declare relation_name text; outlier boolean; begin
      if exists(select 1 from collect_hybrid.roster_import_sources where actor_id='#{ACTOR}' and id not in (select id from roster_qa_import_graph))
       or exists(select 1 from collect_hybrid.roster_recovery_transfers where actor_id='#{ACTOR}' and
          (request_id::text not like '#{PREFIX}-%' or from_import_id not in (select id from roster_qa_import_graph) or to_import_id not in (select id from roster_qa_import_graph) or root_import_id not in (select id from roster_qa_import_graph)))
       or exists(select 1 from collect_hybrid.roster_resource_reservations where actor_id='#{ACTOR}' and id not in (select id from roster_qa_resource_graph))
       or exists(select 1 from public.collections where creator_user_id='#{ACTOR}' and id not in (select id from roster_qa_group_graph))
       or exists(select 1 from collect_hybrid.group_creation_requests where actor_id='#{ACTOR}' and collection_id not in (select id from roster_qa_group_graph))
       or exists(select 1 from collect_hybrid.roster_batches where actor_id='#{ACTOR}' and collection_id not in (select id from roster_qa_group_graph))
       or exists(select 1 from collect_hybrid.member_records where created_by='#{ACTOR}' and id not in (select id from roster_qa_member_graph)) then
        raise exception 'Unattributed synthetic graph; cleanup denied'; end if;
      foreach relation_name in array array['roster_import_extractions','roster_import_revisions','roster_import_results','roster_import_commits','roster_import_recovery_intents','roster_import_editor_drafts'] loop
        execute format('select exists(select 1 from collect_hybrid.%I where actor_id=$1 and import_id not in (select id from roster_qa_import_graph))',relation_name) into strict outlier using '#{ACTOR}'::uuid;
        if outlier then raise exception 'Unattributed owned provenance rows; cleanup denied'; end if;
      end loop;
    end $$;
  SQL
end

def cleanup_sql(tables:,before:,controls:,flag:,permission_rows:,xids:,trigger_guard:,fingerprints:,governance_heads:,baseline_event_ids:)
  <<~SQL
    select pg_advisory_xact_lock(193517,141);
    set local lock_timeout='5s';
    lock table #{CLEANUP_GUARDS.keys.join(',')},collect_security.runtime_control_heads,public.app_realtime_events in access exclusive mode;
    #{trigger_guard}
    do $$ begin
      if current_user<>'postgres' or current_database()<>'postgres' or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
       or (select count(*) from supabase_migrations.schema_migrations)<>#{MIGRATION_COUNT} or (select max(version) from supabase_migrations.schema_migrations)<>#{lit(LATEST_MIGRATION)}
       or (select encode(extensions.digest(statements[1],'sha256'),'hex') from supabase_migrations.schema_migrations where version='20260930170000') is distinct from #{lit(MIGRATION_SHA)}
       or (select encode(extensions.digest(statements[1],'sha256'),'hex') from supabase_migrations.schema_migrations where version='20260930180000') is distinct from #{lit(AUTHORITY_SHA)}
       or exists(select 1 from pg_stat_activity where pid<>pg_backend_pid() and backend_type='client backend' and state<>'idle')
       or exists(select 1 from pg_trigger where tgrelid='public.app_realtime_events'::regclass and not tgisinternal)
       or exists(select 1 from pg_constraint where contype='f' and confrelid='public.app_realtime_events'::regclass) then
        raise exception 'Quiet exact149 cleanup precondition lost'; end if;
    end $$;
    #{graph_sql}
    do $$ begin
      if exists(select 1 from collect_security.runtime_control_events e
        where e.identity_sha256 in (select collect_security.runtime_control_hash(identity) from collect_security.runtime_control_heads h where #{governance_scope('h')})
          and not e.id=any(#{lit('{'+baseline_event_ids.join(',')+'}')}::uuid[])
          and (e.authority<>'database_owner' or e.xmin::text not in (#{xids.map { |x|lit(x) }.join(',')}))) then
        raise exception 'Unattributed governance event; cleanup denied'; end if;
    end $$;
    -- A new FK outside this named graph refuses deletion, before guards change.
    do $$ declare fk record; referenced boolean; fresh_ids text[];
      allowed regclass[]:=array['auth.sessions'::regclass,'public.profiles'::regclass,'collect_admin_access.whatsapp_approvals'::regclass,
        'public.admin_user_roles'::regclass,'public.notification_preferences'::regclass,'public.notification_events'::regclass,
        'collect_hybrid.member_records'::regclass,'collect_hybrid.member_momo_identities'::regclass,'public.collections'::regclass,
        'public.collection_members'::regclass,'public.collection_share_secrets'::regclass,'collect_hybrid.group_creation_requests'::regclass,
        'collect_hybrid.roster_batches'::regclass,#{IMMUTABLE.keys.map { |x|"'#{x}'::regclass" }.join(',')},'public.audit_logs'::regclass,
        'public.feature_flags'::regclass,'collect_hybrid.roster_import_editor_drafts'::regclass];
    begin
      select array_agg(id::text) into fresh_ids from (
        select id from roster_qa_import_graph union select id from roster_qa_group_graph union select id from roster_qa_member_graph
        union select id from roster_qa_resource_graph union select id from collect_hybrid.roster_import_revisions where import_id in (select id from roster_qa_import_graph)
        union select id from collect_hybrid.roster_import_extractions where import_id in (select id from roster_qa_import_graph)
        union select '#{ACTOR}'::uuid union select '#{CONTROLLER}'::uuid
      ) graph_ids;
      for fk in select c.conrelid::regclass child,c.confrelid::regclass parent,
        (select string_agg(format('child.%I=parent.%I',ca.attname,pa.attname),' and ' order by k.ordinality)
          from unnest(c.conkey,c.confkey) with ordinality k(child_col,parent_col,ordinality)
          join pg_attribute ca on ca.attrelid=c.conrelid and ca.attnum=k.child_col join pg_attribute pa on pa.attrelid=c.confrelid and pa.attnum=k.parent_col) predicate
        from pg_constraint c where c.contype='f' and c.confrelid in ('auth.users'::regclass,'public.profiles'::regclass,'public.collections'::regclass,
          'collect_hybrid.member_records'::regclass,'collect_hybrid.roster_import_sources'::regclass,'collect_hybrid.roster_import_extractions'::regclass,
          'collect_hybrid.roster_import_revisions'::regclass,'collect_hybrid.roster_resource_reservations'::regclass) and not c.conrelid=any(allowed) loop
        execute format('select exists(select 1 from %s child join %s parent on %s where to_jsonb(parent)->>''id''=any($1))',fk.child,fk.parent,fk.predicate) into referenced using fresh_ids;
        if referenced then raise exception 'Unknown synthetic FK/reference from %',fk.child; end if;
      end loop;
    end $$;
    #{CLEANUP_GUARDS.map { |t,n|"alter table #{t} disable trigger #{n};" }.join("\n")}
    -- Delete through proven IDs, including transfer edges before their parents.
    delete from collect_hybrid.roster_recovery_transfers where from_import_id in (select id from roster_qa_import_graph) and to_import_id in (select id from roster_qa_import_graph);
    delete from collect_hybrid.roster_import_recovery_intents where import_id in (select id from roster_qa_import_graph);
    delete from collect_hybrid.roster_import_editor_drafts where import_id in (select id from roster_qa_import_graph);
    delete from collect_hybrid.roster_import_commits where import_id in (select id from roster_qa_import_graph);
    delete from collect_hybrid.roster_import_results where import_id in (select id from roster_qa_import_graph);
    delete from collect_hybrid.roster_import_revisions where import_id in (select id from roster_qa_import_graph);
    delete from collect_hybrid.roster_import_extractions where import_id in (select id from roster_qa_import_graph);
    delete from collect_hybrid.roster_import_sources where id in (select id from roster_qa_import_graph);
    delete from collect_hybrid.roster_source_verifications where reservation_id in (select id from roster_qa_resource_graph);
    delete from collect_hybrid.roster_resource_completions where reservation_id in (select id from roster_qa_resource_graph);
    delete from collect_hybrid.roster_resource_reservations where id in (select id from roster_qa_resource_graph);
    delete from collect_hybrid.roster_batches where collection_id in (select id from roster_qa_group_graph) and actor_id='#{ACTOR}';
    delete from collect_hybrid.group_creation_requests where collection_id in (select id from roster_qa_group_graph) and actor_id='#{ACTOR}';
    delete from public.collection_members where collection_id in (select id from roster_qa_group_graph);
    delete from public.collection_share_secrets where collection_id in (select id from roster_qa_group_graph);
    delete from public.collections where id in (select id from roster_qa_group_graph);
    delete from collect_hybrid.member_momo_identities where member_id in (select id from roster_qa_member_graph);
    update public.feature_flags set (enabled,updated_by,updated_reason,updated_at)=(select f.enabled,f.updated_by,f.updated_reason,f.updated_at from jsonb_populate_record(null::public.feature_flags,#{lit(flag.to_json)}::jsonb) f) where key='hybrid_member_onboarding';
    -- Permission deletions are exact pre-run rows; no guessed timestamps/defaults.
    insert into public.admin_role_permissions select * from jsonb_populate_recordset(null::public.admin_role_permissions,#{lit(permission_rows.to_json)}::jsonb) on conflict(role_id,permission_name) do nothing;
    delete from public.notification_events where user_id in ('#{ACTOR}','#{CONTROLLER}');
    delete from public.audit_logs where actor_user_id in ('#{ACTOR}','#{CONTROLLER}');
    delete from auth.users where id in ('#{ACTOR}','#{CONTROLLER}');
    delete from collect_security.runtime_control_events e
      where e.identity_sha256 in (select collect_security.runtime_control_hash(identity) from collect_security.runtime_control_heads h where #{governance_scope('h')})
        and not e.id=any(#{lit('{'+baseline_event_ids.join(',')+'}')}::uuid[])
        and e.authority='database_owner' and e.xmin::text in (#{xids.map { |x|lit(x) }.join(',')});
    delete from collect_security.runtime_control_heads h where #{governance_scope('h')};
    insert into collect_security.runtime_control_heads
      select * from jsonb_populate_recordset(null::collect_security.runtime_control_heads,#{lit(governance_heads.to_json)}::jsonb);
    do $$ declare fk record; referenced boolean; members uuid[]:=(select array_agg(id) from roster_qa_member_graph); begin
      if exists(select 1 from collect_hybrid.member_records where id=any(members) and linked_user_id is not null) then raise exception 'Synthetic member remains linked'; end if;
      for fk in select c.conrelid::regclass relation,a.attname,cardinality(c.conkey) key_count from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1] where c.contype='f' and c.confrelid='collect_hybrid.member_records'::regclass loop
        if fk.key_count<>1 then raise exception 'Unexpected composite member reference'; end if;
        execute format('select exists(select 1 from %s where %I=any($1))',fk.relation,fk.attname) into referenced using members;
        if referenced then raise exception 'Synthetic member still referenced by %',fk.relation; end if;
      end loop;
      delete from collect_hybrid.member_records where id=any(members) and linked_user_id is null;
    end $$;
    #{CLEANUP_GUARDS.map { |t,n|"alter table #{t} enable trigger #{n};" }.join("\n")}
    delete from public.app_realtime_events where xmin::text in (#{xids.map { |x|lit(x) }.join(',')}) or xmin::text=pg_current_xact_id()::text;
    do $$ begin
      if (#{digest_sql(tables)}) is distinct from #{lit(before)} then
        raise notice 'ROSTER_RESIDUAL_BASELINE:%',#{lit(fingerprints.to_json)}::jsonb;
        raise notice 'ROSTER_RESIDUAL_CURRENT:%',(#{fingerprints_sql(tables)});
        raise exception 'Full all-table baseline mismatch; cleanup rolled back'; end if;
      if (#{controls_sql.strip}) is distinct from #{lit(controls)} then raise exception 'Catalog/cron controls mismatch; cleanup rolled back'; end if;
    end $$;
  SQL
end
if __FILE__ == $PROGRAM_NAME
  raise 'Set COLLECT_ROSTER_PROVENANCE_QA=isolated_clone' unless ENV['COLLECT_ROSTER_PROVENANCE_QA']=='isolated_clone'
  raise 'New absolute COLLECT_ROSTER_CHECKPOINT path required' unless CHECKPOINT_PATH && CHECKPOINT_PATH.start_with?('/') && !File.exist?(CHECKPOINT_PATH) && !File.symlink?(CHECKPOINT_PATH) && Dir.exist?(File.dirname(CHECKPOINT_PATH))
  raise 'Explicit reviewed149 SHA required' unless MIGRATION_SHA.match?(/\A[a-f0-9]{64}\z/)
  raise 'Reviewed migration149 changed' unless Digest::SHA256.file(File.join(ROOT,MIGRATION)).hexdigest==MIGRATION_SHA
  raise 'Explicit reviewed150 SHA required' unless AUTHORITY_SHA.match?(/\A[a-f0-9]{64}\z/)
  raise 'Reviewed authority migration150 changed' unless Digest::SHA256.file(File.join(ROOT,AUTHORITY_MIGRATION)).hexdigest==AUTHORITY_SHA
  raw,err,status=Open3.capture3('docker','inspect',CONTAINER);raise err unless status.success?
  container=JSON.parse(raw).fetch(0); labels=container.fetch('Config').fetch('Labels')
  ports=container.fetch('HostConfig').fetch('PortBindings').fetch('5432/tcp')
  config=File.read(File.join(ROOT,'.cache/financial-concurrency-20260929/supabase/config.toml'))
  db=config[/^\[db\]\s*\n(.*?)(?=^\[|\z)/m,1]
  raise 'Exact task fixture provenance required' unless container.dig('State','Running') && labels['com.supabase.cli.project']==PROJECT && labels['com.docker.compose.project']==PROJECT && config.match?(/^project_id = "#{PROJECT}"$/) && db&.match?(/^port = 55722$/) && !ports.empty? && ports.all? { |v|v['HostPort']=='55722' }
  query(<<~SQL)
    do $$ begin
      if current_database()<>'postgres' or current_user<>'postgres' or (select rolsuper from pg_roles where rolname=current_user)
       or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
       or (select count(*) from supabase_migrations.schema_migrations)<>#{MIGRATION_COUNT} or (select max(version) from supabase_migrations.schema_migrations)<>#{lit(LATEST_MIGRATION)}
       or (select encode(extensions.digest(statements[1],'sha256'),'hex') from supabase_migrations.schema_migrations where version='20260930170000') is distinct from #{lit(MIGRATION_SHA)}
       or (select encode(extensions.digest(statements[1],'sha256'),'hex') from supabase_migrations.schema_migrations where version='20260930180000') is distinct from #{lit(AUTHORITY_SHA)}
       or exists(select 1 from auth.users where id::text like '#{PREFIX}-%' or phone in ('250788988001','250788988002'))
       or exists(select 1 from auth.sessions where id::text like '#{PREFIX}-%')
       or exists(select 1 from public.profiles where id::text like '#{PREFIX}-%' or momo_number like '%789988%')
       or exists(select 1 from collect_hybrid.member_records where id::text like '#{PREFIX}-%' or created_by in ('#{ACTOR}','#{CONTROLLER}'))
       or exists(select 1 from collect_hybrid.member_momo_identities where momo_number like '+250789988%')
       or exists(select 1 from collect_hybrid.roster_import_sources where request_id::text like '#{PREFIX}-%' or actor_id in ('#{ACTOR}','#{CONTROLLER}'))
       or exists(select 1 from collect_hybrid.roster_recovery_transfers where request_id::text like '#{PREFIX}-%' or actor_id in ('#{ACTOR}','#{CONTROLLER}'))
       or exists(select 1 from collect_hybrid.roster_resource_reservations where request_id::text like '#{PREFIX}-%' or actor_id in ('#{ACTOR}','#{CONTROLLER}'))
       or exists(select 1 from public.notification_device_tokens) or exists(select 1 from public.notification_deliveries)
       or exists(select 1 from pg_stat_activity where pid<>pg_backend_pid() and backend_type='client backend' and state<>'idle')
       or exists(select 1 from pg_stat_activity where application_name in ('#{WORKER_A}','#{WORKER_B}')) then
        raise exception 'Quiet ordinary-owner150 with reviewed149/150, inactive providers and unused9988 namespace required'; end if;
    end $$;
  SQL
  triggers=CLEANUP_GUARDS.map { |table,name|"('#{table}'::regclass,'#{name}')" }.join(',')
  trigger_guard=<<~SQL
    do $$ declare x record; begin for x in select * from (values #{triggers}) expected(relation,name) loop
      if (select count(*) from pg_trigger where tgrelid=x.relation and tgname=x.name and not tgisinternal and tgenabled='O')<>1
       or exists(select 1 from pg_trigger where tgrelid=x.relation and not tgisinternal and (tgtype::int & 2)=2 and (tgtype::int & 8)=8 and tgname<>x.name) then
        raise exception 'Unexpected immutable DELETE guard; cleanup authorization refused'; end if;
    end loop; end $$;
  SQL
  query(trigger_guard)
  tables=snapshot_tables;before=query(digest_sql(tables)+';');controls=query(controls_sql+';')
  fingerprints=JSON.parse(query(fingerprints_sql(tables)+';'))
  flag=JSON.parse(query("select to_jsonb(f) from public.feature_flags f where key='hybrid_member_onboarding';"))
  permissions=JSON.parse(query("select coalesce(jsonb_agg(to_jsonb(rp) order by permission_name),'[]') from public.admin_role_permissions rp join public.admin_roles r on r.id=rp.role_id where r.name='platform_owner' and rp.permission_name in ('collections.moderate','users.read');"))
  governance_heads=JSON.parse(query("select coalesce(jsonb_agg(to_jsonb(h) order by family,identity::text),'[]') from collect_security.runtime_control_heads h where #{governance_scope('h')};"))
  baseline_event_ids=JSON.parse(query("select coalesce(jsonb_agg(id order by id),'[]') from collect_security.runtime_control_events;"))
  raise 'Expected exact platform-owner permissions missing' unless permissions.length==2
  financial=%w[public.payments public.ledger_entries collect_hybrid.momo_journal_entries collect_hybrid.momo_journal_lines collect_hybrid.collection_balances collect_hybrid.member_balances]
  financial_before=query(digest_sql(financial)+';')
  CHECKPOINT.merge!('phase'=>'baseline_before_seed','fixture'=>PROJECT,'source_sha256'=>Digest::SHA256.file(__FILE__).hexdigest,'migration_sha256'=>MIGRATION_SHA,'authority_migration_sha256'=>AUTHORITY_SHA,'migration_count'=>MIGRATION_COUNT,'baseline_tables'=>tables,'baseline_fingerprints'=>fingerprints,'baseline_sha256'=>before,'controls_sha256'=>controls,'feature_flag'=>flag,'permission_rows'=>permissions,'governance_heads'=>governance_heads,'baseline_governance_event_ids'=>baseline_event_ids)
  File.open(CHECKPOINT_PATH,File::WRONLY|File::CREAT|File::EXCL,0600) { |f|f.write(JSON.pretty_generate(CHECKPOINT)+"\n");f.flush;f.fsync }
  workers=[];seeded=false;failure=nil;cleanup_failure=nil;result=nil;observed=[];acks=[]
  begin
    seeded=true
    query(<<~SQL,transaction:true)
      insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data) values
       ('#{ACTOR}','authenticated','authenticated','250788988001',now(),'{}','{}'),
       ('#{CONTROLLER}','authenticated','authenticated','250788988002',now(),'{}','{}');
      update public.profiles set country_code='RW',currency_code='RWF' where id in ('#{ACTOR}','#{CONTROLLER}');
      insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason) values
       ('#{ACTOR}','+250788988001',clock_timestamp()-interval '20 minutes','Synthetic149 actor approval'),
       ('#{CONTROLLER}','+250788988002',clock_timestamp()-interval '20 minutes','Synthetic149 controller approval');
      insert into public.admin_user_roles(user_id,role_id,reason,created_at)
       select a.id,r.id,'Synthetic149 concurrency role',clock_timestamp()-interval '19 minutes' from (values('#{ACTOR}'::uuid),('#{CONTROLLER}'::uuid)) a(id) cross join public.admin_roles r where r.name='platform_owner';
      insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values('#{CONTROL_SESSION}','#{CONTROLLER}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
      update public.feature_flags set enabled=true where key='hybrid_member_onboarding';
    SQL
    a=worker_start(WORKER_A,workers);b=worker_start(WORKER_B,workers)
    # Exact transfer replay, competing request CAS and lost-response status.
    old=session(1);source,preview=prepared(1,old);import=source.fetch('import_id');fresh=fresh_session(2);tag=etag(import,fresh)
    call=transfer_call(2001,import,tag)
    ack,replay=overlap(a,b,"#{actor(fresh)} select 'RESULT:'||#{call}::text;","#{actor(fresh)} select 'RESULT:'||#{call}::text;",'exact_request_replay_waits_for_one_branch',observed)
    raise 'Concurrent replay response differs' unless ack==replay
    acks<<check_transfer(ack,2001,import,fresh,tag)
    status_ack=result_from(query("#{actor(fresh)} select 'RESULT:'||public.admin_get_roster_transfer_status('#{id(2001)}')::text;",transaction:true))
    raise 'Lost transfer response status differs' unless status_ack==ack
    query("#{actor(fresh)} #{denial_sql(transfer_call(2002,import,tag),states:['55000'],messages:['roster_recovery_transferred'])}",transaction:true)
    observed<<{scenario:'response_loss_status_and_distinct_request_old_leaf_denial',lock_wait:nil}
    # Every old mutation is fenced in both winner directions. Each race owns a new source.
    %w[checkpoint review stage execute commit].each_with_index do |kind,index|
      n=10+index;old=session(100+n);s,p=prepared(n,old);imp=s.fetch('import_id');latest=p
      if kind=='commit'
        latest=result_from(query("#{actor(old)} select 'RESULT:'||#{review_call(n,imp,p.fetch('revision_id'),request:5000+n)}::text;",transaction:true))
      end
      stage,hash=review_intent(imp,latest.fetch('revision_id'),6000+n,n:n)
      query("#{actor(old)} select #{stage};",transaction:true) if kind=='execute'
      operation=case kind
        when 'checkpoint' then draft_call(imp,latest.fetch('revision_id'),7000+n,n:n)
        when 'review' then review_call(n,imp,latest.fetch('revision_id'),changed:true,request:5000+n)
        when 'stage' then stage
        when 'execute' then "public.admin_execute_roster_import_intent('#{id(6000+n)}','#{hash}',true)"
        when 'commit' then commit_call(n,latest)
      end
      dst=fresh_session(200+n);tag=etag(imp,dst);tcall=transfer_call(2100+n,imp,tag)
      hold,denied=overlap(a,b,"#{actor(dst)} select 'RESULT:'||#{tcall}::text;","#{actor(old)} #{denial_sql(operation,states:['55000'],messages:['roster_recovery_transferred'])}","transfer_wins_old_#{kind}_denied",observed)
      raise 'Old mutation denial not reported' unless denied['denied'];acks<<check_transfer(hold,2100+n,imp,dst,tag)
      n=20+index;old=session(100+n);s,p=prepared(n,old);imp=s.fetch('import_id');latest=p
      if kind=='commit'
        latest=result_from(query("#{actor(old)} select 'RESULT:'||#{review_call(n,imp,p.fetch('revision_id'),request:5000+n)}::text;",transaction:true))
      end
      stage,hash=review_intent(imp,latest.fetch('revision_id'),6000+n,n:n)
      query("#{actor(old)} select #{stage};",transaction:true) if kind=='execute'
      operation=case kind
        when 'checkpoint' then draft_call(imp,latest.fetch('revision_id'),7000+n,n:n)
        when 'review' then review_call(n,imp,latest.fetch('revision_id'),changed:true,request:5000+n)
        when 'stage' then stage
        when 'execute' then "public.admin_execute_roster_import_intent('#{id(6000+n)}','#{hash}',true)"
        when 'commit' then commit_call(n,latest)
      end
      dst=fresh_session(200+n);tag=etag(imp,dst)
      expected=kind=='commit' ? 'roster_import_committed' : 'roster_draft_superseded'
      _,denied=overlap(a,b,"#{actor(old)} select 'RESULT:'||#{operation}::text;","#{actor(dst)} #{denial_sql(transfer_call(2100+n,imp,tag),states:['55000'],messages:[expected])}","old_#{kind}_wins_stale_transfer_denied",observed)
      raise 'Stale transfer denial not reported' unless denied['denied']
    end
    # Original service replay can complete before a transfer, but no provider
    # completion/failure/resource path may replay after its old leaf transfers.
    %w[preview resources].each_with_index do |kind,index|
      [false,true].each do |service_wins|
        n=300+index*2+(service_wins ? 1 : 0);old=session(3000+n);s,p=prepared(n,old);dst=fresh_session(3100+n);tag=etag(s.fetch('import_id'),dst)
        reservation=query("select id from collect_hybrid.roster_resource_reservations where request_id='#{id(100+n)}';")
        op=kind=='preview' ? "public.complete_roster_import_preview('#{s.fetch('import_id')}','#{ACTOR}','#{old}',#{lit([candidate(n)].to_json)},'{\"processing_method\":\"deterministic\",\"provider_response_sha256\":null,\"provider_response_id\":null}')" : "public.finish_roster_resources('#{reservation}','#{ACTOR}','#{old}','preview_ready')"
        tcall=transfer_call(2800+n,s.fetch('import_id'),tag)
        if service_wins
          _,ack=overlap(a,b,"#{service} select 'RESULT:'||#{op}::text;","#{actor(dst)} select 'RESULT:'||#{tcall}::text;","original_service_#{kind}_replay_wins_before_transfer",observed)
        else
          ack,denied=overlap(a,b,"#{actor(dst)} select 'RESULT:'||#{tcall}::text;","#{service} #{denial_sql(op,states:['55000'],messages:['roster_recovery_transferred'])}","transfer_wins_original_service_#{kind}_replay_denied",observed)
          raise 'Transferred provider replay unexpectedly allowed' unless denied['denied']
        end
        acks<<check_transfer(ack,2800+n,s.fetch('import_id'),dst,tag)
        query("#{service} #{denial_sql("public.fail_roster_import_preview('#{s.fetch('import_id')}','#{ACTOR}','#{old}','roster_extraction_timeout')",states:['55000'],messages:['roster_recovery_transferred'])}",transaction:true)
        query("#{service} #{denial_sql("public.complete_roster_import_preview('#{ack.fetch('to_import_id')}','#{ACTOR}','#{dst}',#{lit([candidate(n)].to_json)},'{\"processing_method\":\"deterministic\",\"provider_response_sha256\":null,\"provider_response_id\":null}')",states:['55000'],messages:['roster_recovery_provider_replay_forbidden'])}",transaction:true)
      end
    end
    # Auth deletion of an old logged-out source session must not defeat fresh recovery.
    old=session(330);s,p=prepared(30,old);dst=fresh_session(331);tag=etag(s.fetch('import_id'),dst)
    query("delete from auth.sessions where id='#{old}' and user_id='#{ACTOR}';",transaction:true)
    ack=result_from(query("#{actor(dst)} select 'RESULT:'||#{transfer_call(2230,s.fetch('import_id'),tag)}::text;",transaction:true))
    acks<<check_transfer(ack,2230,s.fetch('import_id'),dst,tag)
    reviewed=result_from(query("#{actor(dst)} select 'RESULT:'||#{review_call(30,ack.fetch('to_import_id'),ack.fetch('initial_revision_id'),request:5030)}::text;",transaction:true))
    committed=result_from(query("#{actor(dst)} select 'RESULT:'||#{commit_call(30,reviewed)}::text;",transaction:true))
    raise 'Logged-out source fresh recovery could not explicitly commit' unless committed.fetch('ok') && committed.fetch('import_id')==ack.fetch('to_import_id')
    observed<<{scenario:'old_session_deleted_fresh_transfer_review_explicit_commit',lock_wait:nil}
    # Current fresh-session/approval/role/permission revocation with stale RR snapshots.
    %w[current_session approval role moderate_permission read_permission].each_with_index do |kind,index|
      n=40+index;old=session(400+n);s,p=prepared(n,old);dst=fresh_session(500+n);tag=etag(s.fetch('import_id'),dst)
      mutate=authority_mutation(kind,dst)
      hold="select public._lock_notification_session_gate(); select pg_advisory_xact_lock(hashtext('collect_admin_combined_roster')); #{mutate} select 'RESULT:'||'{\"changed\":true}';"
      _,denied=overlap(a,b,hold,"#{actor(dst)} #{denial_sql(transfer_call(2240+n,s.fetch('import_id'),tag),states:['40001','42501'],messages:['roster_actor_unavailable'])}","repeatable_read_#{kind}_revocation_wins",observed,repeatable:true)
      raise 'Authority revocation not denied/serialized' unless denied['denied']
      restore=restore_authority(kind,permissions)
      query(restore,transaction:true)
    end
    # Reverse direction: transfer commits once, then revocation must deny the
    # fresh branch's read and write paths without altering its issued proof.
    %w[current_session approval role moderate_permission read_permission].each_with_index do |kind,index|
      n=150+index;old=session(1500+n);s,p=prepared(n,old);dst=fresh_session(1600+n);tag=etag(s.fetch('import_id'),dst)
      revoke="select public._lock_notification_session_gate(); select pg_advisory_xact_lock(hashtext('collect_admin_combined_roster')); #{authority_mutation(kind,dst)} select 'RESULT:'||'{\"changed\":true}';"
      ack,_=overlap(a,b,"#{actor(dst)} select 'RESULT:'||#{transfer_call(2600+n,s.fetch('import_id'),tag)}::text;",revoke,"transfer_wins_before_#{kind}_revocation",observed)
      acks<<check_transfer(ack,2600+n,s.fetch('import_id'),dst,tag,recover:false)
      branch=ack.fetch('to_import_id')
      ["public.admin_recover_roster_import('#{ack.fetch('destination_reference_id')}',null)",
       "public.admin_get_roster_import('#{branch}')",
       draft_call(branch,ack.fetch('initial_revision_id'),16000+n,n:n),
       review_call(n,branch,ack.fetch('initial_revision_id'),request:17000+n)].each do |op|
        query("#{actor(dst)} #{denial_sql(op,states:['42501'],messages:['roster_actor_unavailable'])}",transaction:true)
      end
      raise 'Revocation changed original proof' unless query("select original_proof_sha256 from collect_hybrid.roster_recovery_transfers where request_id='#{id(2600+n)}';")==ack.fetch('original_proof_sha256')
      query(restore_authority(kind,permissions),transaction:true)
    end
    # Feature revocation wins an overlapping transfer; then restore for later cases.
    old=session(460);s,p=prepared(60,old);dst=fresh_session(560);tag=etag(s.fetch('import_id'),dst)
    overlap(a,b,"select public._lock_notification_session_gate(); select pg_advisory_xact_lock(hashtext('collect_admin_combined_roster')); update public.feature_flags set enabled=false where key='hybrid_member_onboarding'; select 'RESULT:'||'{\"changed\":true}';","#{actor(dst)} #{denial_sql(transfer_call(2260,s.fetch('import_id'),tag),states:['55000'],messages:['roster_feature_disabled'])}",'feature_revocation_wins_transfer',observed)
    query("update public.feature_flags set enabled=true where key='hybrid_member_onboarding';",transaction:true)
    old=session(461);s,p=prepared(61,old);dst=fresh_session(561);tag=etag(s.fetch('import_id'),dst)
    ack,_=overlap(a,b,"#{actor(dst)} select 'RESULT:'||#{transfer_call(2261,s.fetch('import_id'),tag)}::text;","select public._lock_notification_session_gate(); select pg_advisory_xact_lock(hashtext('collect_admin_combined_roster')); update public.feature_flags set enabled=false where key='hybrid_member_onboarding'; select 'RESULT:'||'{\"changed\":true}';",'transfer_wins_before_feature_revocation',observed)
    acks<<check_transfer(ack,2261,s.fetch('import_id'),dst,tag,recover:false)
    query("#{actor(dst)} #{denial_sql("public.admin_recover_roster_import('#{ack.fetch('destination_reference_id')}',null)",states:['55000'],messages:['roster_feature_disabled'])}",transaction:true)
    query("update public.feature_flags set enabled=true where key='hybrid_member_onboarding';",transaction:true)
    # Signed-JWT deadline crosses while blocked on the real roster gate. The
    # resumed operation must re-evaluate current authority rather than write.
    old=session(462);s,p=prepared(62,old);dst=fresh_session(562);tag=etag(s.fetch('import_id'),dst)
    begin_worker(a);write(a,"select public._lock_notification_session_gate(); select pg_advisory_xact_lock(hashtext('collect_admin_combined_roster')); select 'JWT_HELD';\n");read_until(a,'JWT_HELD')
    jwt_expiry=Time.now.to_i+4
    begin_worker(b);write(b,"#{actor(dst,exp:jwt_expiry)} #{denial_sql(transfer_call(2262,s.fetch('import_id'),tag),states:['42501'],messages:['roster_fresh_auth_required'])} commit; select 'JWT_DENIED';\n")
    observed<<{scenario:'JWT_deadline_crosses_blocked_transfer',lock_wait:blocked(b,a),jwt_expiry:jwt_expiry}
    write(a,"select pg_sleep(greatest(0,#{jwt_expiry}-extract(epoch from clock_timestamp()))+0.2); commit; select 'JWT_RELEASED';\n");read_until(a,'JWT_RELEASED');read_until(b,'JWT_DENIED')
    # Deadline crosses while the transfer is blocked: no expired branch may commit.
    old=session(470);s,p=prepared(70,old,ttl:8);dst=fresh_session(570);tag=etag(s.fetch('import_id'),dst)
    begin_worker(a);write(a,"select public._lock_notification_session_gate(); select pg_advisory_xact_lock(hashtext('collect_admin_combined_roster')); select 'EXPIRY_HELD';\n");read_until(a,'EXPIRY_HELD')
    begin_worker(b);write(b,"#{actor(dst)} #{denial_sql(transfer_call(2270,s.fetch('import_id'),tag),states:['55000'],messages:['roster_import_expired'])} commit; select 'EXPIRY_DENIED';\n")
    observed<<{scenario:'source_deadline_crosses_blocked_transfer',lock_wait:blocked(b,a)}
    write(a,"select pg_sleep(greatest(0,extract(epoch from ('#{s.fetch('expires_at')}'::timestamptz-clock_timestamp())))+0.1); commit; select 'EXPIRY_RELEASED';\n");read_until(a,'EXPIRY_RELEASED');read_until(b,'EXPIRY_DENIED')
    # A→B→C and total8 handoffs; fresh branch always starts with review required.
    old=session(480);root,initial=prepared(80,old);leaf=root.fetch('import_id');parent=initial.fetch('revision_id');sid=old
    8.times do |index|
      dst=fresh_session(600+index);tag=etag(leaf,dst);request=2400+index
      ack=result_from(query("#{actor(dst)} select 'RESULT:'||#{transfer_call(request,leaf,tag)}::text;",transaction:true));acks<<check_transfer(ack,request,leaf,dst,tag)
      raise 'Lineage root or proof drift' unless ack.fetch('root_import_id')==root.fetch('import_id') && (index==0 || ack.fetch('original_proof_sha256')==acks[-2].fetch('original_proof_sha256'))
      leaf=ack.fetch('to_import_id');parent=ack.fetch('initial_revision_id');sid=dst
    end
    dst=fresh_session(608);tag=etag(leaf,dst)
    query("#{actor(dst)} #{denial_sql(transfer_call(2408,leaf,tag),states:['55000'],messages:['roster_recovery_limit'])}",transaction:true)
    raise 'Handoff ceiling not8' unless query("select count(*) from collect_hybrid.roster_recovery_transfers where root_import_id='#{root.fetch('import_id')}';")=='8'
    observed<<{scenario:'A_B_C_lineage_and_eight_handoff_ceiling',lock_wait:nil}
    # Aggregate human-review ceiling across old and recovered branches:9+10=19.
    old=session(490);root,initial=prepared(90,old);parent=initial.fetch('revision_id')
    9.times { |index| parent=result_from(query("#{actor(old)} select 'RESULT:'||#{review_call(90,root.fetch('import_id'),parent,request:8000+index)}::text;",transaction:true)).fetch('revision_id') }
    dst=fresh_session(590);tag=etag(root.fetch('import_id'),dst)
    ack=result_from(query("#{actor(dst)} select 'RESULT:'||#{transfer_call(2490,root.fetch('import_id'),tag)}::text;",transaction:true));acks<<check_transfer(ack,2490,root.fetch('import_id'),dst,tag)
    parent=ack.fetch('initial_revision_id')
    10.times { |index| parent=result_from(query("#{actor(dst)} select 'RESULT:'||#{review_call(90,ack.fetch('to_import_id'),parent,request:8100+index)}::text;",transaction:true)).fetch('revision_id') }
    query("#{actor(dst)} #{denial_sql(review_call(90,ack.fetch('to_import_id'),parent,request:8199),states:['55000'],messages:['roster_revision_limit'])}",transaction:true)
    raise 'Aggregate review ceiling differs from19' unless query("select count(*) from collect_hybrid.roster_import_revisions where processing_method='human_review' and collect_hybrid.roster_recovery_root(import_id)='#{root.fetch('import_id')}';")=='19'
    observed<<{scenario:'nineteen_human_reviews_across_lineage',lock_wait:nil}
    # Aggregate staged intent ceiling across old and recovered branches:20+20=40.
    old=session(491);root,initial=prepared(91,old)
    20.times { |index|stage,_=review_intent(root.fetch('import_id'),initial.fetch('revision_id'),9000+index,n:91);query("#{actor(old)} select #{stage};",transaction:true) }
    dst=fresh_session(591);tag=etag(root.fetch('import_id'),dst)
    ack=result_from(query("#{actor(dst)} select 'RESULT:'||#{transfer_call(2491,root.fetch('import_id'),tag)}::text;",transaction:true));acks<<check_transfer(ack,2491,root.fetch('import_id'),dst,tag)
    20.times { |index|stage,_=review_intent(ack.fetch('to_import_id'),ack.fetch('initial_revision_id'),9100+index,n:91);query("#{actor(dst)} select #{stage};",transaction:true) }
    stage,_=review_intent(ack.fetch('to_import_id'),ack.fetch('initial_revision_id'),9199,n:91)
    query("#{actor(dst)} #{denial_sql(stage,states:['55000'],messages:['roster_recovery_limit'])}",transaction:true)
    raise 'Aggregate intent ceiling differs from40' unless query("select count(*) from collect_hybrid.roster_import_recovery_intents where collect_hybrid.roster_recovery_root(import_id)='#{root.fetch('import_id')}';")=='40'
    observed<<{scenario:'forty_staged_intents_across_lineage',lock_wait:nil}
    # RR actor-draft quota uses DISTINCT imports; no same-source row update can mask a broken singleton fence.
    draft_count=Integer(query("select count(*) from collect_hybrid.roster_import_editor_drafts where actor_id='#{ACTOR}' and expires_at>clock_timestamp();"))
    raise 'Earlier cases exhausted draft quota' if draft_count>39
    (39-draft_count).times do |index|
      n=500+index;old=session(1000+index);s,p=prepared(n,old)
      query("#{actor(old)} select #{draft_call(s.fetch('import_id'),p.fetch('revision_id'),10000+index,n:n)};",transaction:true)
    end
    s1=session(1800);source1,p1=prepared(800,s1);s2=session(1801);source2,p2=prepared(801,s2)
    _,denied=overlap(a,b,"#{actor(s1)} select 'RESULT:'||#{draft_call(source1.fetch('import_id'),p1.fetch('revision_id'),10800,n:800)}::text;","#{actor(s2)} #{denial_sql(draft_call(source2.fetch('import_id'),p2.fetch('revision_id'),10801,n:801),states:['40001'],messages:[])}",'repeatable_read_distinct_import_actor_draft_quota',observed,repeatable:true)
    raise 'Stale RR draft waiter did not abort' unless denied['sqlstate']=='40001'
    raise 'Actor draft quota exceeded40' unless query("select count(*) from collect_hybrid.roster_import_editor_drafts where actor_id='#{ACTOR}' and expires_at>clock_timestamp();")=='40'
    # Seed awaiting-preview sources through the real INSERT guard to99 total;
    # quota fixture clones deterministic metadata, never extraction/approval data.
    source_count=Integer(query("select count(*) from collect_hybrid.roster_import_sources where actor_id='#{ACTOR}' and created_at>clock_timestamp()-interval '24 hours';"))
    raise 'Earlier cases exhausted source quota' if source_count>99
    (99-source_count).times do |index|
      query("insert into collect_hybrid.roster_import_sources(request_id,actor_id,session_id,source_kind,source_sha256,source_size,client_filename,declared_mime,detected_type,derived_sha256,derived_size,ai_consent,consent_version,parser_version,schema_version,input_sha256,expires_at) select '#{id(20000+index)}',actor_id,session_id,source_kind,source_sha256,source_size,client_filename,declared_mime,detected_type,derived_sha256,derived_size,ai_consent,consent_version,parser_version,schema_version,input_sha256,expires_at from collect_hybrid.roster_import_sources where id='#{source1.fetch('import_id')}';",transaction:true)
    end
    pending=[]
    [802,803].each do |n|
      sha=Digest::SHA256.hexdigest("synthetic quota source #{n}")
      query("#{service} select public.reserve_roster_resources('#{ACTOR}','#{s1}','#{id(100+n)}','#{sha}','text',99,null);",transaction:true)
      pending<<"public.create_roster_import_source('#{ACTOR}','#{s1}','#{id(100+n)}','text','#{sha}',99,'synthetic-#{n}.txt','text/plain','utf8_text',null,null,false,null,null)"
    end
    _,denied=overlap(a,b,"#{service} select 'RESULT:'||#{pending[0]}::text;","#{service} #{denial_sql(pending[1],states:['40001'],messages:[])}",'repeatable_read_distinct_request_actor_source_quota',observed,repeatable:true)
    raise 'Stale RR source waiter did not abort' unless denied['sqlstate']=='40001'
    raise 'Actor source quota exceeded100' unless query("select count(*) from collect_hybrid.roster_import_sources where actor_id='#{ACTOR}' and created_at>clock_timestamp()-interval '24 hours';")=='100'
    raise 'Roster races changed financial rows' unless query(digest_sql(financial)+';')==financial_before
    result={status:'pass',fixture:PROJECT,migration_count:MIGRATION_COUNT,worker_sessions:2,provider_calls:0,hosted_auth_requests:0,scenarios:observed,transfer_acknowledgements:acks,financial_rows_unchanged:true,source_sha256:Digest::SHA256.file(__FILE__).hexdigest,migration_sha256:MIGRATION_SHA,authority_migration_sha256:AUTHORITY_SHA}
  rescue StandardError=>e
    failure=e
  ensure
    begin
      workers.each { |w|w[:input].close unless w[:input].closed? }
      workers.each do |w|
        begin Timeout.timeout(5) { w[:thread].value };rescue Timeout::Error
          raise 'Cannot terminate unidentified worker' unless w[:pid]
          query("select pg_terminate_backend(pid) from pg_stat_activity where pid=#{w[:pid]} and application_name='#{w[:name]}';")
          Timeout.timeout(5) { w[:thread].value }
        end
        w[:output].read.lines.grep(/^XID:/).each { |line|track_xid(line.strip.delete_prefix('XID:')) }
        error=w[:error].read
        raise "Worker failed: #{error}" unless w[:thread].value.success? || failure
      end
      raise 'Workers remain; cleanup denied' unless query("select count(*) from pg_stat_activity where application_name in ('#{WORKER_A}','#{WORKER_B}');")=='0'
      if seeded
        raise 'Catalog controls drifted; cleanup denied' unless snapshot_tables==tables && query(controls_sql+';')==controls
        attribution=JSON.parse(query(owned_xids_sql+';'));owned_xids=attribution.map { |v|v.fetch('xmin') }
        xids=(TRACKED_XIDS+owned_xids).uniq
        raise 'Unverified transaction attribution' unless !xids.empty? && xids.all? { |x|x.match?(/\A[0-9]+\z/) }
        CHECKPOINT.merge!('phase'=>'cleanup_ready','owned_row_xid_attribution'=>attribution,'scenario_result'=>result,'primary_failure'=>failure && "#{failure.class}: #{failure.message}");save_checkpoint
        query(cleanup_sql(tables:tables,before:before,controls:controls,flag:flag,permission_rows:permissions,xids:xids,trigger_guard:trigger_guard,fingerprints:fingerprints,governance_heads:governance_heads,baseline_event_ids:baseline_event_ids),transaction:true)
        after=query(digest_sql(tables)+';');controls_after=query(controls_sql+';')
        raise 'Post-cleanup full baseline mismatch' unless after==before && controls_after==controls
        result&.merge!(baseline_tables:tables,baseline_table_count:tables.length,baseline_sha256_before:before,baseline_sha256_after:after,controls_sha256_before:controls,controls_sha256_after:controls_after,synthetic_graph_removed:true,worker_sessions_remaining:0,qa_only_temporarily_disabled_triggers:CLEANUP_GUARDS,captured_transaction_ids:xids,owned_row_xid_attribution:attribution,checkpoint_path:CHECKPOINT_PATH,sequence_counters_restored:false,sequence_note:'PostgreSQL nextval counters are not rolled back or reset.')
        CHECKPOINT.merge!('phase'=>'restored','restoration'=>{baseline_sha256_after:after,controls_sha256_after:controls_after,worker_sessions_remaining:0});save_checkpoint
      end
    rescue StandardError=>e
      cleanup_failure=e;CHECKPOINT.merge!('phase'=>'cleanup_failed','cleanup_error'=>e.message,'primary_failure'=>failure && "#{failure.class}: #{failure.message}");save_checkpoint
    end
  end
  raise "Primary failure: #{failure ? failure.class.to_s+': '+failure.message : 'none; scenarios completed'}\nCleanup failed: #{cleanup_failure.message}" if cleanup_failure
  raise failure if failure
  raise 'Reviewed migration sources changed during run' unless Digest::SHA256.file(File.join(ROOT,MIGRATION)).hexdigest==MIGRATION_SHA && Digest::SHA256.file(File.join(ROOT,AUTHORITY_MIGRATION)).hexdigest==AUTHORITY_SHA
  CHECKPOINT.merge!('phase'=>'complete','result'=>result);save_checkpoint
  puts JSON.pretty_generate(result)
end
