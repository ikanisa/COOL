# Synthetic overlapping transactions, scoped to the dedicated platform sandbox.
require 'json'
require 'open3'
require 'time'
DB = 'collect_platform_access_uat_20260902'.freeze
PSQL = %w[docker exec -i supabase_db_collect psql -XqAt -U postgres].concat(
  ['-d', DB, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']).freeze
IDS = (1..4).map { |n| "98300000-0000-4000-8000-#{n.to_s.rjust(12,'0')}" }.freeze
def query(sql)
  out, err, status = Open3.capture3(*PSQL, stdin_data: sql)
  raise err unless status.success?
  out.strip
end
def wait_for(label)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
  loop do
    value = yield
    return value if value
    raise "Timeout: #{label}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.05
  end
end
def claims(n)
  {sub: IDS[n-1], role: 'authenticated', session_id: "98310000-0000-4000-8000-#{n.to_s.rjust(12,'0')}"}.to_json
end
class Connection
  def initialize(name, sql, open: false)
    @name = name
    @input, output, error, @process = Open3.popen3(*PSQL)
    @out = Thread.new { output.read }
    @err = Thread.new { error.read }
    @input.write("set application_name='#{name}'; set statement_timeout='12s';\n#{sql}\n")
    @input.flush
    @input.close unless open
  end
  def pid
    value = query("select pid from pg_stat_activity where datname='#{DB}' and application_name='#{@name}';")
    value.empty? ? nil : Integer(value)
  end
  def release(sql)
    return if @input.closed?
    @input.write(sql + "\n")
    @input.close
  end
  def result
    raise 'Timed out' unless @process.join(15)
    {ok: @process.value.success?, out: @out.value, err: @err.value}
  end
end
def action(n, statement)
  "set local role authenticated; select set_config('request.jwt.claims','#{claims(n)}',true); #{statement}"
end
def approve(n)
  "select public.admin_approve_whatsapp('#{IDS[n-1]}','+25078898300#{n}','Synthetic concurrency approval');"
end
def activate(n, active=true)
  "select public.admin_set_user_access('#{IDS[n-1]}',#{active},'Synthetic concurrency access');"
end
def revoke(n)
  "select public.admin_revoke_whatsapp_approval('#{IDS[n-1]}','Synthetic concurrency revoke');"
end
checks = []
created = false
begin
  raise 'Wrong database' unless query('select current_database();') == DB
  raise 'Fixture namespace occupied' unless query("select not exists(select 1 from auth.users where id in ('#{IDS.join("','")}'));") == 't'
  query(<<~SQL)
    begin;
    insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
    select ('98300000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'authenticated','authenticated',
      '25078898300'||i,now(),'{}','{}' from generate_series(1,4)i;
    insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,reason)
    select id,'+'||phone,'Synthetic existing approved operator' from auth.users where id in ('#{IDS[0]}','#{IDS[1]}');
    insert into public.admin_user_roles(user_id,role_id,reason)
    select u::uuid,r.id,'Synthetic existing role' from public.admin_roles r,unnest(array['#{IDS[0]}','#{IDS[1]}'])u
    where r.name='platform_owner';
    insert into auth.sessions(id,user_id,created_at)
    select ('98310000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      ('98300000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,clock_timestamp() from generate_series(1,4)i;
    commit;
  SQL
  created = true
  scenarios = [
    ['approval_retry',action(1,approve(3)),action(1,approve(3)),nil],
    ['activation_retry',action(1,activate(3)),action(1,activate(3)),nil],
    ['revoked_actor_queued_approval',action(1,revoke(2)),action(2,approve(4)),'P0001'],
    ['revoked_target_queued_activation',action(1,revoke(3)),action(1,activate(3)),'42501']
  ]
  scenarios.each_with_index do |(name,a_sql,b_sql,error_code),index|
    gate = first = second = nil
    lock = 983010 + index
    begin
      gate = Connection.new("platform_#{index}_gate","select pg_advisory_lock(#{lock});",open:true)
      gate_pid = wait_for('gate lock') do
        pid = gate.pid
        pid if pid && query("select exists(select 1 from pg_locks where pid=#{pid} and locktype='advisory' and granted);") == 't'
      end
      first = Connection.new("platform_#{index}_first","begin; #{a_sql} select pg_advisory_xact_lock(#{lock}); commit;")
      first_pid = wait_for('first reaches commit barrier') do
        pid = first.pid
        pid if pid && query("select #{gate_pid}=any(pg_blocking_pids(#{pid}));") == 't'
      end
      second = Connection.new("platform_#{index}_second","begin; #{b_sql} commit;")
      second_pid = wait_for('second genuinely overlaps') do
        pid = second.pid
        pid if pid && query("select #{first_pid}=any(pg_blocking_pids(#{pid}));") == 't'
      end
      gate.release("select pg_advisory_unlock(#{lock});")
      a,b,g = first.result,second.result,gate.result
      raise "First failed: #{a[:err]}" unless a[:ok] && g[:ok]
      raise "Unexpected second result: #{b}" unless error_code ? (!b[:ok] && b[:err].include?(error_code)) : b[:ok]
      checks << {name:name,status:'pass',overlap_verified:true,first_pid:first_pid,blocked_pid:second_pid,rejected_sqlstate:error_code}
    ensure
      gate&.release("select pg_advisory_unlock(#{lock});")
      [first,second,gate].compact.each(&:result)
    end
  end
  raise 'Retry or revocation invariant failed' unless query(<<~SQL) == 't'
    select (select count(*)=1 from public.audit_logs where entity_id='#{IDS[2]}' and action='admin.whatsapp.approved')
      and (select count(*)=1 from public.audit_logs where entity_id='#{IDS[2]}' and action='admin.access.activated')
      and not exists(select 1 from public.admin_user_roles where user_id in ('#{IDS[1]}','#{IDS[2]}') and revoked_at is null)
      and not exists(select 1 from collect_admin_access.whatsapp_approvals where user_id='#{IDS[3]}');
  SQL
  checks << {name:'single audit and no stale authority resurrection',status:'pass'}
ensure
  if created
    query(<<~SQL)
      begin;
      delete from public.audit_logs where entity_id in ('#{IDS.join("','")}');
      delete from auth.users where id in ('#{IDS.join("','")}') and phone in ('250788983001','250788983002','250788983003','250788983004');
      commit;
    SQL
    raise 'Cleanup failed' unless query("select not exists(select 1 from auth.users where id in ('#{IDS.join("','")}'));") == 't'
    checks << {name:'exact synthetic accounts removed',status:'pass'}
  end
end
puts JSON.pretty_generate(captured_at:Time.now.utc.iso8601,database:DB,checks:checks)
