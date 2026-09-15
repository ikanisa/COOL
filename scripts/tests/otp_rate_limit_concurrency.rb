# frozen_string_literal: true

require_relative '../qa/fullstack_database_sql'
require 'fileutils'

database = 'collect_fullstack_otp_concurrent_20260914'
output = ARGV.fetch(0)
raise 'New evidence directory required' if File.exist?(output)
Dir.mkdir(output, 0o700)
FileUtils.cp(__FILE__, File.join(output, 'runner-source.rb'))
report = { started_at: Time.now.utc.iso8601(6), final_acceptance: false,
           database: database, commands: [], scenarios: [],
           mode: 'task_owned_committed_sql_races_no_provider_transport' }
created = false
mutex = Mutex.new
threads = []
replay = File.join(FullstackDatabase::ROOT, '.cache/fullstack-qa/20260914T151002Z/database-current-replay-chain-126.json')
sources = [__FILE__, File.expand_path('../qa/fullstack_database.rb', __dir__),
           File.expand_path('../qa/fullstack_database_sql.rb', __dir__)]
report[:source_inputs] = sources.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }

sql_call = lambda do |id, sql|
  sql = "set statement_timeout='35s';set lock_timeout='30s';\n#{sql}"
  File.write(File.join(output, "#{id}.sql"), sql)
  record = { id: id, started_at: Time.now.utc.iso8601(6), sql_sha256: Digest::SHA256.hexdigest(sql) }
  out, err = '', ''
  begin
    out, err, status = FullstackDatabase.docker('exec', '-i', FullstackDatabase::CONTAINER,
      'psql', '-XAt', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose',
      input: sql, timeout: 50)
    record[:exit_code] = status.exitstatus
    record[:command_status] = status.success? ? 'success' : 'sql_error'
  rescue FullstackDatabase::CommandTimeout => error
    out, err = error.output, error.error
    record[:command_status], record[:error] = 'unverified_after_timeout', error.message
  ensure
    record[:finished_at] = Time.now.utc.iso8601(6)
    log = File.join(output, "#{id}.log")
    File.write(log, out + err)
    record[:log], record[:log_sha256] = log, Digest::SHA256.file(log).hexdigest
    mutex.synchronize { report[:commands] << record }
  end
  [record, out, err]
end

begin
  state = FullstackDatabaseSql.verified_baseline(replay_report: replay)
  report[:target], report[:baseline_before], report[:migration_sources] = state.values_at(:target, :baseline, :expected)
  FullstackDatabaseSql.execute!('createdb', '-U', 'postgres', '--template=postgres', database)
  created = true
  setup = <<~SQL
    insert into public.otp_rate_limits(phone_hash,requested_at)
    select phone,clock_timestamp()-interval '1 minute' from
      (values(repeat('8',64)),(repeat('9',64)))fixture(phone) cross join generate_series(1,4);
  SQL
  raise 'Setup failed' unless sql_call.call('setup', setup)[0][:exit_code] == 0

  [['read_committed', 8, '8', 9142101], ['repeatable_read', 2, '9', 9142102]].each do |kind, workers, hash_digit, barrier|
    prefix = "collect_otp_#{kind}"
    controller_sql = <<~SQL
      set application_name='#{prefix}_controller';
      select pg_advisory_lock(#{barrier});
      do $barrier$
      declare deadline timestamptz:=clock_timestamp()+interval '28 seconds'; waiting integer;
      begin
        loop
          perform pg_stat_clear_snapshot();
          select count(*) into waiting from pg_locks locks join pg_stat_activity activity on activity.pid=locks.pid
          where activity.datname=current_database() and activity.application_name like '#{prefix}_worker_%'
            and locks.locktype='advisory' and locks.objid=#{barrier} and not locks.granted;
          if waiting=#{workers} then raise notice 'ALL_#{workers}_WORKERS_OBSERVED'; exit; end if;
          if clock_timestamp()>deadline then raise exception 'Workers did not reach the barrier'; end if;
          perform pg_sleep(0.05);
        end loop;
      end $barrier$;
      select pg_advisory_unlock(#{barrier});
    SQL
    controller = Thread.new { sql_call.call("#{kind}-controller", controller_sql) }
    threads << controller
    ready = false
    5.times do |attempt|
      result, out, = sql_call.call("#{kind}-readiness-#{attempt}", <<~SQL)
        select count(*) from pg_locks locks join pg_stat_activity activity on activity.pid=locks.pid
        where activity.datname=current_database() and activity.application_name='#{prefix}_controller'
          and locks.locktype='advisory' and locks.objid=#{barrier} and locks.granted;
      SQL
      ready = result[:exit_code] == 0 && out.lines.any? { |line| line.strip == '1' }
      break if ready
    end
    raise 'Barrier ownership not observed' unless ready
    worker_threads = (1..workers).map do |number|
      Thread.new do
        sql_call.call("#{kind}-worker-#{number}", <<~SQL)
          set application_name='#{prefix}_worker_#{number}';
          begin isolation level #{kind.tr('_', ' ')};
          select count(*) from public.otp_rate_limits where phone_hash=repeat('#{hash_digit}',64);
          set local role service_role;
          select pg_advisory_xact_lock_shared(#{barrier});
          select case when public.reserve_otp_request(repeat('#{hash_digit}',64),null)
            then 'SLOT_ACCEPTED' else 'SLOT_DENIED' end;
          select pg_sleep(0.1);
          commit;
        SQL
      end
    end
    threads.concat(worker_threads)
    workers_result = worker_threads.map(&:value)
    control = controller.value
    accepted = workers_result.count { |record, out, _| record[:exit_code] == 0 && out.lines.any? { |line| line.strip == 'SLOT_ACCEPTED' } && out.lines.any? { |line| line.strip == 'COMMIT' } }
    denied = workers_result.count { |record, out, _| record[:exit_code] == 0 && out.lines.any? { |line| line.strip == 'SLOT_DENIED' } && out.lines.any? { |line| line.strip == 'COMMIT' } }
    serialization = workers_result.count { |record, _out, err| record[:exit_code] == 3 && err.include?('40001') }
    overlap = control[0][:exit_code] == 0 && control[2].include?("ALL_#{workers}_WORKERS_OBSERVED")
    passed = overlap && accepted == 1 && (kind == 'read_committed' ? denied == 7 && serialization == 0 : denied == 0 && serialization == 1)
    report[:scenarios] << { isolation: kind, workers: workers, all_workers_observed_at_barrier: overlap,
      accepted: accepted, quota_denied: denied, serialization_rejected: serialization, status: passed ? 'pass' : 'fail' }
    raise 'Concurrency expectations failed' unless passed
  end

  result, out, = sql_call.call('final-state', <<~SQL)
    select json_build_object(
      'read_committed_attempts',(select count(*) from public.otp_rate_limits where phone_hash=repeat('8',64)),
      'repeatable_read_attempts',(select count(*) from public.otp_rate_limits where phone_hash=repeat('9',64)),
      'payments',(select count(*) from public.payments),
      'outbox',(select count(*) from collect_hybrid.sms_notification_outbox));
    set role service_role;
    select case when public.reserve_otp_request(repeat('9',64),null) then 'BAD_RETRY' else 'RETRY_DENIED' end;
  SQL
  raise 'Final verification failed' unless result[:exit_code] == 0 && out.lines.any? { |line| line.strip == 'RETRY_DENIED' }
  report[:persisted_effects] = JSON.parse(out.lines.find { |line| line.start_with?('{') })
  raise 'Incorrect committed quota' unless report[:persisted_effects].values_at('read_committed_attempts','repeatable_read_attempts','payments','outbox') == [5,5,0,0]
  report[:source_unchanged] = report[:source_inputs].all? { |path, sha| Digest::SHA256.file(path).hexdigest == sha }
  raise 'Concurrency source changed' unless report[:source_unchanged]
  report[:status] = 'pass'
rescue StandardError => error
  report[:status], report[:error] = 'fail', error.message
ensure
  threads.each(&:join)
  if created
    begin
      FullstackDatabase.verify!
      FullstackDatabaseSql.execute!('dropdb', '-U', 'postgres', database)
      report[:clone_removed] = true
      report[:baseline_after] = FullstackDatabaseSql.readback('postgres')
      raise 'Original baseline changed' unless report[:baseline_after] == report[:baseline_before]
    rescue StandardError => error
      report[:status], report[:cleanup_error] = 'fail', error.message
    end
  end
  report[:finished_at] = Time.now.utc.iso8601(6)
  File.write(File.join(output, 'report.json'), JSON.pretty_generate(report) + "\n")
end
puts JSON.generate(report.reject { |key, _| [:commands, :source_inputs, :migration_sources].include?(key) })
exit(report[:status] == 'pass' ? 0 : 1)
