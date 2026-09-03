require 'minitest/autorun'
require_relative '../audits/collect_backup_network_probe'

class CollectBackupNetworkProbeTest < Minitest::Test
  REF = CollectBackupNetworkProbe::REF

  def endpoint(host = "db.#{REF}.supabase.co", user = 'postgres', port = 5432, database = 'postgres')
    "postgresql://#{user}:synthetic-secret@#{host}:#{port}/#{database}"
  end

  def test_exact_direct_project
    assert_equal "db.#{REF}.supabase.co", CollectBackupNetworkProbe.database_endpoint(endpoint).host
  end

  def test_session_pooler_needs_exact_project_user
    assert_equal 5432, CollectBackupNetworkProbe.database_endpoint(
      endpoint('aws-0-us-east-2.pooler.supabase.com', "postgres.#{REF}")).port
    assert_raises(RuntimeError) { CollectBackupNetworkProbe.database_endpoint(endpoint('aws-0-us-east-2.pooler.supabase.com')) }
    assert_raises(RuntimeError) { CollectBackupNetworkProbe.database_endpoint(endpoint('aws-0-us-east-2.pooler.supabase.com', "postgres.#{REF}-other")) }
  end

  def test_transaction_pooler_and_wrong_database_refused
    assert_raises(RuntimeError) { CollectBackupNetworkProbe.database_endpoint(endpoint('aws-0-us-east-2.pooler.supabase.com', "postgres.#{REF}", 6543)) }
    assert_raises(RuntimeError) { CollectBackupNetworkProbe.database_endpoint(endpoint("db.#{REF}.supabase.co", 'postgres', 5432, 'other')) }
  end

  def test_lookalike_hosts_refused
    ["db.#{REF}-other.supabase.co", "db.#{REF}.supabase.co.attacker.test", "#{REF}.example.test"].each do |host|
      assert_raises(RuntimeError) { CollectBackupNetworkProbe.database_endpoint(endpoint(host)) }
    end
  end

  def test_invalid_endpoint_withholds_value
    error = assert_raises(RuntimeError) { CollectBackupNetworkProbe.database_endpoint('postgresql://synthetic-secret with spaces') }
    refute_includes error.message, 'synthetic-secret'
    assert_raises(RuntimeError) { CollectBackupNetworkProbe.database_endpoint('https://example.test') }
  end

  def test_ipv4_explicit_match_and_nonmatch
    network = { 'config' => { 'dbAllowedCidrs' => ['192.0.2.5/32'], 'dbAllowedCidrsV6' => [] } }
    assert CollectBackupNetworkProbe.explicitly_allowed?('192.0.2.5', network)
    refute CollectBackupNetworkProbe.explicitly_allowed?('192.0.2.6', network)
  end

  def test_ipv6_uses_ipv6_rules
    network = { 'config' => { 'dbAllowedCidrs' => [], 'dbAllowedCidrsV6' => ['2001:db8::/64'] } }
    assert CollectBackupNetworkProbe.explicitly_allowed?('2001:db8::5', network)
    refute CollectBackupNetworkProbe.explicitly_allowed?('192.0.2.5', network)
  end

  def test_empty_missing_invalid_rules_fail_closed
    refute CollectBackupNetworkProbe.explicitly_allowed?('192.0.2.5', { 'config' => { 'dbAllowedCidrs' => [] } })
    assert_raises(KeyError) { CollectBackupNetworkProbe.explicitly_allowed?('192.0.2.5', {}) }
    assert_raises(RuntimeError) { CollectBackupNetworkProbe.explicitly_allowed?('192.0.2.5', { 'config' => { 'dbAllowedCidrs' => nil } }) }
    assert_raises(IPAddr::InvalidAddressError) { CollectBackupNetworkProbe.explicitly_allowed?('192.0.2.5', { 'config' => { 'dbAllowedCidrs' => ['invalid'] } }) }
  end

  def test_runtime_has_no_network_mutation_or_record_export
    source = File.read(File.expand_path('../audits/collect_backup_network_probe.rb', __dir__))
    assert_includes source, 'read_only: true'
    assert_includes source, 'STDIN.noecho'
    assert_includes source, 'File::EXCL, 0o600'
    refute_match(/Net::HTTP::(?:Patch|Put|Delete)|pg_dump|db push|select \*/i, source)
  end
end
