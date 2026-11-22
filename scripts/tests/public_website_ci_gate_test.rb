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

  def test_live_qualification_collects_each_component_once_and_reports_an_unreadable_component
    Dir.mktmpdir('collect-public-ci-components-') do |root|
      scripts = File.join(root, 'scripts')
      qa = File.join(scripts, 'qa')
      FileUtils.mkdir_p(qa)
      FileUtils.cp(GATE, File.join(scripts, 'public_website_ci_gate.sh'))
      FileUtils.cp(File.join(ROOT, 'scripts/public_website_completion_gate.sh'), scripts)
      FileUtils.cp(File.join(ROOT, 'scripts/qa/public_lighthouse_evidence.rb'), qa)
      FileUtils.mkdir_p(File.join(qa, 'public_website'))
      %w[completion_gate.rb external_evidence.rb].each do |name|
        FileUtils.cp(File.join(ROOT, 'scripts/qa/public_website', name), File.join(qa, 'public_website'))
      end

      probes = {
        'public_website_quality_gate.sh' => ['static', '{"status":"pass","summary":{"passed":55}}', 0],
        'public_website_live_gate.sh' => ['live', 'unreadable fixture', 1],
        'public_website_audit_evidence.sh' => ['audit', '{"status":"pass","metrics":{}}', 3],
      }
      probes.each do |script, (id, body, code)|
        File.write(File.join(scripts, script), <<~SH)
          #!/usr/bin/env bash
          printf '%s\\n' '#{id}' >> "$PROBE_LOG"
          printf '%s\\n' '#{body}'
          exit #{code}
        SH
      end

      results = File.join(root, 'evidence')
      probe_log = File.join(root, 'probes.txt')
      _, _, result = Open3.capture3(
        {
          'PUBLIC_WEBSITE_CI_OUT_DIR' => results,
          'PUBLIC_WEBSITE_EVIDENCE_DIR' => File.join(root, 'external'),
          'PROBE_LOG' => probe_log,
        },
        'bash', File.join(scripts, 'public_website_ci_gate.sh'), 'live',
        chdir: root
      )
      refute result.success?
      assert_equal %w[static live audit], File.readlines(probe_log, chomp: true)
      completion = JSON.parse(File.read(File.join(results, 'public-completion-gate.json')))
      assert_equal 'fail', completion.fetch('status')
      assert_equal true, completion.dig('code_checks', 'static_quality_gate')
      assert_equal false, completion.dig('code_checks', 'live_quality_gate')
      assert_equal false, completion.dig('code_checks', 'live_audit_evidence')
      live = JSON.parse(File.read(File.join(results, 'public-live-gate.json')))
      assert_equal 1, live.dig('component_error', 'exit_status')
      audit = JSON.parse(File.read(File.join(results, 'public-live-audit-evidence.json')))
      assert_equal 'fail', audit.fetch('status')
      assert_equal 3, audit.dig('component_error', 'exit_status')
    end
  end
end
