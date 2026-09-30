require 'open3'
require 'json'
require 'digest'
require 'timeout'

# Source-only until root supplies the exact fixture, source hash and checkpoint.
# No provider request is made. Committed synthetic rows are restored at the end.
ROOT = File.expand_path('../..', __dir__)
PROJECT = 'collect_fin_concurrency_qa_20260929'
CONTAINER = "supabase_db_#{PROJECT}"
MIGRATION = 'supabase/migrations/20260930130000_signed_otp_uncertain_recovery.sql'
PREFIX = 'qa_otp_race_20260930_'
WORKERS = %w[collect_otp145_a collect_otp145_b].freeze
PSQL = ['docker','exec','-i',CONTAINER,'psql','-XqAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'].freeze
SCHEMAS = %w[public private collect_hybrid collect_security collect_admin_access collect_auth_security collect_member_actions collect_profile_access auth realtime supabase_migrations].freeze
BODY_HASH = Digest::SHA256.hexdigest('synthetic OTP race body; no real OTP or phone')
PHONES = (1..8).map { |n| Digest::SHA256.hexdigest("synthetic-otp-race-phone-#{n}") }.freeze
CHECKPOINT = { 'fixture'=>PROJECT, 'source_only_until_guarded_execution'=>true, 'cases'=>[] }

def lit(value)
 value.nil? ? 'null' : "'#{value.to_s.gsub("'","''")}'"
end
def checkpoint
 path=ENV.fetch('COLLECT_OTP_CHECKPOINT')
 temp=path+'.tmp'
 File.open(temp,File::WRONLY|File::CREAT|File::TRUNC,0600) { |f|f.write(JSON.pretty_generate(CHECKPOINT)+"\n");f.flush;f.fsync }
 File.rename(temp,path)
end
def sql(query)
 output,error,status=Open3.capture3(*PSQL,stdin_data:"set application_name='collect_otp145_control';set statement_timeout='30s';set lock_timeout='20s';set timezone='UTC';\n#{query}")
 raise(error.empty? ? output : error) unless status.success?
 output.strip
end
def service
 "set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
end
def reserve(n,phone=n)
 "public.reserve_signed_otp_v3(#{lit(PREFIX+n.to_s)},#{lit(BODY_HASH)},#{lit(PHONES.fetch(phone-1))})"
end
def result(output)
 line=output.lines.find{|l|l.start_with?('RESULT:')}
 raise 'Missing durable OTP result' unless line
 JSON.parse(line.delete_prefix('RESULT:'))
end
def invoke(call)
 result(sql("begin;#{service}select 'RESULT:'||(#{call})::text;commit;"))
end
def begin_call(r)
 "public.begin_signed_otp_v3(#{lit(r.fetch('hook_id'))},#{lit(BODY_HASH)},#{lit(r.fetch('attempt_id'))}::uuid,#{r.fetch('revision')})"
end
def record_call(r,outcome)
 ph=outcome=='accepted' ? Digest::SHA256.hexdigest('synthetic-provider-message') : nil
 "public.record_signed_otp_v3(#{lit(r.fetch('hook_id'))},#{lit(BODY_HASH)},#{lit(r.fetch('attempt_id'))}::uuid,#{r.fetch('revision')},#{lit(outcome)},#{lit(ph)},#{lit(Digest::SHA256.hexdigest("synthetic-#{outcome}-evidence"))})"
end
def recover_call(r,outcome)
 evidence={hook_id:r.fetch('hook_id'),payload_hash:BODY_HASH,attempt_id:r.fetch('attempt_id'),outcome:outcome,
 provider_message_hash:Digest::SHA256.hexdigest('synthetic-provider-message'),observed_at:Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),source:'operator_verified_provider_status'}.to_json
 "public.recover_signed_otp_v3(#{lit(r.fetch('hook_id'))},#{lit(BODY_HASH)},#{lit(r.fetch('attempt_id'))}::uuid,#{r.fetch('revision')},#{lit(evidence)},#{lit(Digest::SHA256.hexdigest(evidence))})"
end
class Worker
 attr_reader :name,:pid,:errors
 def initialize(name,isolation='read committed')
  @name=name
  @input,@output,@error,@wait=Open3.popen3(*PSQL);@input.sync=true;@errors=''
  @errthread=Thread.new{@errors=@error.read}
  @input.puts('\\set VERBOSITY verbose')
  send("set application_name='#{name}';set statement_timeout='30s';set lock_timeout='20s';set timezone='UTC';begin isolation level #{isolation};#{service}select 'PID:'||pg_backend_pid();")
  @pid=Integer(read('PID:').delete_prefix('PID:'))
 end
 def send(query);@input.puts(query);end
 def read(prefix)
  Timeout.timeout(35) do
   loop do
    line=@output.gets
    raise "Worker terminated: #{@errors}" unless line
    return line.strip if line.start_with?(prefix)
   end
  end
 end
 def call(query);send("select 'RESULT:'||(#{query})::text;");end
 def commit;send("commit;select 'COMMITTED';");read('COMMITTED');end
 def finish
  @input.close unless @input.closed?;@output.read;@wait.value;@errthread.join
  {status:@wait.value.exitstatus,errors:@errors}
 end
 def terminate
  send('rollback;') rescue nil
  @input.close rescue nil
  @wait.value
 end
end
def blocked(worker,blocker)
 Timeout.timeout(15) do
  loop do
   count=sql("select count(*) from pg_stat_activity where pid=#{worker.pid} and wait_event_type='Lock' and #{blocker.pid}=any(pg_blocking_pids(pid));")
   return true if count=='1'
   sleep 0.02
  end
 end
end
def race(label,call_a,call_b,expected_b:'result')
 a=Worker.new(WORKERS[0]);b=Worker.new(WORKERS[1])
 begin
  a.call(call_a);ra=result(a.read('RESULT:'))
  b.call(call_b);blocked(b,a)
  a.commit
  if expected_b=='40001'
   rb=nil;status_b=b.finish
   raise 'Losing request did not fail closed with serialization conflict' unless status_b[:status]!=0 && status_b[:errors].include?('40001:') && (status_b[:errors].include?('OTP completion conflict') || status_b[:errors].include?('OTP recovery conflict'))
  else
   rb=result(b.read('RESULT:'));b.commit;status_b=b.finish
   raise 'Losing worker execution failed unexpectedly' unless status_b[:status]==0
  end
  status_a=a.finish;raise 'Winning worker failed' unless status_a[:status]==0
  entry={label:label,actual_blocking_observed:true,winner:ra,loser:rb,loser_exit:status_b[:status]}
  CHECKPOINT['cases']<<entry;checkpoint
  [ra,rb]
 ensure
  a.terminate rescue nil;b.terminate rescue nil
 end
end

def tables
 JSON.parse(sql("select json_agg(format('%I.%I',n.nspname,c.relname) order by n.nspname,c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in ('r','p') and n.nspname in (#{SCHEMAS.map{|s|lit(s)}.join(',')});"))
end
def fingerprint_sql(list)
 rows=list.map { |t| "select '#{t}' relation,count(*) row_count,encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by to_jsonb(t)::text),''),'sha256'),'hex') sha256 from #{t} t" }.join(' union all ')
 "select jsonb_object_agg(relation,jsonb_build_object('rows',row_count,'sha256',sha256)) from (#{rows}) f"
end
def fingerprints(list)
 JSON.parse(sql(fingerprint_sql(list)))
end

unless ARGV==['--execute-local145'] && ENV['COLLECT_OTP_MIGRATION_SHA']==Digest::SHA256.file(File.join(ROOT,MIGRATION)).hexdigest && ENV['COLLECT_OTP_CHECKPOINT']
 abort 'SOURCE_ONLY: exact --execute-local145, pinned COLLECT_OTP_MIGRATION_SHA and new COLLECT_OTP_CHECKPOINT required'
end
abort 'Checkpoint already exists' if File.exist?(ENV.fetch('COLLECT_OTP_CHECKPOINT'))
metadata,error,status=Open3.capture3('docker','inspect',CONTAINER)
abort "Exact container unavailable: #{error}" unless status.success?
container=JSON.parse(metadata).fetch(0);labels=container.fetch('Config').fetch('Labels')
config=File.read(File.join(ROOT,'.cache/financial-concurrency-20260929/supabase/config.toml'))
abort 'Fixture project binding mismatch' unless labels['com.supabase.cli.project']==PROJECT && labels['com.docker.compose.project']==PROJECT && config.match?(/^project_id = "#{PROJECT}"$/) && config.match?(/^port = 55722$/)
guard=sql("select current_database()='postgres' and current_setting('port')::integer=5432 and current_user='postgres' and current_setting('cron.launch_active_jobs')='off' and current_setting('pg_net.batch_size')='0' and (select count(*) from supabase_migrations.schema_migrations)=145 and (select max(version) from supabase_migrations.schema_migrations)='20260930130000' and not exists(select 1 from collect_security.signed_otp_requests where hook_id like '#{PREFIX}%') and not exists(select 1 from public.otp_rate_limits where phone_hash in (#{PHONES.map{|p|lit(p)}.join(',')})) and not exists(select 1 from collect_auth_security.otp_phone_locks where phone_hash in (#{PHONES.map{|p|lit(p)}.join(',')})) and not exists(select 1 from pg_stat_activity where application_name in (#{WORKERS.map{|v|lit(v)}.join(',')}));")
abort 'Database fixture/source/namespace guard failed' unless guard=='t'
list=tables;before=fingerprints(list)
policy=JSON.parse(sql("select coalesce(json_agg(p),'[]'::json) from collect_security.otp_policy p;"))
CHECKPOINT.merge!('source_only_until_guarded_execution'=>false,'source_sha256'=>ENV.fetch('COLLECT_OTP_MIGRATION_SHA'),'tables'=>list,'baseline'=>before,'policy_before'=>policy,'synthetic_phone_hashes'=>PHONES)
checkpoint
# Configure a working local-only policy. Existing private configuration is restored.
sql("begin;insert into collect_security.otp_policy(singleton,global_hourly_limit,global_daily_limit,enabled) values(true,100000,1000000,true) on conflict(singleton) do update set global_hourly_limit=100000,global_daily_limit=1000000,enabled=true;commit;")

r1,r2=race('same hook concurrent reservation',reserve(1),reserve(1))
raise 'Duplicate hook admitted different attempts' unless r1==r2
s1,s2=race('same generation concurrent begin',begin_call(r1),begin_call(r1))
raise 'Two workers claimed provider send' unless s1.fetch('started')==true && s2.fetch('started')==false
race('accepted completion wins over concurrent ambiguous completion',record_call(s1,'accepted'),record_call(s1,'ambiguous'),expected_b:'40001')
accepted=invoke("public.read_signed_otp_v3(#{lit(r1.fetch('hook_id'))},#{lit(BODY_HASH)},#{lit(r1.fetch('attempt_id'))}::uuid)")
race('delivered recovery wins over contradictory concurrent failed recovery',recover_call(accepted,'delivered'),recover_call(accepted,'failed'),expected_b:'40001')
current=invoke("public.read_signed_otp_v3(#{lit(r1.fetch('hook_id'))},#{lit(BODY_HASH)},#{lit(r1.fetch('attempt_id'))}::uuid)")
raise 'Concurrent failure overwrote proved delivered result' unless current.fetch('state')=='delivered'
# Exactly one remaining global slot, separate synthetic phones.
sql("begin;update collect_security.otp_policy set global_hourly_limit=(select count(*)+1 from collect_security.signed_otp_requests where requested_at>=clock_timestamp()-interval '1 hour');commit;")
a,b=race('global quota concurrent final slot',reserve(2),reserve(3))
raise 'Global slot admitted multiple hooks' unless a.is_a?(Hash) && b=='throttled'
# Repeatable-read snapshot taken before the winning policy mutation must abort.
sql("begin;update collect_security.otp_policy set global_hourly_limit=100000;commit;")
a=Worker.new(WORKERS[0]);b=Worker.new(WORKERS[1],'repeatable read')
begin
 b.send("select 'SNAPSHOT:'||count(*) from pg_catalog.pg_class;");b.read('SNAPSHOT:')
 a.call(reserve(4));result(a.read('RESULT:'));b.call(reserve(5));blocked(b,a);a.commit
 failed=b.finish;raise 'Stale repeatable-read quota decision was admitted' unless failed[:status]!=0 && failed[:errors].include?('40001:') && failed[:errors].include?('could not serialize access')
 raise 'Winning worker failed' unless a.finish[:status]==0
 CHECKPOINT['cases']<<{label:'stale repeatable-read quota snapshot',actual_blocking_observed:true,loser_exit:failed[:status],serialization_failure:true};checkpoint
ensure
 a.terminate rescue nil;b.terminate rescue nil
end

# Capture every owned row and its XID before controlled restoration. No XID range
# or unrelated audit/financial row is deleted. Root must retain its pre-run backup.
owned=JSON.parse(sql("select jsonb_build_object('requests',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('xmin',r.xmin::text)),'[]') from collect_security.signed_otp_requests r where hook_id like '#{PREFIX}%'),'evidence',(select coalesce(jsonb_agg(to_jsonb(e)||jsonb_build_object('xmin',e.xmin::text)),'[]') from collect_security.signed_otp_evidence e where hook_id like '#{PREFIX}%'),'counters',(select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('xmin',c.xmin::text)),'[]') from public.otp_rate_limits c where phone_hash in (#{PHONES.map{|p|lit(p)}.join(',')})));") )
CHECKPOINT['owned_before_cleanup']=owned;checkpoint
raise 'Unexpected owned hook admitted' unless owned.fetch('requests').map{|r|r.fetch('hook_id')}.sort==[1,2,4].map{|n|PREFIX+n.to_s}
raise 'Unexpected phone reservation count' unless owned.fetch('counters').length==3
raise 'Owned rows have altered identity' unless owned.fetch('requests').all?{|r|r.fetch('payload_hash')==BODY_HASH && PHONES.include?(r.fetch('phone_hash'))}
raise 'Worker connection remains live before cleanup' unless sql("select count(*) from pg_stat_activity where application_name in (#{WORKERS.map{|v|lit(v)}.join(',')});")=='0'
restore_policy=policy.empty? ? 'delete from collect_security.otp_policy;' : "update collect_security.otp_policy set global_hourly_limit=#{policy[0].fetch('global_hourly_limit')},global_daily_limit=#{policy[0].fetch('global_daily_limit')},enabled=#{policy[0].fetch('enabled')};"
sql("begin;lock table collect_security.otp_policy,collect_security.signed_otp_requests,collect_security.signed_otp_evidence,public.otp_rate_limits,collect_auth_security.otp_phone_locks in access exclusive mode;do $$ begin if (select count(*) from collect_security.otp_policy where singleton and enabled and global_hourly_limit=100000 and global_daily_limit=1000000)<>1 then raise exception 'OTP local policy changed before restoration';end if;end $$;alter table collect_security.signed_otp_evidence disable trigger signed_otp_evidence_immutable;delete from collect_security.signed_otp_evidence where hook_id like '#{PREFIX}%';alter table collect_security.signed_otp_evidence enable trigger signed_otp_evidence_immutable;delete from collect_security.signed_otp_requests where hook_id like '#{PREFIX}%';delete from public.otp_rate_limits where phone_hash in (#{PHONES.map{|p|lit(p)}.join(',')});delete from collect_auth_security.otp_phone_locks where phone_hash in (#{PHONES.map{|p|lit(p)}.join(',')});#{restore_policy}do $$ begin if (#{fingerprint_sql(list)}) is distinct from #{lit(before.to_json)}::jsonb then raise exception 'Authoritative table fingerprints not restored';end if;end $$;commit;")
after=fingerprints(list);CHECKPOINT['baseline_restored']=after==before;CHECKPOINT['after']=after;checkpoint
raise 'Authoritative application table baselines changed' unless after==before
raise 'Worker connection remains live' unless sql("select count(*) from pg_stat_activity where application_name in (#{WORKERS.map{|v|lit(v)}.join(',')});")=='0'
puts JSON.pretty_generate({pass:true,fixture:PROJECT,source_sha256:ENV.fetch('COLLECT_OTP_MIGRATION_SHA'),cases:CHECKPOINT.fetch('cases'),table_fingerprints_restored:list.length,provider_requests:0,sequences_restored:false,checkpoint_sha256:Digest::SHA256.file(ENV.fetch('COLLECT_OTP_CHECKPOINT')).hexdigest})
