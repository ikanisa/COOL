# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'

# Execute the real runner inside an isolated tree with synthetic tools. These
# tests verify reporting/decision behavior, never real release acceptance.
class RepoWideQaUatTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @root = Dir.mktmpdir('collect-runner-fixture-')
    FileUtils.mkdir_p(File.join(@root, 'scripts/qa'))
    FileUtils.cp(File.join(ROOT, 'scripts/repo_wide_qa_uat.sh'), File.join(@root, 'scripts/repo_wide_qa_uat.sh'))
    stub = <<~'SH'
      #!/bin/bash
      set -eu
      ruby -r json -r fileutils - "${0##*/}" <<'RUBY'
      name = ARGV.fetch(0)
      payload = { status: 'pass', signoff_approved: true, manifest_written: true,
        go_live_approved: true, decision: 'GO', approval_status: 'approved', blocker_keys: [] }
      if name == 'supabase_go_live_evidence_bundle.sh'
        FileUtils.mkdir_p(ENV.fetch('SUPABASE_EVIDENCE_BUNDLE_DIR'))
        File.write(File.join(ENV.fetch('SUPABASE_EVIDENCE_BUNDLE_DIR'), 'summary.json'), JSON.generate(payload))
      end
      puts JSON.generate(payload)
      RUBY
    SH
    names = File.read(File.join(ROOT, 'scripts/repo_wide_qa_uat.sh')).scan(%r{\$ROOT_DIR/scripts/([a-z_]+\.sh)}).flatten.uniq
    names.each { |name| executable("scripts/#{name}", stub) }
    executable('flutter', "#!/bin/sh\nexit 0\n")
    executable('dart', "#!/bin/sh\nexit 0\n")
    executable('adb', "#!/bin/sh\nprintf 'List of devices attached\\nqa-fixture-device\\tdevice\\n'\n")
    File.write(File.join(@root, 'scripts/qa/dart_format.rb'), "exit 0\n")
    File.write(File.join(@root, 'scripts/qa/mobile_design_gate.rb'), <<~'RUBY')
      require 'json'
      if ARGV.include?('--check-contract')
        puts JSON.generate(status: 'contract_valid', release_status: 'not_assessed', failures: [])
        exit 0
      end
      platform = ARGV.include?('--ios') ? 'ios' : 'android'
      status = ENV.fetch("QA_TEST_#{platform.upcase}_STATUS", 'pass')
      payload = { rule: 'MOBILE-DESIGN-100', platform: platform, status: status,
        score: status == 'pass' ? 100 : nil, failures: status == 'pass' ? [] : ['Synthetic missing review'] }
      payload[:failures] = ['Synthetic contradiction'] if ENV['QA_TEST_CONTRADICTORY_GATE'] == platform
      puts JSON.generate(payload)
      exit(status == 'pass' ? 0 : 1)
    RUBY
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def executable(path, content)
    File.write(File.join(@root, path), content)
    File.chmod(0o755, File.join(@root, path))
  end

  def run_runner(overrides = {})
    bundle = File.join(@root, 'evidence')
    environment = {
      'PATH' => '/usr/bin:/bin:/usr/sbin:/sbin',
      'HOME' => ENV.fetch('HOME'),
      'FLUTTER' => File.join(@root, 'flutter'), 'DART' => File.join(@root, 'dart'),
      'ADB' => File.join(@root, 'adb'), 'ANDROID_UAT_DEVICE_ID' => 'qa-fixture-device',
      'QA_UAT_BUNDLE_DIR' => bundle
    }.merge(overrides)
    stdout, stderr, status = Open3.capture3(environment, '/bin/bash',
      File.join(@root, 'scripts/repo_wide_qa_uat.sh'), '--json', unsetenv_others: true)
    assert File.file?(File.join(bundle, 'summary.json')), "Runner did not produce a summary: #{stdout}\n#{stderr}"
    [JSON.parse(File.read(File.join(bundle, 'summary.json'))), status.exitstatus]
  end

  def test_both_design_gates_are_required_in_execution_mode
    summary, code = run_runner
    assert_equal 0, code
    assert_equal 'GO', summary['decision']
    assert_equal false, summary['fixture_mode']
    assert_equal 'pass', summary['surfaces']['mobile_visual_acceptance_android']
    assert_equal 'pass', summary['surfaces']['mobile_visual_acceptance_ios']
    assert_includes summary['commands'].map { |row| row['name'] }, 'mobile_design_android'
    assert_includes summary['commands'].map { |row| row['name'] }, 'mobile_design_ios'
  end

  def test_android_blocked_cannot_be_cancelled_by_passing_ios_and_contract
    summary, code = run_runner('QA_TEST_ANDROID_STATUS' => 'blocked')
    assert_equal 1, code
    assert_equal 'NO-GO', summary['decision']
    assert_equal false, summary['release_eligible']
    assert_equal 'blocked', summary['surfaces']['mobile_visual_acceptance_android']
    assert_equal 'pass', summary['surfaces']['mobile_contract_compliance']
  end

  def test_ios_blocked_cannot_be_cancelled_by_passing_android
    summary, code = run_runner('QA_TEST_IOS_STATUS' => 'blocked')
    assert_equal 1, code
    assert_equal 'NO-GO', summary['decision']
    assert_equal 'blocked', summary['surfaces']['mobile_visual_acceptance_ios']
  end

  def test_zero_exit_with_contradictory_gate_payload_fails
    summary, code = run_runner('QA_TEST_CONTRADICTORY_GATE' => 'android')
    assert_equal 1, code
    assert_equal 'FAIL', summary['decision']
    assert_equal 'fail', summary['surfaces']['mobile_visual_acceptance_android']
  end

  def test_runner_fixture_results_are_explicitly_unverified
    summary, code = run_runner('QA_UAT_FIXTURE' => '1')
    assert_equal 1, code
    refute_equal 'GO', summary['decision']
    assert_equal true, summary['fixture_mode']
    assert_equal false, summary['release_eligible']
    assert_equal 'runner_fixture', summary['evidence_kind']
    refute_includes summary['surfaces'].values, 'pass'
    assert_equal 'unverified', summary['surfaces']['flutter_app']
    assert_equal 'blocked', summary['surfaces']['mobile_visual_acceptance_android']
    assert_equal 'blocked', summary['surfaces']['mobile_visual_acceptance_ios']
  end
end
