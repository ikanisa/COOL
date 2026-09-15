# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'rbconfig'
require_relative '../qa/fullstack_database'

class FullstackDatabaseTest < Minitest::Test
  def setup
    @container = {
      'Name' => "/#{FullstackDatabase::CONTAINER}", 'Id' => 'synthetic-container-id',
      'Created' => '2026-09-14T16:30:00Z', 'Image' => 'sha256:synthetic-fixture',
      'State' => { 'Running' => true },
      'Config' => {
        'Image' => FullstackDatabase::IMAGE,
        'Labels' => {
          'com.supabase.cli.project' => FullstackDatabase::PROJECT,
          'com.docker.compose.project' => FullstackDatabase::PROJECT,
          'com.supabase.cli.workdir' => FullstackDatabase::WORKDIR
        }
      },
      'NetworkSettings' => { 'Networks' => { FullstackDatabase::NETWORK => {} } },
      'Mounts' => [{ 'RW' => true, 'Type' => 'volume', 'Name' => FullstackDatabase::CONTAINER,
                     'Destination' => '/var/lib/postgresql/data' }]
    }
    @network = { 'Name' => FullstackDatabase::NETWORK, 'Internal' => true,
                 'Labels' => { 'collect.qa.task' => FullstackDatabase::TASK } }
  end

  def validate(endpoint = 'unix:///synthetic/docker.sock')
    FullstackDatabase.validate!(@container, @network, endpoint)
  end

  def test_accepts_only_owned_isolated_target_and_returns_non_secret_provenance
    result = validate
    assert_equal FullstackDatabase::CONTAINER, result[:container]
    assert_equal true, result[:network_internal]
    refute result.key?(:credentials)
  end

  def test_rejects_remote_docker
    %w[tcp://127.0.0.1:2375 ssh://remote unix://].each do |endpoint|
      assert_raises(RuntimeError) { validate(endpoint) }
    end
  end

  def test_rejects_legacy_container_even_when_running
    @container['Name'] = '/supabase_db_collect'
    assert_raises(RuntimeError) { validate }
  end

  def test_rejects_mismatched_checkout_label
    @container['Config']['Labels']['com.supabase.cli.workdir'] = '/old-checkout'
    assert_raises(RuntimeError) { validate }
  end

  def test_rejects_ordinary_or_additional_networks
    @network['Internal'] = false
    assert_raises(RuntimeError) { validate }
    @network['Internal'] = true
    @container['NetworkSettings']['Networks']['bootstrap'] = {}
    assert_raises(RuntimeError) { validate }
  end

  def test_rejects_unowned_network
    @network['Labels'].clear
    assert_raises(RuntimeError) { validate }
  end

  def test_rejects_external_writable_mount
    @container['Mounts'] << { 'RW' => true, 'Type' => 'bind', 'Destination' => '/other' }
    assert_raises(RuntimeError) { validate }
  end

  def test_rejects_stopped_target_and_unexpected_image
    @container['State']['Running'] = false
    assert_raises(RuntimeError) { validate }
    @container['State']['Running'] = true
    @container['Config']['Image'] = 'postgres:latest'
    assert_raises(RuntimeError) { validate }
  end

  def test_stopped_inspection_is_explicit_and_does_not_relax_ownership
    @container['State'] = { 'Running' => false, 'Status' => 'exited' }
    assert_raises(RuntimeError) { validate }
    result = FullstackDatabase.validate!(@container, @network, 'unix:///synthetic/docker.sock', allow_stopped: true)
    assert_equal false, result[:observed_running]
    assert_equal 'exited', result[:observed_state]
    @network['Internal'] = false
    assert_raises(RuntimeError) do
      FullstackDatabase.validate!(@container, @network, 'unix:///synthetic/docker.sock', allow_stopped: true)
    end
  end

  def test_rejects_paused_restarting_dead_and_nonterminal_stopped_states
    %w[Paused Restarting Dead].each do |flag|
      @container['State'] = { 'Running' => true, flag => true }
      assert_raises(RuntimeError) { validate }
    end
    %w[created restarting removing dead].each do |state|
      @container['State'] = { 'Running' => false, 'Status' => state }
      assert_raises(RuntimeError) do
        FullstackDatabase.validate!(@container, @network, 'unix:///synthetic/docker.sock', allow_stopped: true)
      end
    end
  end
end

# A disposable executable stands in for the CLI; these tests never contact Docker.
class FullstackDatabaseCommandTest < Minitest::Test
  def with_cli(body)
    Dir.mktmpdir('collect-qa-cli-test-') do |directory|
      cli = File.join(directory, 'docker')
      File.write(cli, "#!#{RbConfig.ruby}\n$stdout.sync = $stderr.sync = true\n#{body}\n")
      File.chmod(0o700, cli)
      previous = ENV['PATH']
      ENV['PATH'] = "#{directory}:#{previous}"
      begin
        yield
      ensure
        ENV['PATH'] = previous
      end
    end
  end

  def assert_bounded_timeout(body, input: nil)
    with_cli(body) do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      error = assert_raises(FullstackDatabase::CommandTimeout) do
        FullstackDatabase.docker('synthetic', input: input, timeout: 2)
      end
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      assert_operator elapsed, :<, 7
      assert_equal 2, error.seconds
      assert_match(/server-side outcome is unverified/, error.message)
      yield error if block_given?
    end
  end

  def test_transports_input_arguments_both_streams_and_exit_status
    with_cli('puts ARGV.join("|"); puts STDIN.read; warn "diagnostic"; exit 7') do
      out, err, status = FullstackDatabase.docker('first', 'two words', input: 'synthetic payload', timeout: 2)
      assert_equal "first|two words\nsynthetic payload\n", out
      assert_equal "diagnostic\n", err
      assert_equal 7, status.exitstatus
      refute status.success?
    end
  end

  def test_success_and_capture_failures_are_distinct
    with_cli('puts "inspection"') do
      assert_equal "inspection\n", FullstackDatabase.capture('inspect')
    end
    with_cli('warn "fixture failure"; exit 4') do
      error = assert_raises(RuntimeError) { FullstackDatabase.capture('inspect') }
      assert_match(/fixture failure/, error.message)
    end
  end

  def test_timeout_preserves_partial_streams
    assert_bounded_timeout('puts "started"; warn "waiting"; sleep 30') do |error|
      assert_equal "started\n", error.output
      assert_equal "waiting\n", error.error
    end
  end

  def test_timeout_covers_a_blocked_input_writer
    assert_bounded_timeout('puts "input unread"; sleep 30', input: 'x' * (2 * 1024 * 1024)) do |error|
      assert_equal "input unread\n", error.output
    end
  end

  def test_open_descendant_stream_cannot_turn_parent_exit_into_success
    assert_bounded_timeout('fork { sleep 30 }; puts "parent finished"; exit 0') do |error|
      assert_equal "parent finished\n", error.output
    end
  end

  def test_client_ignoring_term_is_still_bounded
    assert_bounded_timeout('trap("TERM") {}; puts "ready"; sleep 30') do |error|
      assert_equal "ready\n", error.output
    end
  end

  def test_rejects_invalid_timeout_before_spawning
    [0, -1, Float::INFINITY, Float::NAN, '2', nil].each do |timeout|
      assert_raises(ArgumentError) { FullstackDatabase.docker('synthetic', timeout: timeout) }
    end
  end
end
