# Overlapping owner actions against one explicit disposable database only.
# No live credentials, provider traffic, or production database defaults.
require 'json'
require 'open3'
require 'time'

DB = 'collect_uat_20260902'.freeze
PSQL = %w[docker exec -i supabase_db_collect psql -X -qAt -U postgres].concat(
  ['-d', DB, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
).freeze
OWNER = '97000000-0000-4000-8000-000000000001'.freeze
TARGET = '97000000-0000-4000-8000-000000000002'.freeze
OTHER = '97000000-0000-4000-8000-000000000003'.freeze
GROUPS = %w[97000000-0000-4000-8000-000000000010 97000000-0000-4000-8000-000000000011].freeze

def query(sql)
  out, err, status = Open3.capture3(*PSQL, stdin_data: sql)
  raise "Disposable database check failed: #{err}" unless status.success?
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
  attr_reader :name
  def initialize(name, sql, keep_open: false)
    @name = name
    @input, output, error, @process = Open3.popen3(*PSQL)
    @out = Thread.new { output.read }
    @err = Thread.new { error.read }
    @input.write("set application_name='#{name}'; set statement_timeout='12s';\n" + sql + "\n")
    @input.flush
    @input.close unless keep_open
  end

  def pid
    value = query("select pid from pg_stat_activity where datname='#{DB}' and application_name='#{name}';")
    value.empty? ? nil : Integer(value)
  end

  def release(sql = '')
    return if @input.closed?
    @input.write(sql + "\n")
    @input.close
  end

  def result
    raise 'Local concurrency process exceeded timeout' unless @process.join(15)
    {success: @process.value.success?, stdout: @out.value, stderr: @err.value}
  end
end

checks = []
created = false
begin
  raise 'Wrong database' unless query('select current_database();') == DB
  raise 'Synthetic namespace must be empty' unless query(<<~SQL) == 't'
    select not exists(select 1 from auth.users where id in ('#{OWNER}','#{TARGET}','#{OTHER}'))
      and not exists(select 1 from public.collections where id in ('#{GROUPS.join("','")}'));
  SQL
  query(<<~SQL)
    begin;
    insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
    select ('97000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'authenticated','authenticated',
      '25078897000'||n,now(),'{}','{}' from generate_series(1,3)n;
    update public.profiles set public_id='97000'||right(id::text,1)
      where id in ('#{OWNER}','#{TARGET}','#{OTHER}');
    insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type)
    select id::uuid,'synthetic-owner-race-'||n,'#{OWNER}','Synthetic overlapping owner actions','Other','private','private','other'
      from (values ('#{GROUPS[0]}',1),('#{GROUPS[1]}',2))v(id,n);
    insert into public.collection_members(collection_id,user_id,role,status)
    select g::uuid,u::uuid,case when u='#{OWNER}' then 'owner' else 'member' end::public.member_role,'active'
      from unnest(array['#{GROUPS.join("','")}'])g cross join unnest(array['#{OWNER}','#{TARGET}','#{OTHER}'])u;
    insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network,label)
    select g::uuid,'#{OWNER}','0788970001',encode(extensions.digest('+250788970001','sha256'),'hex'),'mtn_momo','Synthetic race route'
      from unnest(array['#{GROUPS.join("','")}'])g;
    commit;
  SQL
  created = true

  GROUPS.each_with_index do |group, index|
    lock = 970010 + index
    label = index.zero? ? 'transfer_vs_transfer' : 'archive_vs_transfer'
    gate = first = second = nil
    begin
      gate = Connection.new("collect_uat_#{label}_gate", "select pg_advisory_lock(#{lock});", keep_open: true)
      gate_pid = await_value('gate acquired') do
        pid = gate.pid
        pid if pid && query("select exists(select 1 from pg_locks where pid=#{pid} and locktype='advisory' and granted);") == 't'
      end
      action = index.zero? ? "public.transfer_group_ownership('#{group}','970002')" : "public.archive_group('#{group}')"
      claims = {sub: OWNER, role: 'authenticated'}.to_json
      first = Connection.new("collect_uat_#{label}_first", <<~SQL)
        begin;
        set local role authenticated;
        select set_config('request.jwt.claims','#{claims}',true);
        select #{action};
        select pg_advisory_xact_lock(#{lock});
        commit;
      SQL
      first_pid = await_value('first action mutated and reached gate') do
        pid = first.pid
        pid if pid && query("select #{gate_pid}=any(pg_blocking_pids(#{pid}));") == 't'
      end
      second = Connection.new("collect_uat_#{label}_second", <<~SQL)
        begin;
        set local role authenticated;
        select set_config('request.jwt.claims','#{claims}',true);
        select public.transfer_group_ownership('#{group}','970003');
        commit;
      SQL
      second_pid = await_value('second action genuinely blocked by first action') do
        pid = second.pid
        pid if pid && query("select #{first_pid}=any(pg_blocking_pids(#{pid}));") == 't'
      end
      gate.release("select pg_advisory_unlock(#{lock});")
      a, b, g = first.result, second.result, gate.result
      expected_error = index.zero? ? '42501' : '22023'
      raise "First action failed: #{a[:stderr]}" unless a[:success] && g[:success]
      raise "Conflict did not fail with #{expected_error}: #{b}" if b[:success] || !b[:stderr].include?(expected_error)
      expected_owner = index.zero? ? TARGET : OWNER
      expected_action = index.zero? ? 'collection.ownership_transferred' : 'collection.archived'
      valid = query(<<~SQL) == 't'
        select (select creator_user_id='#{expected_owner}' and (archived_at is not null)=#{index == 1}
          from public.collections where id='#{group}')
        and (select count(*)=1 from public.collection_members where collection_id='#{group}' and role='owner' and status='active')
        and (select count(*)=1 from public.audit_logs where entity_id='#{group}' and action='#{expected_action}')
        and (select count(*)=1 from public.audit_logs where entity_id='#{group}')
        and exists(select 1 from public.collection_receivers where collection_id='#{group}' and receiver_user_id='#{OWNER}'
          and momo_number='0788970001' and is_active)
        and not exists(select 1 from public.admin_user_roles where user_id in ('#{OWNER}','#{TARGET}','#{OTHER}'));
      SQL
      raise 'Post-race ownership, audit, payment route or privilege invariant failed' unless valid
      checks << {name: label, status: 'pass', actual_overlap_verified: true,
                 first_pid: first_pid, blocked_second_pid: second_pid, rejected_sqlstate: expected_error,
                 one_owner: true, one_audit_event: true, payment_route_unchanged: true, no_platform_privileges: true}
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
      delete from public.collections where id in ('#{GROUPS.join("','")}') and slug in ('synthetic-owner-race-1','synthetic-owner-race-2');
      delete from auth.users where id in ('#{OWNER}','#{TARGET}','#{OTHER}') and phone in ('250788970001','250788970002','250788970003');
      commit;
    SQL
    clean = query("select not exists(select 1 from auth.users where id in ('#{OWNER}','#{TARGET}','#{OTHER}')) and not exists(select 1 from public.collections where id in ('#{GROUPS.join("','")}'));") == 't'
    raise 'Synthetic cleanup failed' unless clean
    checks << {name: 'exact synthetic targets removed', status: 'pass'}
  end
end
puts JSON.pretty_generate(captured_at: Time.now.utc.iso8601, database: DB, mode: 'isolated PostgreSQL overlapping transactions', checks: checks)
