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
    FileUtils.cp(File.join(ROOT, 'scripts/release_go_preflight.sh'), scripts)
    FileUtils.mkdir_p(File.join(scripts, 'qa'))
    FileUtils.cp(File.join(ROOT, 'scripts/qa/release_evidence.py'), File.join(scripts, 'qa'))
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
    File.write(File.join(scripts, 'cloudflare_platform_acceptance_gate.sh'), '#!/bin/bash' + "\n" + 'exit "${TEST_PLATFORM_EXIT:-0}"' + "\n")
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

  def test_current_supabase_pending_cannot_report_go_even_when_legacy_passes
    result = status('TEST_PLATFORM_EXIT' => '0')
    assert_equal 'NO-GO', result.fetch('decision')
    assert_equal ['current_supabase_hosted_acceptance_pending'], result.fetch('blocker_keys')
    assert_equal '0', result.fetch('evidence_flags').fetch('platform_acceptance')
    refute_includes result.fetch('blocker_keys'), 'cloudflare_platform_hosted_acceptance'
  end

  def test_historical_acceptance_is_not_called_or_required
    marker = File.join(@root, 'historical-probe-called')
    File.write(File.join(@root, 'scripts/cloudflare_platform_acceptance_gate.sh'),
               "#!/bin/bash\nprintf called > '#{marker}'\nexit 2\n")
    result = status
    refute File.exist?(marker)
    assert_equal ['current_supabase_hosted_acceptance_pending'], result.fetch('blocker_keys')
    File.delete(File.join(@root, 'scripts/cloudflare_platform_acceptance_gate.sh'))
    assert_equal result.fetch('blocker_keys'), status.fetch('blocker_keys')
  end

  def test_missing_current_reader_cannot_report_go
    File.delete(File.join(@root, 'scripts/qa/release_evidence.py'))
    result = status
    assert_equal 'NO-GO', result.fetch('decision')
    assert_includes result.fetch('blocker_keys'), 'current_supabase_hosted_acceptance_pending'
  end

  def test_erroring_current_reader_cannot_report_go
    File.write(File.join(@root, 'scripts/qa/release_evidence.py'), 'raise SystemExit(2)')
    result = status
    assert_equal 'NO-GO', result.fetch('decision')
    assert_includes result.fetch('blocker_keys'), 'current_supabase_hosted_acceptance_pending'
  end

  def test_actual_current_pending_status_blocks_copied_preflight
    out, err, code = Open3.capture3(
      { 'ADMIN_PWA_LIVE_URL' => 'https://example.invalid' },
      File.join(@root, 'scripts/release_go_preflight.sh')
    )
    refute code.success?, out
    assert_includes err, 'Current release decision is not GO'
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
