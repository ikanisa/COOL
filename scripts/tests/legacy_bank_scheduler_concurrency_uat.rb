# Root-only SQL execution on the exact isolated fixture. By default this prints
# usage and performs no database operation. Every mutation uses cron.alter_job.
require 'json'
require 'open3'
require 'timeout'
require 'fileutils'
require 'digest'
require 'time'

module LegacyBankSchedulerConcurrency
  ROOT = File.expand_path('../..', __dir__)
  PROJECT = 'collect_fin_concurrency_qa_20260929'
  CONTAINER = 'supabase_db_' + PROJECT
  COMMAND = "select public.run_daily_bank_reconciliation(current_date, 'scheduled daily reconciliation');"
  SNAPSHOT = File.join(ROOT, 'scripts/tests/legacy_bank_scheduler_snapshot.sql')

  class Session
    attr_reader :pid, :errors
    def initialize
      @stdin, @stdout, @stderr, @wait = Open3.popen3('docker', 'exec', '-i', CONTAINER,
        'psql', '-XqAt', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=0')
      @errors = +''
      @error_thread = Thread.new { @stderr.each_line { |line| @errors << line } }
      @counter = 0
      @pid = Integer(run('select pg_backend_pid();').last)
      run("set statement_timeout='15s'; set lock_timeout='10s'; set collect.legacy_bank_scheduler_qa='isolated_clone';")
      run(<<~SQL)
        create function pg_temp.capture(action text) returns jsonb language plpgsql as $$
        declare result jsonb; code text; message text; begin
          begin execute action into result;
          exception when others then get stacked diagnostics code = returned_sqlstate, message = message_text;
            return jsonb_build_object('ok',false,'sqlstate',code,'message',message);
          end;
          return jsonb_build_object('ok',true,'result',result);
        end $$;
      SQL
    end

    def run(sql)
      @counter += 1
      marker = "scheduler_done_#{@pid || 0}_#{@counter}"
      @stdin.write(sql + "\n\\echo #{marker}\n")
      @stdin.flush
      lines = []
      Timeout.timeout(20) do
        loop do
          line = @stdout.gets
          raise 'psql ended before command boundary' unless line
          break if line.strip == marker
          lines << line.strip unless line.strip.empty?
        end
      end
      lines
    end

    def json(sql)
      rows = run(sql).select { |line| line.start_with?('{') }
      raise "Expected one JSON row, got #{rows.length}" unless rows.length == 1
      JSON.parse(rows.first)
    end

    def capture(sql)
      escaped = sql.gsub("'", "''")
      json("select pg_temp.capture('#{escaped}');")
    end

    def close
      return if @stdin.closed?
      @stdin.write("rollback;\n\\q\n")
      @stdin.close
      @wait.value
      @error_thread.join
      @stdout.close
      @stderr.close
    rescue IOError, Errno::EPIPE
      @wait.value
    end
  end

  def self.require!(condition, message)
    raise message unless condition
  end

  def self.snapshot
    session = Session.new
    begin
      session.json(File.read(SNAPSHOT))
    ensure
      session.close
    end
  end

  def self.blocked!(monitor, reader, editor)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      proof = monitor.json("select jsonb_build_object('waiter',#{reader.pid},'blockers',pg_blocking_pids(#{reader.pid}));")
      return proof if proof.fetch('blockers').include?(editor.pid)
      raise 'Expected real PostgreSQL blocking relation not observed' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.05
    end
  end

  def self.persist(path, value)
    temporary = path + '.tmp'
    File.write(temporary, JSON.pretty_generate(value) + "\n")
    File.rename(temporary, path)
  end

  def self.execute!(phase, output_dir)
    require!(%w[canary142 verified143].include?(phase), 'Unknown phase')
    require!(!File.exist?(output_dir), 'Output directory already exists; preserve prior attempt')
    inspect_json, inspect_status = Open3.capture2('docker', 'inspect', CONTAINER)
    require!(inspect_status.success?, 'Exact container is not running')
    container = JSON.parse(inspect_json).fetch(0)
    require!(container.dig('State', 'Running') == true, 'Exact container is not running')
    require!(container.dig('Config', 'Labels').values.count(PROJECT) >= 2, 'Exact project labels required')
    config = File.read(File.join(ROOT, '.cache/financial-concurrency-20260929/supabase/config.toml'))
    require!(config.match?(/^project_id\s*=\s*"#{PROJECT}"/) && config.match?(/^port\s*=\s*55722$/), 'Exact project config and host DB port required')
    FileUtils.mkdir_p(output_dir, mode: 0o700)
    monitor = Session.new
    guard = monitor.json(<<~SQL)
      select jsonb_build_object('normal_owner',current_user='postgres' and not r.rolsuper,
        'cron_select',has_table_privilege(current_user,'cron.job','SELECT'),
        'cron_dml',has_table_privilege(current_user,'cron.job','INSERT,UPDATE,DELETE,MAINTAIN'),
        'cron_off',current_setting('cron.launch_active_jobs')='off',
        'net_off',current_setting('pg_net.batch_size')='0',
        'versions',(select count(*) from supabase_migrations.schema_migrations),
        'latest',(select max(version) from supabase_migrations.schema_migrations),
        'cron_version',(select extversion from pg_extension where extname='pg_cron'),
        'canonical',(select count(*) from cron.job where jobname='collect-daily-bank-reconciliation'),
        'active_bank',(select count(*) from cron.job where jobname='collect-daily-bank-reconciliation' and active))
      from pg_roles r where r.rolname=current_user;
    SQL
    count, latest = phase == 'canary142' ? [142, '20260930100000'] : [143, '20260930110000']
    require!(guard.values_at('normal_owner','cron_select','cron_dml','cron_off','net_off','versions','latest','cron_version','canonical') ==
      [true,true,false,true,true,count,latest,'1.6.4',1], 'Exact isolated normal-owner fixture required')
    baseline = snapshot
    job = baseline.fetch('cron_jobs').find { |row| row.fetch('name') == 'collect-daily-bank-reconciliation' }
    require!(job.fetch('owner') == 'postgres' && job.fetch('schedule') == '30 21 * * *' && job.fetch('command_sha256') == Digest::SHA256.hexdigest(COMMAND), 'Unexpected canonical source identity')
    require!(job.fetch('active') == (phase == 'canary142'), 'Unexpected phase activity')
    require!(phase == 'canary142' || baseline.fetch('final_verifications').length == 1, 'Verified phase requires final receipt')
    checkpoint = {'started_at' => Time.now.utc.iso8601, 'phase' => phase, 'guard' => guard, 'baseline' => baseline, 'scenarios' => [], 'complete' => false}
    checkpoint_path = File.join(output_dir, 'checkpoint.json')
    persist(checkpoint_path, checkpoint) # Durable evidence BEFORE any mutation.
    job_id = Integer(job.fetch('id'))
    canary = "select jsonb_build_object('job_id',#{job_id},'active',(select active from cron.job where jobid=#{job_id}))"
    action = phase == 'canary142' ? canary : 'select collect_hybrid.retire_legacy_bank_scheduler()'
    verifier = phase == 'canary142' ? canary : 'select collect_hybrid.verify_legacy_bank_scheduler_retirement()'
    restore = "select cron.alter_job(#{job_id}, schedule:='30 21 * * *', command:='#{COMMAND.gsub("'", "''")}', database:='postgres', active:=#{job.fetch('active')});"
    scenarios = [
      ['editor_commit_before_owner_lock', :editor_first, true, "command:='select 1;'", action],
      ['editor_rollback_before_owner_lock', :editor_first, false, "command:='select 1;'", action],
      ['owner_lock_before_editor_commit', :owner_first, true, "command:='select 1;'", action],
      ['owner_lock_before_editor_rollback', :owner_first, false, "command:='select 1;'", action],
      ['schedule_commit_before_owner_lock', :editor_first, true, "schedule:='15 * * * *'", action],
      ['duplicate_pause_serializable_retry', :duplicate, true, nil, action]
    ]
    if phase == 'verified143'
      scenarios += [
        ['reactivation_commit_before_verification', :editor_first, true, 'active:=true', verifier],
        ['verification_lock_before_reactivation', :owner_first, true, 'active:=true', verifier],
        ['duplicate_verification_serializable_retry', :duplicate, true, nil, verifier]
      ]
    end
    begin
      scenarios.each do |label, order, commit_edit, edit, tested_action|
        editor = Session.new
        reader = Session.new
        result = nil
        proof = nil
        begin
          editor.run('begin isolation level serializable;')
          reader.run('begin isolation level serializable;')
          reader.run("select jobid from cron.job where jobid=#{job_id};") # Snapshot BEFORE concurrent commit.
          if order == :editor_first
            editor.run("select cron.alter_job(#{job_id}, #{edit});")
            worker = Thread.new do
              if phase == 'canary142'
                reader.capture("select jsonb_build_object('api_result',cron.alter_job(#{job_id}, schedule:='30 21 * * *')::text);")
              else
                reader.capture(tested_action)
              end
            end
            proof = blocked!(monitor, reader, editor)
            editor.run(commit_edit ? 'commit;' : 'rollback;')
            result = worker.value
            if commit_edit
              require!(result.fetch('ok') == false && result.fetch('sqlstate') == '40001', "#{label}: stale snapshot must fail 40001")
            else
              require!(result.fetch('ok') == true, "#{label}: rollback must permit unchanged owner operation")
            end
          else
            if phase == 'canary142'
              editor.run("select cron.alter_job(#{job_id}, schedule:='30 21 * * *');")
            else
              first = editor.capture(tested_action)
              require!(first.fetch('ok') == true, "#{label}: first owner operation failed")
            end
            worker = Thread.new do
              if order == :duplicate
                phase == 'canary142' ? reader.capture("select jsonb_build_object('api_result',cron.alter_job(#{job_id}, schedule:='30 21 * * *')::text);") : reader.capture(tested_action)
              else
                # External owner editor intentionally uses READ COMMITTED so
                # it serializes after the held owner lock and proves drift.
                reader.run('rollback; begin;')
                reader.capture("select jsonb_build_object('api_result',cron.alter_job(#{job_id}, #{edit})::text);")
              end
            end
            proof = blocked!(monitor, reader, editor)
            editor.run('commit;')
            result = worker.value
            if order == :duplicate
              require!(!result.fetch('ok') && result.fetch('sqlstate') == '40001', "#{label}: stale duplicate must fail 40001")
            else
              require!(result.fetch('ok'), "#{label}: serialized owner edit failed")
              reader.run(commit_edit ? 'commit;' : 'rollback;')
            end
          end
          reader.run('rollback;')
          if phase == 'verified143' && commit_edit && order != :duplicate
            # A fresh SERIALIZABLE transaction is required for actual checks.
            monitor.run('begin isolation level serializable;')
            drift = monitor.capture(tested_action)
            monitor.run('rollback;')
            require!(!drift.fetch('ok') && drift.fetch('sqlstate') == '55000', "#{label}: fresh operation must reject committed drift")
          end
          monitor.run(restore)
          monitor.run('begin isolation level serializable;')
          retry_result = phase == 'canary142' ? monitor.capture(canary) : monitor.capture(tested_action)
          monitor.run('rollback;')
          require!(retry_result.fetch('ok'), "#{label}: exact restored state retry must succeed")
          after = snapshot
          require!(after == baseline, "#{label}: business/job/history/audit fingerprints not restored")
          checkpoint.fetch('scenarios') << {'label' => label, 'blocking' => proof, 'result' => result, 'exact_retry' => retry_result, 'baseline_restored' => true}
          persist(checkpoint_path, checkpoint)
        ensure
          editor.close
          reader.close
        end
      end
      checkpoint['complete'] = true
      checkpoint['completed_at'] = Time.now.utc.iso8601
      checkpoint['final_snapshot'] = snapshot
      require!(checkpoint['final_snapshot'] == baseline, 'Final baseline differs')
      persist(checkpoint_path, checkpoint)
      puts JSON.generate({'ok' => true, 'phase' => phase, 'checks' => scenarios.length, 'checkpoint' => checkpoint_path, 'baseline_restored' => true})
    rescue Exception => error
      checkpoint['error_class'] = error.class.name
      checkpoint['error'] = error.message
      begin
        monitor.run(restore)
        checkpoint['recovered_snapshot'] = snapshot
        checkpoint['baseline_restored_after_error'] = checkpoint['recovered_snapshot'] == baseline
      rescue Exception => cleanup_error
        checkpoint['cleanup_error'] = cleanup_error.message
      end
      persist(checkpoint_path, checkpoint)
      raise
    ensure
      monitor.close
    end
  end
end

if $PROGRAM_NAME == __FILE__
  unless ARGV.length == 3 && ARGV[0] == '--execute'
    warn 'Root-only usage: ruby legacy_bank_scheduler_concurrency_uat.rb --execute canary142|verified143 NEW_OUTPUT_DIR'
    exit 2
  end
  LegacyBankSchedulerConcurrency.execute!(ARGV[1], File.expand_path(ARGV[2]))
end
