# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'

# Exercises the real runner inside an isolated tree with synthetic commands.
class RepoWideQaUatTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @root = Dir.mktmpdir('collect-runner-fixture-')
    FileUtils.mkdir_p(File.join(@root, 'scripts/qa'))
    FileUtils.cp(File.join(ROOT, 'scripts/repo_wide_qa_uat.sh'), File.join(@root, 'scripts/repo_wide_qa_uat.sh'))
    stub = <<~'SH'
      #!/bin/bash
      set -eu
      ruby -r json -r fileutils - "${0##*/}" <<'INNER_RUBY'
      name = ARGV.fetch(0)
      payload = { status: 'pass', signoff_approved: true, manifest_written: true,
        go_live_approved: true, decision: 'GO', approval_status: 'approved', blocker_keys: [] }
      if name == 'supabase_go_live_evidence_bundle.sh'
        FileUtils.mkdir_p(ENV.fetch('SUPABASE_EVIDENCE_BUNDLE_DIR'))
        File.write(File.join(ENV.fetch('SUPABASE_EVIDENCE_BUNDLE_DIR'), 'summary.json'), JSON.generate(payload))
      end
      puts JSON.generate(payload)
      INNER_RUBY
    SH
    names = File.read(File.join(ROOT, 'scripts/repo_wide_qa_uat.sh')).scan(%r{\$ROOT_DIR/scripts/([a-z_]+\.sh)}).flatten.uniq
    names.each { |name| executable("scripts/#{name}", stub) }
    executable('flutter', "#!/bin/sh\nexit 0\n")
    executable('dart', "#!/bin/sh\nexit 0\n")
    executable('adb', "#!/bin/sh\nprintf 'List of devices attached\\nqa-fixture-device\\tdevice\\n'\n")
    File.write(File.join(@root, 'scripts/qa/dart_format.rb'), "exit 0\n")
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

  def test_execution_reports_route_artifacts_without_a_visual_score
    summary, code = run_runner
    assert_equal 0, code
    assert_equal 'GO', summary['decision']
    assert_equal false, summary['fixture_mode']
    assert_equal 'pass', summary['surfaces']['mobile_route_artifacts']
    refute summary['surfaces'].key?('mobile_visual_acceptance_android')
    refute summary['surfaces'].key?('mobile_visual_acceptance_ios')
    refute summary.key?('mobile_visual_acceptance')
  end

  def test_runner_fixture_cannot_claim_release_eligibility
    summary, code = run_runner('QA_UAT_FIXTURE' => '1')
    assert_equal 1, code
    refute_equal 'GO', summary['decision']
    assert_equal true, summary['fixture_mode']
    assert_equal false, summary['release_eligible']
    assert_equal 'runner_fixture', summary['evidence_kind']
    refute_includes summary['surfaces'].values, 'pass'
  end
end
