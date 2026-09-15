# frozen_string_literal: true

require 'digest'
require 'json'
require 'open3'
require 'time'
require_relative 'fullstack_database'

# Existing assertion suites run unchanged on a fresh clone for each case. The
# historical database names are local SQL guards, never container selectors.
module FullstackDatabaseSql
  ROOT = FullstackDatabase::ROOT
  MEMBER_DB = 'collect_uat_20260902'.freeze
  MONEY_DB = 'collect_hybrid_money_uat_20260903'.freeze
  CASES = [
    *%w[admin_hybrid_overview_contract group_admin_contract group_owner_controls_contract
        member_collection_read_contract member_cross_rail_history_contract
        member_group_roster_contract member_volume_uat].map { |id| ["scripts/tests/#{id}.sql", MEMBER_DB] },
    ['scripts/tests/platform_admin_access_contract.sql', 'collect_platform_access_uat_20260902'],
    ['scripts/tests/member_roster_access_uat.sql', MEMBER_DB],
    *%w[hybrid_direct_ussd_financial_core_uat attested_sms_finality_uat hybrid_roster_import_uat].map do |id|
      ["scripts/tests/#{id}.sql", MONEY_DB]
    end,
    ['scripts/tests/hybrid_sms_notification_outbox_uat.sql', 'collect_hybrid_sms_uat_20260903'],
    ['scripts/tests/hybrid_verified_account_claim_uat.sql', MONEY_DB, 'collect_hybrid_account_claim_uat'],
    ['scripts/tests/hybrid_internal_function_privileges_uat.sql', 'collect_hybrid_privilege_uat_20260903'],
    ['scripts/tests/hybrid_backend_uat.sql', 'collect_hybrid_uat_20260902'],
    ['scripts/tests/hybrid_directory_presentation_uat.sql', 'collect_directory_presentation_v2_uat_20260903'],
    ['scripts/tests/geographic_member_profile_gates_uat.sql', MEMBER_DB, nil, 'wrap'],
    ['scripts/bank_transfer_rollback_uat.sql', MEMBER_DB],
    ['scripts/group_creation_journey_uat.sql', MEMBER_DB],
    ['scripts/local_backend_privacy_lifecycle_uat.sql', MEMBER_DB, nil, 'LOCAL_BACKEND_PRIVACY_LIFECYCLE_PASS'],
    ['scripts/tests/otp_rate_limit_uat.sql', 'collect_fullstack_otp_20260914']
  ].freeze

  def self.docker(*args, input: nil)
    FullstackDatabase.docker('exec', '-i', FullstackDatabase::CONTAINER, *args,
                             input: input, timeout: 90)
  end

  def self.execute!(*args, input: nil)
    output, error, status = docker(*args, input: input)
    raise "Local fixture command failed: #{error}" unless status.success?
    output
  end

  def self.readback(database)
    sql = <<~SQL
      select json_build_object(
        'database',current_database(),
        'users',(select count(*) from auth.users),
        'only_bootstrap_user',(select coalesce(bool_and(id='99100000-0000-4000-8000-000000000001'), false) from auth.users),
        'profiles',(select count(*) from public.profiles),
        'collections',(select count(*) from public.collections),
        'memberships',(select count(*) from public.collection_members),
        'payments',(select count(*) from public.payments),
        'raw_sms',(select count(*) from public.raw_payment_sms),
        'ledger',(select count(*) from public.ledger_entries),
        'outbox',(select count(*) from collect_hybrid.sms_notification_outbox),
        'migrations',(select count(*) from supabase_migrations.schema_migrations)
      );
    SQL
    JSON.parse(execute!('psql', '-XqAt', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1', input: sql))
  end

  def self.verified_baseline(replay_report: nil)
    target = FullstackDatabase.verify!
    replay_path = replay_report || File.join(ROOT, '.cache/fullstack-qa/20260914T151002Z/database-clean-replay-with-auth.json')
    replay = JSON.parse(File.read(replay_path))
    migrations = Dir[File.join(ROOT, 'supabase/migrations/*.sql')].sort
    expected = migrations.to_h { |path| [File.basename(path), Digest::SHA256.file(path).hexdigest] }
    actual = replay.fetch('migrations').to_h { |entry| [entry.fetch('migration'), entry.fetch('sha256')] }
    unless replay['status'] == 'pass' && replay.dig('target_provenance', 'container_id') == target[:container_id] &&
           replay.fetch('migrations').all? { |entry| entry['status'] == 'pass' } && actual == expected
      raise 'Successful current-source replay on this exact container required'
    end
    baseline = readback('postgres')
    unless baseline.values_at('users', 'profiles', 'payments', 'raw_sms', 'migrations', 'only_bootstrap_user') == [1, 1, 0, 0, migrations.length, true]
      raise 'Pristine synthetic replay baseline required'
    end
    { target: target, replay_path: replay_path, migrations: migrations, expected: expected, baseline: baseline }
  end

  def self.run(output, selected: nil, replay_report: nil)
    raise 'New evidence directory required' if File.exist?(output)
    state = verified_baseline(replay_report: replay_report)
    target, replay_path, migrations, expected, baseline = state.values_at(:target, :replay_path, :migrations, :expected, :baseline)
    cases = CASES
    if selected
      known = CASES.map { |entry| File.basename(entry[0], '.sql') }
      raise 'Unknown or empty case selection' if selected.empty? || (selected - known).any?
      cases = CASES.select { |entry| selected.include?(File.basename(entry[0], '.sql')) }
    end
    Dir.mkdir(output, 0o700)
    report = { schema_version: 1, environment: 'task_owned_current_schema_synthetic_rollback',
               target: target, replay_report: replay_path, replay_sha256: Digest::SHA256.file(replay_path).hexdigest,
               source_migrations: expected, baseline: baseline, cases: [], cleanup: [], final_acceptance: false,
               limitations: ['SQL/RLS/RPC checks only; no API gateway, native device or provider transport',
                             'Scheduled and network background workers disabled in this fixture',
                             'Database clones preserve the current bootstrap owner and public group seed data'] }
    cases.each do |source, database, app_name, special|
      FullstackDatabase.verify!
      id = File.basename(source, '.sql')
      path = File.join(ROOT, source)
      source_sha = Digest::SHA256.file(path).hexdigest
      sql = File.read(path)
      marker = special && special != 'wrap' ? special : "#{id.upcase}_PASS"
      if special == 'wrap'
        sql = "begin;\nset local statement_timeout='30s';\n#{sql}\nselect '#{marker}';\nrollback;\n"
      end
      raise "Missing rollback boundary in #{source}" unless sql.strip.downcase.end_with?('rollback;')
      sql = "set application_name='#{app_name || 'collect_fullstack_qa_sql'}';\n#{sql}"
      sql = "set statement_timeout='30s'; set lock_timeout='5s';\n#{sql}"
      created = false
      started = Time.now.utc.iso8601(6)
      clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      phase = 'create_clone'
      log = File.join(output, "#{id}.log")
      out, err = '', ''
      begin
        # createdb refuses an existing database. Never drops a pre-existing fixture.
        execute!('createdb', '-U', 'postgres', '--template=postgres', database)
        created = true
        phase = 'read_before'
        before = readback(database)
        phase = 'execute_sql'
        out, err, status = docker('psql', '-XAt', '-U', 'postgres', '-d', database,
                                 '-v', 'ON_ERROR_STOP=1', input: sql)
        File.open(log, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(out + err) }
        phase = 'read_after'
        after = readback(database)
        unchanged = source_sha == Digest::SHA256.file(path).hexdigest
        passed = status.success? && (out + err).include?(marker) && out.lines.any? { |line| line.strip == 'ROLLBACK' } && before == after && unchanged
        result = { id: id, source: source, source_sha256: source_sha, executed_sql_sha256: Digest::SHA256.hexdigest(sql),
                   database: database, started_at: started, finished_at: Time.now.utc.iso8601(6),
                   seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - clock).round(3),
                   exit_code: status.exitstatus, marker_found: (out + err).include?(marker),
                   rollback_observed: out.lines.any? { |line| line.strip == 'ROLLBACK' },
                   before: before, after: after, source_unchanged: unchanged,
                   log: log, log_sha256: Digest::SHA256.file(log).hexdigest,
                   status: passed ? 'pass' : 'fail', errors: err.lines.grep(/ERROR|DETAIL|CONTEXT/).map(&:strip) }
        report[:cases] << result
        puts JSON.generate(id: id, status: result[:status], seconds: result[:seconds], errors: result[:errors])
        $stdout.flush
      rescue StandardError => error
        detail = if error.is_a?(FullstackDatabase::CommandTimeout)
                   error.output + error.error
                 else
                   error.message
                 end
        File.open(log, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |file|
          file.write("\nQA command failed during #{phase}: #{error.message}\n#{detail}\n")
        end
        report[:cases] << {
          id: id, source: source, source_sha256: source_sha,
          executed_sql_sha256: Digest::SHA256.hexdigest(sql), database: database,
          started_at: started, finished_at: Time.now.utc.iso8601(6),
          seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - clock).round(3),
          status: 'fail', failed_phase: phase, errors: [error.message],
          command_outcome: error.is_a?(FullstackDatabase::CommandTimeout) ? 'unverified_after_client_timeout' : 'failed',
          log: log, log_sha256: Digest::SHA256.file(log).hexdigest,
          source_unchanged: source_sha == Digest::SHA256.file(path).hexdigest
        }
        raise
      ensure
        primary_error = $!
        cleanup_error = nil
        if created
          begin
            FullstackDatabase.verify!
            execute!('dropdb', '-U', 'postgres', database)
            report[:cleanup] << { database: database, status: 'pass', action: 'dropped_created_clone' }
          rescue StandardError => error
            cleanup_error = error
            report[:cleanup] << { database: database, status: 'fail', action: 'drop_created_clone', error: error.message }
            if error.is_a?(FullstackDatabase::CommandTimeout)
              report[:cleanup].last.merge!(command_outcome: 'unverified_after_client_timeout',
                                           partial_stdout: error.output, partial_stderr: error.error)
            end
          end
        else
          report[:cleanup] << { database: database, status: 'skipped', action: 'creation_not_confirmed_no_drop' }
        end
        report[:source_unchanged] = expected == migrations.to_h { |migration| [File.basename(migration), Digest::SHA256.file(migration).hexdigest] }
        report[:status] = report[:source_unchanged] && report[:cases].length == cases.length &&
                          report[:cases].all? { |entry| entry[:status] == 'pass' } &&
                          report[:cleanup].length == cases.length && report[:cleanup].all? { |entry| entry[:status] == 'pass' } ? 'pass' : 'fail'
        File.open(File.join(output, 'report.json'), File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
          file.write(JSON.pretty_generate(report) + "\n")
        end
        raise cleanup_error if cleanup_error && !primary_error
      end
    end
    report[:status] == 'pass'
  end
end

if $PROGRAM_NAME == __FILE__
  selection = ARGV.find { |argument| argument.start_with?('--only=') }
  ARGV.delete(selection) if selection
  replay = ARGV.find { |argument| argument.start_with?('--replay-report=') }
  ARGV.delete(replay) if replay
  abort('Usage: fullstack_database_sql.rb NEW_EVIDENCE_DIRECTORY [--only=case_id,...] [--replay-report=PATH]') unless ARGV.length == 1
  begin
    exit(FullstackDatabaseSql.run(ARGV.first, selected: selection&.split('=', 2)&.last&.split(','),
                                 replay_report: replay&.split('=', 2)&.last) ? 0 : 1)
  rescue StandardError => error
    warn "Full-stack SQL review failed: #{error.message}"
    exit 1
  end
end
