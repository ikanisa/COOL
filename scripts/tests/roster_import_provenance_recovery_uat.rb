require_relative 'roster_import_provenance_concurrency_uat'

# Root-only recovery of the failed, fully backed-up first9954 concurrency run.
# Default trace mode restores only inside a rolled-back transaction. Apply must
# pin that trace's digest and unchanged pre-recovery data/control fingerprints.
BACKUP_PATH = File.join(ROOT,'.cache/roster-provenance-20260930/pre-concurrency142.dump')
BACKUP_SHA = '500e66e7de0c0720aa8107b41b9c95444676411cf5fe2fe2711f667439732ed2'
FAILED_SOURCE_SHA = 'c2c49f80caefc1df06ff557d9ded0378b7f006cc1e62a8d1e4b1a225885b606c'

raise 'Exact recovery authorization required' unless ENV['COLLECT_ROSTER_RECOVERY_QA']=='failed_9954_run'
raise 'Do not share concurrency checkpoint with recovery' if CHECKPOINT_PATH
apply=ARGV[0]=='--apply'
raise 'Use --trace OUTPUT.json or --apply TRACE.json SHA256' unless
  (!apply && ARGV.length==2 && ARGV[0]=='--trace') || (apply && ARGV.length==3)
trace_path=File.expand_path(ARGV[1])
raise 'Recovery trace must be new' if !apply && File.exist?(trace_path)
raise 'Authoritative failed-run backup changed' unless Digest::SHA256.file(BACKUP_PATH).hexdigest==BACKUP_SHA
raise 'Frozen142 changed' unless Digest::SHA256.file(File.join(ROOT,MIGRATION)).hexdigest==MIGRATION_SHA
failed_source=File.join(ROOT,'docs/release/roster-import-provenance-2026-09-30/sources/concurrency-attempt1-c2c49f80.rb')
raise 'Failed source evidence changed' unless Digest::SHA256.file(failed_source).hexdigest==FAILED_SOURCE_SHA
reviewed=nil
if apply
  raise 'Exact reviewed trace digest required' unless ARGV[2].match?(/\A[0-9a-f]{64}\z/) && Digest::SHA256.file(trace_path).hexdigest==ARGV[2]
  reviewed=JSON.parse(File.read(trace_path))
  raise 'Trace is not a successful rollback rehearsal for this source/backup' unless reviewed['status']=='rollback_rehearsal_pass' &&
    reviewed['backup_sha256']==BACKUP_SHA && reviewed['recovery_source_sha256']==Digest::SHA256.file(__FILE__).hexdigest &&
    reviewed['harness_source_sha256']==Digest::SHA256.file(File.join(__dir__,'roster_import_provenance_concurrency_uat.rb')).hexdigest
end
raw,err,status=Open3.capture3('docker','inspect',CONTAINER)
raise err unless status.success?
container=JSON.parse(raw).fetch(0);labels=container.fetch('Config').fetch('Labels')
ports=container.fetch('HostConfig').fetch('PortBindings').fetch('5432/tcp')
config=File.read(File.join(ROOT,'.cache/financial-concurrency-20260929/supabase/config.toml'))
db=config[/^\[db\]\s*\n(.*?)(?=^\[|\z)/m,1]
raise 'Exact task142/55722 fixture required' unless container.dig('State','Running') &&
  labels['com.supabase.cli.project']==PROJECT && labels['com.docker.compose.project']==PROJECT &&
  config.match?(/^project_id = "#{PROJECT}"$/) && db&.match?(/^port = 55722$/) && !ports.empty? && ports.all? { |p| p['HostPort']=='55722' }

# pg_restore is solely an archive decoder. No --dbname/connection or restored
# commands are executed; only known COPY payloads become temporary baseline rows.
decoded,error,status=Open3.capture3('docker','exec','-i',CONTAINER,'pg_restore','--data-only','--file=-',stdin_data:File.binread(BACKUP_PATH))
raise error unless status.success?
allowed_schemas=SCHEMAS.delete("'").split(',')
blocks={}; lines=decoded.lines; i=0
while i<lines.length
  line=lines[i];i+=1
  next unless line.start_with?('COPY ')
  m=/\ACOPY ([a-z_][a-z_0-9]*)\.([a-z_][a-z_0-9]*) \(([a-z_0-9", ]+)\) FROM stdin;\n\z/.match(line)
  raise 'Unrecognized backup COPY header' unless m
  relation="#{m[1]}.#{m[2]}"; columns=m[3].split(', ').map { |v| v.delete('"') }
  raise 'Unsafe backup column identifier' unless columns.all? { |v| v.match?(/\A[a-z_][a-z_0-9]*\z/) }
  payload=[]
  while i<lines.length && lines[i]!="\\.\n"
    payload << lines[i];i+=1
  end
  raise 'Unterminated COPY payload' unless i<lines.length
  i+=1
  next unless allowed_schemas.include?(m[1])
  raise 'Duplicate archive table' if blocks.key?(relation)
  blocks[relation]={columns:columns,payload:payload.join}
end
raise 'Unexpected backup table set' unless blocks.length==131 && blocks.keys.include?('supabase_migrations.schema_migrations') && blocks.keys.include?('public.app_realtime_events')
tables=snapshot_tables
raise 'Current table catalog differs from authoritative backup' unless tables==blocks.keys.sort
# Supabase grants postgres SELECT only on the Auth service migration registry.
# Preserve that registry under an ACCESS SHARE lock and full digest comparison;
# every other selected table retains the original ACCESS EXCLUSIVE protection.
read_only_registry='auth.schema_migrations'
raise 'Expected Auth registry missing' unless tables.include?(read_only_registry)
before=query(digest_sql(tables)+';');controls=query(controls_sql+';')
if apply
  raise 'Fixture data/control changed since reviewed rehearsal' unless before==reviewed['before_sha256'] && controls==reviewed['controls_sha256']
end
expected_map=tables.each_with_index.to_h { |t,n| [t,"pg_temp.roster_recovery_baseline_#{n}"] }
load_baseline=tables.map do |t|
  b=blocks.fetch(t);temp=expected_map.fetch(t)
  "create temp table #{temp.split('.').last} (like #{t} including generated) on commit drop;\nCOPY #{temp} (#{b[:columns].map { |c| '"'+c+'"' }.join(',')}) FROM stdin;\n#{b[:payload]}\\.\n"
end.join
expected_rows=expected_map.map { |real,temp| "select '#{real}'::text family,to_jsonb(t) body from #{temp} t" }.join(' union all ')
expected_digest="with rows as (#{expected_rows}) select encode(extensions.digest(coalesce(string_agg(family||':'||body::text,E'\\n' order by family,body::text),''),'sha256'),'hex') from rows"
expected_fingerprints=expected_map.map do |real,temp|
  "select '#{real}' relation,count(*) row_count,encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by to_jsonb(t)::text),''),'sha256'),'hex') sha256 from #{temp} t"
end.join(' union all ')
expected_fingerprints="select jsonb_object_agg(relation,jsonb_build_object('rows',row_count,'sha256',sha256)) from (#{expected_fingerprints}) f"
trigger_guard=<<~SQL
  do $$ declare x record; begin
    for x in select * from (values #{IMMUTABLE.map { |t,n| "('#{t}'::regclass,'#{n}')" }.join(',')}) e(relation,name) loop
      if (select count(*) from pg_trigger where tgrelid=x.relation and tgname=x.name and not tgisinternal and tgenabled='O')<>1
        or exists(select 1 from pg_trigger where tgrelid=x.relation and not tgisinternal and (tgtype::int & 2)=2 and (tgtype::int & 8)=8 and tgname<>x.name)
        then raise exception 'Unexpected provenance guard'; end if;
    end loop;
  end $$;
SQL
flag_sql="(select to_jsonb(f) from #{expected_map.fetch('public.feature_flags')} f where key='hybrid_member_onboarding')"
cleanup=cleanup_sql(tables:tables,before_sql:expected_digest,controls_before:controls,flag_sql:flag_sql,
  xids_sql:"select body->>'xmin' from roster_recovery_attribution",trigger_guard:trigger_guard,residual_baseline_sql:expected_fingerprints)
body=<<~SQL
  begin;
  set local lock_timeout='5s';
  select pg_advisory_xact_lock(193517,141);
  lock table #{read_only_registry} in access share mode;
  lock table #{(tables-[read_only_registry]).join(',')} in access exclusive mode;
  do $$ begin
    if current_database()<>'postgres' or current_user<>'postgres' or current_setting('cron.launch_active_jobs')<>'off'
      or current_setting('pg_net.batch_size')<>'0' or (select count(*) from supabase_migrations.schema_migrations)<>142
      or (select max(version) from supabase_migrations.schema_migrations)<>'20260930100000'
      or (select count(*) from auth.users where id in ('#{ACTOR}','#{CONTROLLER}'))<>2
      or (select count(*) from collect_hybrid.roster_import_sources where actor_id='#{ACTOR}')<>8
      or (select count(*) from collect_hybrid.roster_import_commits where actor_id='#{ACTOR}')<>5
      or exists(select 1 from auth.users where id::text like '#{PREFIX}-%' and id not in ('#{ACTOR}','#{CONTROLLER}'))
      or exists(select 1 from public.notification_device_tokens) or exists(select 1 from public.notification_deliveries)
      or exists(select 1 from pg_stat_activity where pid<>pg_backend_pid() and backend_type='client backend' and state<>'idle')
      or (#{digest_sql(tables)})<>#{lit(before)} or (#{controls_sql.strip})<>#{lit(controls)} then
      raise exception 'Quiet exact failed9954 graph required; refuse stale or changed fixture'; end if;
  end $$;
  #{load_baseline}
  create temp table roster_recovery_attribution on commit drop as
    select value body from jsonb_array_elements((#{owned_xids_sql}));
  -- This failed run emitted no retained top-XID checkpoint. Every removed event
  -- must therefore match a transaction independently evidenced by a surviving
  -- owned row. Unmatched events are reported and prevent cleanup entirely.
  do $$ begin
    if exists(select 1 from public.app_realtime_events e
      left join #{expected_map.fetch('public.app_realtime_events')} old on old.id=e.id
      where old.id is null and not exists(select 1 from roster_recovery_attribution a where a.body->>'xmin'=e.xmin::text)) then
      raise notice 'UNATTRIBUTED_EVENTS:%', (select jsonb_agg(jsonb_build_object('row',to_jsonb(e),'xmin',e.xmin::text))
        from public.app_realtime_events e left join #{expected_map.fetch('public.app_realtime_events')} old on old.id=e.id
        where old.id is null and not exists(select 1 from roster_recovery_attribution a where a.body->>'xmin'=e.xmin::text));
      raise exception 'Unattributed telemetry: recovery requires independent evidence'; end if;
  end $$;
  select 'RECOVERY_ATTRIBUTION:'||(select jsonb_agg(body order by body::text) from roster_recovery_attribution)::text;
  select 'RECOVERY_BASELINE:'||(#{expected_fingerprints})::text;
  #{cleanup}
  select 'RECOVERY_RESTORED:'||(#{expected_digest});
  #{apply ? 'commit' : 'rollback'};
SQL
output=query(body)
marker=lambda { |prefix| output.lines.find { |line| line.start_with?(prefix) }&.strip&.delete_prefix(prefix) }
after=query(digest_sql(tables)+';');controls_after=query(controls_sql+';')
restored=marker.call('RECOVERY_RESTORED:')
raise 'Missing restoration proof' unless restored && restored.match?(/\A[0-9a-f]{64}\z/) && controls_after==controls
raise 'Unexpected final recovery state' unless after==(apply ? restored : before)
report={status:apply ? 'recovery_applied' : 'rollback_rehearsal_pass',fixture:PROJECT,host_port:55722,
  backup_sha256:BACKUP_SHA,failed_source_sha256:FAILED_SOURCE_SHA,migration_sha256:MIGRATION_SHA,
  recovery_source_sha256:Digest::SHA256.file(__FILE__).hexdigest,
  harness_source_sha256:Digest::SHA256.file(File.join(__dir__,'roster_import_provenance_concurrency_uat.rb')).hexdigest,
  before_sha256:before,after_sha256:after,restored_baseline_sha256:restored,controls_sha256:controls,
  baseline_fingerprints:JSON.parse(marker.call('RECOVERY_BASELINE:')),
  attributed_owned_rows:JSON.parse(marker.call('RECOVERY_ATTRIBUTION:')),
  provider_calls:0,hosted_auth_requests:0,sequence_counters_restored:false}
if !apply
  File.open(trace_path,File::WRONLY|File::CREAT|File::EXCL,0600) { |f| f.write(JSON.pretty_generate(report)+"\n");f.flush;f.fsync }
end
puts JSON.pretty_generate(report)
