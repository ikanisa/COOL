# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'rbconfig'
require_relative '../qa/bounded_git_metadata'

class BoundedGitMetadataTest < Minitest::Test
  def capture(program, **options)
    Dir.mktmpdir('collect-git-metadata-') do |directory|
      BoundedGitMetadata.capture([RbConfig.ruby, '-e', program], root: directory,
                                 seconds: options.fetch(:seconds, 1),
                                 output_limit: options.fetch(:output_limit, 262_144))
    end
  end

  def test_completed_output_and_nonzero_exit_are_distinct
    result = capture('STDOUT.write(" M known-source.rb\n")')
    assert result['success']
    assert_equal " M known-source.rb\n", result['output']
    failed = capture('exit 1')
    refute failed['success']
    assert_equal 'command_failed', failed['error']
  end

  def test_deadline_returns_without_waiting_for_a_blocked_command
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = capture('sleep 30', seconds: 0.05)
    refute result['success']
    assert_equal 'deadline', result['error']
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
  end

  def test_output_growth_is_bounded_and_cannot_be_reported_as_clean
    result = capture('loop { STDOUT.write("x" * 8192); STDOUT.flush }', output_limit: 1024)
    refute result['success']
    assert_equal 'output_limit', result['error']
    assert_operator result['output'].bytesize, :<=, 9216
  end
end
