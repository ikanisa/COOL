# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

class ReleaseStatusFailClosedTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @root = Dir.mktmpdir('collect-release-status-')
    scripts = File.join(@root, 'scripts')
    FileUtils.mkdir_p(scripts)
    FileUtils.cp(File.join(ROOT, 'scripts/release_status.sh'), scripts)
    File.write(File.join(scripts, 'release_approval_evidence_gate.sh'), <<~'SH')
      #!/bin/bash
      printf '%s\n' '{"approvals":{"product_signoff":{"approved":true},"android_sms_access_uat":{"approved":true},"release_owner_signoff":{"approved":true}}}'
      exit "${TEST_APPROVAL_EXIT:-0}"
    SH
    File.write(File.join(scripts, 'flutter_mobile_release_gate.sh'), <<~'SH')
      #!/bin/bash
      printf '%s\n' '{"blocker_keys":[]}'
      exit "${TEST_MOBILE_EXIT:-0}"
    SH
    File.write(File.join(scripts, 'admin_pwa_live_gate.sh'), "#!/bin/bash\nexit 0\n")
    File.write(File.join(scripts, 'collect_linked_uat.sh'), "#!/bin/bash\nexit 0\n")
    Dir[File.join(scripts, '*.sh')].each { |path| File.chmod(0o755, path) }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def status(env = {})
    out, err, code = Open3.capture3(
      { 'ADMIN_PWA_LIVE_URL' => 'https://example.invalid' }.merge(env),
      File.join(@root, 'scripts/release_status.sh'), '--json'
    )
    assert code.success?, err
    JSON.parse(out)
  end

  def test_all_required_probes_passing_can_report_go
    result = status
    assert_equal 'GO', result.fetch('decision')
    assert_empty result.fetch('blocker_keys')
  end

  def test_blocked_approval_probe_cannot_report_go
    result = status('TEST_APPROVAL_EXIT' => '99')
    assert_equal 'NO-GO', result.fetch('decision')
    assert_includes result.fetch('blocker_keys'), 'release_approval_evidence_gate'
  end

  def test_erroring_mobile_probe_cannot_report_go
    result = status('TEST_MOBILE_EXIT' => '2')
    assert_equal 'NO-GO', result.fetch('decision')
    assert_includes result.fetch('blocker_keys'), 'flutter_mobile_release_gate'
  end

  def test_blocked_mobile_probe_with_unknown_keys_cannot_report_go
    result = status('TEST_MOBILE_EXIT' => '99')
    assert_equal 'NO-GO', result.fetch('decision')
    assert_includes result.fetch('blocker_keys'), 'flutter_mobile_release_gate'
  end
end
