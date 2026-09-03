require 'minitest/autorun'
require 'tmpdir'
require_relative '../audits/collect_hosted_preflight'

class CollectHostedPreflightTest < Minitest::Test
  def with_migrations
    Dir.mktmpdir('collect-preflight-test-') do |directory|
      File.write(File.join(directory, '202609010001_first.sql'), 'select 1;')
      File.write(File.join(directory, '202609020001_second.sql'), 'select 2;')
      yield directory
    end
  end

  def test_pending_plan_and_hashes
    with_migrations do |directory|
      result = CollectHostedPreflight.plan([{ 'version' => '202609010001', 'name' => 'first' }], directory)
      assert_equal 1, result[:remote_count]
      assert_equal 2, result[:local_count]
      assert_empty result[:remote_only]
      assert_empty result[:history_holes]
      assert_empty result[:name_mismatches]
      assert_equal ['202609020001'], result[:pending].map { |row| row['version'] }
      assert_equal Digest::SHA256.hexdigest('select 2;'), result[:pending].first['sha256']
    end
  end

  def test_remote_drift_is_not_hidden
    with_migrations do |directory|
      result = CollectHostedPreflight.plan([
        { 'version' => '202609020001', 'name' => 'different' },
        { 'version' => '202609030001', 'name' => 'remote_only' }
      ], directory)
      assert_equal ['202609030001'], result[:remote_only]
      assert_equal ['202609020001'], result[:name_mismatches]
      assert_equal ['202609010001'], result[:history_holes].map { |row| row['version'] }
    end
  end

  def test_duplicate_history_fails_closed
    with_migrations do |directory|
      assert_raises(RuntimeError) do
        CollectHostedPreflight.plan([{ 'version' => '1' }, { 'version' => '1' }], directory)
      end
    end
  end

  def test_duplicate_local_versions_fail_closed
    with_migrations do |directory|
      File.write(File.join(directory, '202609010001_duplicate.sql'), 'select 3;')
      assert_raises(RuntimeError) { CollectHostedPreflight.plan([], directory) }
    end
  end

  def test_advisors_are_summarized_without_database_details
    data = { 'lints' => [
      { 'name' => 'rpc_warning', 'level' => 'WARN', 'detail' => 'private detail' },
      { 'name' => 'rpc_warning', 'level' => 'WARN' },
      { 'name' => 'unused_index', 'level' => 'INFO' }
    ] }
    summary = CollectHostedPreflight.advisor_summary(data)
    assert_equal({ 'WARN' => 2, 'INFO' => 1 }, summary[:by_level])
    assert_equal 2, summary[:findings].length
    refute_includes JSON.generate(summary), 'private detail'
  end

  def test_invalid_advisor_payload_does_not_become_clean
    assert_raises(KeyError) { CollectHostedPreflight.advisor_summary({}) }
    assert_raises(RuntimeError) { CollectHostedPreflight.advisor_summary({ 'lints' => nil }) }
  end

  def test_runtime_has_no_deployment_or_customer_export_route
    source = File.read(File.expand_path('../audits/collect_hosted_preflight.rb', __dir__))
    assert_includes source, 'begin read only;'
    assert_includes source, 'STDIN.noecho'
    assert_includes source, 'File::EXCL, 0o600'
    refute_match(/ENV\[|puts.*token|db push|apply_migration|create_user/, source)
  end
end
