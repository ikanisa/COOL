# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'digest'

class ReleaseWorktreeReviewGateTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  REVIEW = {
    'RELEASE_WORKTREE_REVIEWED' => '1',
    'RELEASE_WORKTREE_REVIEW_NOTE' => 'Synthetic temporary-repository fixture only.',
    'RELEASE_WORKTREE_REVIEWER' => 'Synthetic Fixture Reviewer',
    'RELEASE_WORKTREE_REVIEWED_AT' => '2026-10-29T00:00:00Z',
    'RELEASE_WORKTREE_REVIEW_EVIDENCE' => 'synthetic-fixture-evidence'
  }.freeze

  def setup
    @fixture = Dir.mktmpdir('collect-worktree-review-')
    @root = File.join(@fixture, 'repo')
    @bin = File.join(@fixture, 'bin')
    FileUtils.mkdir_p([File.join(@root, 'scripts'), @bin])
    @script = File.join(@root, 'scripts/release_worktree_review_gate.sh')
    FileUtils.cp(File.join(ROOT, 'scripts/release_worktree_review_gate.sh'), @script)
    @git = executable('git')
    @environment = ENV.keys.grep(/\AGIT_/).to_h { |key| [key, nil] }.merge(
      'GIT_CONFIG_NOSYSTEM' => '1', 'GIT_CONFIG_GLOBAL' => File::NULL,
      'GIT_TERMINAL_PROMPT' => '0', 'GIT_ALLOW_PROTOCOL' => '',
      **REVIEW.keys.to_h { |key| [key, nil] }
    )
    git('init', '--quiet', '--initial-branch=main')
    git('config', 'user.name', 'Synthetic Fixture')
    git('config', 'user.email', 'fixture@example.test')
    %w[staged.txt worktree.txt old.txt].each { |name| File.write(File.join(@root, name), "base\n") }
    git('add', '.')
    git('-c', "core.hooksPath=#{File::NULL}", 'commit', '--quiet', '-m', 'Synthetic test fixture')
  end

  def teardown
    FileUtils.remove_entry(@fixture)
  end

  def executable(name)
    path = ENV.fetch('PATH').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
              .find { |candidate| File.file?(candidate) && File.executable?(candidate) }
    raise "Required test executable unavailable: #{name}" unless path

    path
  end

  def git(*args)
    output, error, status = Open3.capture3(@environment, @git, '-C', @root, *args)
    assert status.success?, error
    output.strip
  end

  def gate(environment = {})
    output, error, status = Open3.capture3(
      @environment.merge(environment), '/bin/bash', @script, '--json'
    )
    [JSON.parse(output), error, status]
  end

  def wrapper(command, body)
    path = File.join(@bin, 'git')
    File.write(path, <<~SH)
      #!/bin/bash
      for argument in "$@"; do
        if [[ "$argument" == "#{command}" ]]; then
          #{body}
        fi
      done
      exec "$TEST_REAL_GIT" "$@"
    SH
    File.chmod(0o755, path)
    { 'PATH' => @bin + File::PATH_SEPARATOR + ENV.fetch('PATH'), 'TEST_REAL_GIT' => @git }
  end

  def test_clean_repository_passes_without_mutating_head_or_index
    head = git('rev-parse', 'HEAD')
    index = File.binread(File.join(@root, '.git/index'))
    result, error, status = gate
    assert status.success?, error
    assert_equal 'pass', result.fetch('status')
    assert_equal false, result.fetch('dirty')
    assert_equal 0, result.fetch('changed_count')
    assert_empty result.fetch('changed_paths')
    assert_equal head, git('rev-parse', 'HEAD')
    assert_equal index, File.binread(File.join(@root, '.git/index'))
  end

  def test_real_corrupt_index_cannot_be_relabelled_clean_or_overridden_by_review
    File.binwrite(File.join(@root, '.git/index'), 'synthetic invalid index')
    [{}, REVIEW].each do |environment|
      result, _error, status = gate(environment)
      refute status.success?
      assert_equal 'blocked', result.fetch('status')
      assert_includes result.fetch('blocker_keys'), 'worktree_status_unavailable'
      assert_nil result.fetch('dirty')
      assert_nil result.fetch('changed_count')
      assert_nil result.fetch('changed_paths')
    end
  end

  def test_staged_and_unstaged_changes_keep_exact_status_and_require_review
    File.write(File.join(@root, 'staged.txt'), "staged change\n")
    git('add', 'staged.txt')
    File.write(File.join(@root, 'worktree.txt'), "unstaged change\n")
    result, _error, status = gate
    refute status.success?
    assert_equal true, result.fetch('dirty')
    assert_includes result.fetch('blocker_keys'), 'worktree_review'
    assert_equal [
      { 'status' => 'M ', 'path' => 'staged.txt' },
      { 'status' => ' M', 'path' => 'worktree.txt' }
    ], result.fetch('changed_paths')
  end

  def test_untracked_files_cannot_be_hidden_by_status_configuration
    git('config', 'status.showUntrackedFiles', 'no')
    File.write(File.join(@root, 'untracked.txt'), 'fixture')
    result, _error, status = gate
    refute status.success?
    assert_equal [{ 'status' => '??', 'path' => 'untracked.txt' }], result.fetch('changed_paths')
  end

  def test_nul_framing_preserves_newlines_spaces_and_rename_source
    renamed = " new\nname -> target.txt"
    git('mv', 'old.txt', renamed)
    untracked = "untracked\nname.txt"
    File.write(File.join(@root, untracked), 'fixture')
    result, _error, status = gate
    refute status.success?
    assert_equal 2, result.fetch('changed_count')
    assert_includes result.fetch('changed_paths'), {
      'status' => 'R ', 'path' => renamed, 'original_path' => 'old.txt'
    }
    assert_includes result.fetch('changed_paths'), { 'status' => '??', 'path' => untracked }
  end

  def test_existing_explicit_review_still_allows_a_known_dirty_tree
    File.write(File.join(@root, 'worktree.txt'), 'reviewed fixture change')
    result, error, status = gate(REVIEW)
    assert status.success?, error
    assert_equal 'pass', result.fetch('status')
    assert_equal true, result.fetch('dirty')
    assert_equal true, result.fetch('reviewed')
    assert_equal 1, result.fetch('changed_count')
  end

  def test_non_repository_root_fails_without_a_clean_status_claim
    FileUtils.mv(File.join(@root, '.git'), File.join(@fixture, 'saved-git'))
    result, _error, status = gate(REVIEW)
    refute status.success?
    assert_equal 'fail', result.fetch('status')
    assert_includes result.fetch('blocker_keys'), 'worktree_not_git'
    refute result.key?('dirty')
  end

  def test_missing_git_returns_a_sanitized_machine_readable_failure
    FileUtils.ln_s(RbConfig.ruby, File.join(@bin, 'ruby'))
    FileUtils.ln_s(executable('dirname'), File.join(@bin, 'dirname'))
    result, error, status = gate('PATH' => @bin)
    refute status.success?
    assert_equal 'fail', result.fetch('status')
    assert_includes result.fetch('blocker_keys'), 'worktree_git_unavailable'
    assert_empty error
  end

  def test_status_error_and_malformed_success_are_both_unknown_even_with_review
    [
      "printf 'sensitive fixture diagnostic' >&2; exit 128",
      "printf 'unframed status'; exit 0",
      "printf 'R  renamed\\0'; exit 0"
    ].each do |body|
      result, error, status = gate(wrapper('status', body).merge(REVIEW))
      refute status.success?
      assert_includes result.fetch('blocker_keys'), 'worktree_status_unavailable'
      assert_nil result.fetch('dirty')
      refute_includes JSON.generate(result) + error, 'sensitive fixture diagnostic'
    end
  end

  def test_unreadable_committed_head_is_not_a_release_identity
    result, _error, status = gate(wrapper('rev-parse', <<~SH).merge(REVIEW))
      if [[ "$*" == *"--short HEAD"* ]]; then
        exit 128
      fi
    SH
    refute status.success?
    assert_includes result.fetch('blocker_keys'), 'worktree_identity_unavailable'
  end

  def test_failed_configured_upstream_comparison_cannot_pass
    head = git('rev-parse', 'HEAD')
    git('config', 'remote.origin.url', 'https://example.invalid/no-network')
    git('config', 'remote.origin.fetch', '+refs/heads/*:refs/remotes/origin/*')
    git('update-ref', 'refs/remotes/origin/main', head)
    git('config', 'branch.main.remote', 'origin')
    git('config', 'branch.main.merge', 'refs/heads/main')
    clean, _error, clean_status = gate
    assert clean_status.success?
    assert_equal({ 'ahead' => 0, 'behind' => 0 }, clean.fetch('ahead_behind'))
    result, _error, status = gate(wrapper('rev-list', 'exit 128').merge(REVIEW))
    refute status.success?
    assert_includes result.fetch('blocker_keys'), 'worktree_upstream_unavailable'
    assert_nil result.fetch('ahead_behind')
  end
end
