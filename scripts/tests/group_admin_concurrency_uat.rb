# Fixture-only overlapping transactions; no production defaults or credentials.
require 'json'
require 'open3'
require 'time'

DB = 'collect_uat_20260902'.freeze
PSQL = %w[docker exec -i supabase_db_collect psql -XqAt -U postgres].concat(
  ['-d', DB, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
).freeze
OWNER = '98100000-0000-4000-8000-000000000001'.freeze
TARGET = '98100000-0000-4000-8000-000000000002'.freeze
OTHER = '98100000-0000-4000-8000-000000000003'.freeze
GROUPS = (10..13).map { |n| "98100000-0000-4000-8000-#{n.to_s.rjust(12, '0')}" }.freeze

def query(sql)
  out, err, status = Open3.capture3(*PSQL, stdin_data: sql)
  raise "Local database check failed: #{err}" unless status.success?
  out.strip
end

def await_value(message)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
  loop do
    value = yield
    return value if value
    raise "Timed out: #{message}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.05
  end
end

class Connection
  def initialize(name, sql, keep_open: false)
    @name = name
    @input, output, error, @process = Open3.popen3(*PSQL)
    @out = Thread.new { output.read }
    @err = Thread.new { error.read }
    @input.write("set application_name='#{name}'; set statement_timeout='12s';\n#{sql}\n")
    @input.flush
    @input.close unless keep_open
  end

  def pid
    value = query("select pid from pg_stat_activity where datname='#{DB}' and application_name='#{@name}';")
    value.empty? ? nil : Integer(value)
  end

  def release(sql = '')
    return if @input.closed?
    @input.write(sql + "\n")
    @input.close
  end

  def result
    raise 'Local concurrency process timed out' unless @process.join(15)
    {success: @process.value.success?, stdout: @out.value, stderr: @err.value}
  end
end

checks = []
created = false
begin
  raise 'Wrong database' unless query('select current_database();') == DB
  raise 'Synthetic namespace occupied' unless query(<<~SQL) == 't'
    select not exists(select 1 from auth.users where id in ('#{OWNER}','#{TARGET}','#{OTHER}'))
      and not exists(select 1 from public.collections where id in ('#{GROUPS.join("','")}'));
  SQL
  query(<<~SQL)
    begin;
    insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
    select ('98100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
      'authenticated','authenticated','25078898100'||n,now(),'{}','{}' from generate_series(1,3)n;
    update public.profiles set public_id='98100'||right(id::text,1) where id in ('#{OWNER}','#{TARGET}','#{OTHER}');
    insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type)
    select g::uuid,'synthetic-admin-race-'||g,'#{OWNER}','Synthetic admin race','Other','private','private','other'
      from unnest(array['#{GROUPS.join("','")}'])g;
    insert into public.collection_members(collection_id,user_id,role,status)
    select g::uuid,u::uuid,case when u='#{OWNER}' then 'owner' else 'member' end::public.member_role,'active'
      from unnest(array['#{GROUPS.join("','")}'])g cross join unnest(array['#{OWNER}','#{TARGET}','#{OTHER}'])u;
    commit;
  SQL
  created = true
  GROUPS.each_with_index do |group, index|
    lock = 981010 + index
    label = %w[add_vs_retry transfer_vs_add archive_vs_add removal_vs_add][index]
    first_statement = [
      "select public.add_group_admin('#{group}','981002');",
      "select public.transfer_group_ownership('#{group}','981003');",
      "select public.archive_group('#{group}');",
      # Models a privileged membership removal already in flight. All member
      # rows are locked/rechecked by add_group_admin, so no revival is possible.
      "update public.collection_members set status='removed' where collection_id='#{group}' and user_id='#{TARGET}';"
    ][index]
    expected_error = [nil, '42501', '22023', '22023'][index]
    gate = first = second = nil
    begin
      gate = Connection.new("admin_race_#{index}_gate", "select pg_advisory_lock(#{lock});", keep_open: true)
      gate_pid = await_value('gate') do
        pid = gate.pid
        pid if pid && query("select exists(select 1 from pg_locks where pid=#{pid} and locktype='advisory' and granted);") == 't'
      end
      claims = {sub: OWNER, role: 'authenticated'}.to_json
      first = Connection.new("admin_race_#{index}_first", <<~SQL)
        begin;
        #{index == 3 ? '' : 'set local role authenticated;'}
        select set_config('request.jwt.claims','#{claims}',true);
        #{first_statement}
        select pg_advisory_xact_lock(#{lock});
        commit;
      SQL
      first_pid = await_value('first action reached commit gate') do
        pid = first.pid
        pid if pid && query("select #{gate_pid}=any(pg_blocking_pids(#{pid}));") == 't'
      end
      second = Connection.new("admin_race_#{index}_second", <<~SQL)
        begin; set local role authenticated;
        select set_config('request.jwt.claims','#{claims}',true);
        select public.add_group_admin('#{group}','981002');
        commit;
      SQL
      second_pid = await_value('second action genuinely overlaps first') do
        pid = second.pid
        pid if pid && query("select #{first_pid}=any(pg_blocking_pids(#{pid}));") == 't'
      end
      gate.release("select pg_advisory_unlock(#{lock});")
      a, b, g = first.result, second.result, gate.result
      raise "First action failed: #{a[:stderr]}" unless a[:success] && g[:success]
      if expected_error
        raise "Conflict was not rejected: #{b}" if b[:success] || !b[:stderr].include?(expected_error)
      else
        raise "Idempotent retry failed: #{b[:stderr]}" unless b[:success]
      end
      raise 'Admin role/audit or platform separation invariant failed' unless query(<<~SQL) == 't'
        select (select count(*)=#{index.zero? ? 1 : 0} from public.collection_members
          where collection_id='#{group}' and user_id='#{TARGET}' and role='admin' and status='active')
        and (select count(*)=#{index.zero? ? 1 : 0} from public.audit_logs
          where entity_id='#{group}' and action='collection.admin_added')
        and not exists(select 1 from public.admin_user_roles where user_id in ('#{OWNER}','#{TARGET}','#{OTHER}'));
      SQL
      checks << {name: label, status: 'pass', overlap_verified: true,
                 first_pid: first_pid, blocked_second_pid: second_pid, rejected_sqlstate: expected_error}
    ensure
      gate&.release("select pg_advisory_unlock(#{lock});")
      [first, second, gate].compact.each(&:result)
    end
  end
ensure
  if created
    query(<<~SQL)
      begin;
      delete from public.audit_logs where entity_id in ('#{GROUPS.join("','")}');
      delete from public.collections where id in ('#{GROUPS.join("','")}') and slug like 'synthetic-admin-race-%';
      delete from auth.users where id in ('#{OWNER}','#{TARGET}','#{OTHER}') and phone in ('250788981001','250788981002','250788981003');
      commit;
    SQL
    raise 'Synthetic cleanup failed' unless query(<<~SQL) == 't'
      select not exists(select 1 from auth.users where id in ('#{OWNER}','#{TARGET}','#{OTHER}'))
        and not exists(select 1 from public.collections where id in ('#{GROUPS.join("','")}'));
    SQL
    checks << {name: 'exact synthetic targets removed', status: 'pass'}
  end
end
puts JSON.pretty_generate(captured_at: Time.now.utc.iso8601, database: DB, checks: checks)
