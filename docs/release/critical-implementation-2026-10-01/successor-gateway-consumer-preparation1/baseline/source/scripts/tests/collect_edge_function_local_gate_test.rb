# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../audits/collect_edge_function_local_gate'

class CollectEdgeFunctionLocalGateTest < Minitest::Test
  Gate = CollectEdgeFunctionLocalGate
  Status = Struct.new(:exitstatus) do
    def success?
      exitstatus.zero?
    end
  end

  def setup
    @root = Dir.mktmpdir('collect-edge-gate-')
    @output = File.join(@root, 'report.json')
    @deno = File.join(@root, 'deno')
    File.write(@deno, 'fake executable, never invoked')
    File.chmod(0o700, @deno)
    File.write(File.join(@root, '.dvmrc'), "2.5.6\n")
    Gate::EXPECTED_JWT.each_key do |slug|
      directory = File.join(@root, 'supabase/functions', slug)
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, 'index.ts'), "export {};\n")
    end
    @test = File.join(@root, 'supabase/functions/ingest-bank-sms/nested/receipt_test.ts')
    FileUtils.mkdir_p(File.dirname(@test))
    File.write(@test, 'synthetic test source')
    @config = File.join(@root, 'supabase/config.toml')
    File.write(@config, Gate::EXPECTED_JWT.map { |slug, jwt| "[functions.#{slug}]\nverify_jwt = #{jwt}\n" }.join("\n"))
    @calls = []
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def run_gate(version: '2.5.6', summary: "ok | 57 passed | 0 failed (20ms)\n", test_exit: 0, check_exit: 0, mutate: false)
    executor = lambda do |*arguments, **options|
      child_env, binary, command, *rest = arguments
      assert_equal @root, options[:chdir]
      assert_equal @deno, binary
      @calls << { command: command, args: rest, env: child_env }
      case command
      when '--version'
        ["deno #{version} (stable, release, aarch64-apple-darwin)\nv8 synthetic\n", '', Status.new(0)]
      when 'test'
        [summary, '', Status.new(test_exit)]
      when 'check'
        File.write(@test, 'changed after test execution') if mutate
        ['', check_exit.zero? ? '' : 'synthetic type error', Status.new(check_exit)]
      else
        flunk "Unexpected child command #{command}"
      end
    end
    result = nil
    capture_io do
      Open3.stub(:capture3, executor) do
        result = Gate.run(@output, root: @root, env: { 'DENO_BIN' => @deno })
      end
    end
    [result, JSON.parse(File.read(@output))]
  end

  def test_all_functions_nested_tests_dynamic_count_and_restricted_environment
    result, report = run_gate
    assert result
    assert_equal 57, report.dig('tests', 'count')
    assert_equal 11, report.dig('checks', 'entrypoints').length
    assert_equal 12, report.dig('checks', 'files').length
    assert_equal ['supabase/functions/ingest-bank-sms/nested/receipt_test.ts'], report.dig('tests', 'files')
    test_command = @calls.find { |call| call[:command] == 'test' }
    assert_includes test_command[:args], "--allow-env=#{Gate::TEST_ENV.join(',')}"
    refute_includes test_command[:args], '--allow-env'
    assert Gate::TEST_ENV.all? { |name| test_command[:env].key?(name) && test_command[:env][name].nil? }
    assert_equal 0o600, File.stat(@output).mode & 0o777
    assert report['source_inputs_unchanged']
    refute report['final_acceptance']
  end

  def test_runtime_can_be_found_on_path
    assert_equal @deno, Gate.runtime('PATH' => @root)
    assert_raises(RuntimeError) { Gate.runtime('DENO_BIN' => @root, 'PATH' => @root) }
  end

  def test_wrong_runtime_is_recorded_and_stops_before_test_execution
    result, report = run_gate(version: '2.5.5')
    refute result
    assert_match(/must match .dvmrc/, report['error'])
    assert_equal ['--version'], @calls.map { |call| call[:command] }
  end

  def test_zero_ignored_or_missing_summary_cannot_pass
    ["ok | 0 passed | 0 failed\n", "ok | 57 passed | 0 failed | 1 ignored\n", "unrecognized output\n"].each do |summary|
      File.delete(@output) if File.exist?(@output)
      result, report = run_gate(summary: summary)
      refute result
      assert_equal 'fail', report.dig('tests', 'status')
      refute report['commands'].any? { |command| command['command'].include?('check') }
    end
  end

  def test_nonzero_test_exit_cannot_pass_even_with_success_text
    result, report = run_gate(test_exit: 1)
    refute result
    assert_equal 'fail', report.dig('tests', 'status')
  end

  def test_type_failure_preserves_completed_tests_and_failure_output
    result, report = run_gate(check_exit: 1)
    refute result
    assert_equal 'pass', report.dig('tests', 'status')
    assert_equal 'fail', report.dig('checks', 'status')
    assert_equal 'synthetic type error', report['commands'].last['stderr']
  end

  def test_source_change_during_execution_invalidates_result
    result, report = run_gate(mutate: true)
    refute result
    refute report['source_inputs_unchanged']
    assert_match(/source or config changed/, report['error'])
  end

  def test_jwt_config_and_entrypoint_drift_fail_closed
    File.write(@config, File.read(@config).sub('verify_jwt = false', 'verify_jwt = true'))
    result, report = run_gate
    refute result
    assert_match(/JWT config differs/, report['error'])
    directory = File.join(@root, 'supabase/functions/new-unreviewed-function')
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'index.ts'), 'export {};')
    assert_raises(RuntimeError) { Gate.inventory(@root) }
  end

  def test_no_tests_or_existing_report_are_rejected
    File.delete(@test)
    assert_raises(RuntimeError) { Gate.inventory(@root) }
    File.write(@output, 'previous evidence')
    assert_raises(RuntimeError) { Gate.run(@output, root: @root, env: { 'DENO_BIN' => @deno }) }
    assert_equal 'previous evidence', File.read(@output)
  end
end
