#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class PublicWebsiteCiGateTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  GATE = File.join(ROOT, 'scripts/public_website_ci_gate.sh')

  def run_live_gate(status:, missing_external_count:, code_checks:, completion_exit:)
    Dir.mktmpdir('collect-public-ci-gate-') do |root|
      scripts = File.join(root, 'scripts')
      FileUtils.mkdir_p(scripts)
      FileUtils.cp(GATE, File.join(scripts, 'public_website_ci_gate.sh'))
      File.write(File.join(scripts, 'public_website_live_gate.sh'), "#!/usr/bin/env bash\nprintf '{}\\n'\n")
      File.write(File.join(scripts, 'public_website_audit_evidence.sh'), "#!/usr/bin/env bash\nprintf '{}\\n'\n")
      payload = JSON.generate(
        status: status,
        missing_external_count: missing_external_count,
        code_checks: code_checks
      )
      File.write(
        File.join(scripts, 'public_website_completion_gate.sh'),
        "#!/usr/bin/env bash\nprintf '%s\\n' '#{payload}'\nexit #{completion_exit}\n"
      )
      _output, _errors, result = Open3.capture3(
        { 'PUBLIC_WEBSITE_CI_OUT_DIR' => File.join(root, 'evidence') },
        'bash', File.join(scripts, 'public_website_ci_gate.sh'), 'live',
        chdir: root
      )
      return result.exitstatus
    end
  end

  def test_external_missing_evidence_fails_production_live_gate
    refute_equal 0, run_live_gate(
      status: 'fail', missing_external_count: 1,
      code_checks: { 'public_routes' => true }, completion_exit: 1
    )
  end

  def test_completion_gate_exit_failure_is_not_hidden_by_pass_payload
    refute_equal 0, run_live_gate(
      status: 'pass', missing_external_count: 0,
      code_checks: { 'public_routes' => true }, completion_exit: 1
    )
  end

  def test_passed_completion_gate_succeeds
    assert_equal 0, run_live_gate(
      status: 'pass', missing_external_count: 0,
      code_checks: { 'public_routes' => true }, completion_exit: 0
    )
  end
end
