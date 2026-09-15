# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../qa/fullstack_database_sql'

class FullstackDatabaseSqlTest < Minitest::Test
  CASE = 'group_admin_contract'

  def with_fixture(execute:, sql:)
    Dir.mktmpdir('collect-qa-sql-test-') do |directory|
      replay = File.join(directory, 'replay.json')
      migrations = Dir[File.join(FullstackDatabase::ROOT, 'supabase/migrations/*.sql')].sort.map do |path|
        { migration: File.basename(path), sha256: Digest::SHA256.file(path).hexdigest, status: 'pass' }
      end
      File.write(replay, JSON.generate(status: 'pass', target_provenance: { container_id: 'synthetic' }, migrations: migrations))
      baseline = { 'users' => 1, 'profiles' => 1, 'payments' => 0, 'raw_sms' => 0,
                   'migrations' => migrations.length, 'only_bootstrap_user' => true }
      output = File.join(directory, 'evidence')
      FullstackDatabase.stub(:verify!, { container_id: 'synthetic' }) do
        FullstackDatabaseSql.stub(:readback, baseline) do
          FullstackDatabaseSql.stub(:execute!, execute) do
            FullstackDatabaseSql.stub(:docker, sql) do
              yield output, replay
            end
          end
        end
      end
    end
  end

  def successful_sql
    status = Struct.new(:success?, :exitstatus).new(true, 0)
    ["#{CASE.upcase}_PASS\nROLLBACK\n", '', status]
  end

  def run_case(output, replay)
    FullstackDatabaseSql.run(output, selected: [CASE], replay_report: replay)
  end

  def test_success_requires_rollback_readback_and_confirmed_cleanup
    commands = []
    execute = lambda { |*args| commands << args; '' }
    with_fixture(execute: execute, sql: successful_sql) do |output, replay|
      capture_io { assert run_case(output, replay) }
      report = JSON.parse(File.read(File.join(output, 'report.json')))
      assert_equal 'pass', report['status']
      assert_equal ['createdb', 'dropdb'], commands.map(&:first)
      assert_equal 'dropped_created_clone', report['cleanup'].first['action']
      assert_equal report['cases'].first['log_sha256'], Digest::SHA256.file(report['cases'].first['log']).hexdigest
    end
  end

  def test_timeout_evidence_survives_cleanup_failure_without_masking_primary_error
    commands = []
    execute = lambda do |*args|
      commands << args
      raise 'clone still has a connection' if args.first == 'dropdb'
      ''
    end
    timeout = FullstackDatabase::CommandTimeout.new('partial SQL output', 'partial diagnostic', 90)
    sql = ->(*_args, **_options) { raise timeout }
    with_fixture(execute: execute, sql: sql) do |output, replay|
      error = assert_raises(FullstackDatabase::CommandTimeout) { run_case(output, replay) }
      assert_same timeout, error
      report = JSON.parse(File.read(File.join(output, 'report.json')))
      assert_equal 'fail', report['status']
      assert_equal 'execute_sql', report['cases'].first['failed_phase']
      assert_equal 'unverified_after_client_timeout', report['cases'].first['command_outcome']
      assert_includes File.read(report['cases'].first['log']), 'partial SQL output'
      assert_includes File.read(report['cases'].first['log']), 'partial diagnostic'
      assert_equal 'fail', report['cleanup'].first['status']
      assert_equal ['createdb', 'dropdb'], commands.map(&:first)
    end
  end

  def test_uncertain_creation_never_drops_a_database
    commands = []
    execute = lambda do |*args|
      commands << args
      raise FullstackDatabase::CommandTimeout.new('creation started', '', 90)
    end
    with_fixture(execute: execute, sql: successful_sql) do |output, replay|
      assert_raises(FullstackDatabase::CommandTimeout) { run_case(output, replay) }
      report = JSON.parse(File.read(File.join(output, 'report.json')))
      assert_equal ['createdb'], commands.map(&:first)
      assert_equal 'create_clone', report['cases'].first['failed_phase']
      assert_equal 'creation_not_confirmed_no_drop', report['cleanup'].first['action']
      assert_equal 'fail', report['status']
    end
  end

  def test_cleanup_failure_cannot_leave_a_passing_report
    execute = lambda do |*args|
      raise 'drop failed' if args.first == 'dropdb'
      ''
    end
    with_fixture(execute: execute, sql: successful_sql) do |output, replay|
      capture_io do
        assert_raises(RuntimeError) { run_case(output, replay) }
      end
      report = JSON.parse(File.read(File.join(output, 'report.json')))
      assert_equal 'pass', report['cases'].first['status']
      assert_equal 'fail', report['status']
      assert_equal 'drop failed', report['cleanup'].first['error']
    end
  end
end
