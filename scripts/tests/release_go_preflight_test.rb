# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

class ReleaseGoPreflightTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @root = Dir.mktmpdir('collect-release-preflight-')
    FileUtils.mkdir_p(File.join(@root, 'scripts'))
    FileUtils.cp(File.join(ROOT, 'scripts/release_go_preflight.sh'), File.join(@root, 'scripts/release_go_preflight.sh'))
    File.write(File.join(@root, 'scripts/release_approval_evidence_gate.sh'), <<~'SH')
      #!/bin/bash
      exit "${TEST_APPROVAL_EXIT:-0}"
    SH
    File.write(File.join(@root, 'scripts/release_status.sh'), <<~'SH')
      #!/bin/bash
      printf '{"decision":"%s","blocker_keys":%s}\n' "${TEST_DECISION:-GO}" "${TEST_BLOCKERS:-[]}"
    SH
    Dir[File.join(@root, 'scripts', '*.sh')].each { |path| File.chmod(0o755, path) }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def preflight(env = {})
    Open3.capture3(env, File.join(@root, 'scripts/release_go_preflight.sh'))
  end

  def test_go_requires_approved_evidence_and_empty_blockers
    _stdout, _stderr, status = preflight
    assert status.success?
  end

  def test_no_go_decision_blocks_even_when_status_command_exits_zero
    _stdout, stderr, status = preflight('TEST_DECISION' => 'NO-GO')
    refute status.success?
    assert_includes stderr, 'Current release decision is not GO'
  end

  def test_nonempty_blockers_block_even_with_go_decision
    _stdout, _stderr, status = preflight('TEST_BLOCKERS' => '["provider"]')
    refute status.success?
  end

  def test_missing_approval_blocks
    _stdout, stderr, status = preflight('TEST_APPROVAL_EXIT' => '99')
    refute status.success?
    assert_includes stderr, 'approval evidence is incomplete'
  end
end
