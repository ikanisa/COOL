require 'minitest/autorun'
require_relative '../audits/collect_encrypted_database_backup'

class CollectEncryptedDatabaseBackupTest < Minitest::Test
  def test_pgpass_escapes_colons_and_backslashes
    slash = 92.chr
    assert_equal "a#{slash}:b#{slash}#{slash}c", pgpass_field("a:b#{slash}c")
    ["a\nb", "a\rb", "a\0b"].each { |value| assert_raises(RuntimeError) { pgpass_field(value) } }
  end

  def test_configuration_keeps_both_address_families
    config = { 'dbAllowedCidrs' => ['192.0.2.5/32'], 'dbAllowedCidrsV6' => ['2001:db8::/64'] }
    assert_equal config, configuration({ 'config' => config })
    assert_raises(RuntimeError) { configuration({ 'config' => { 'dbAllowedCidrs' => [] } }) }
  end

  def test_client_errors_are_classified_without_credentials
    assert_equal 'database_password_authentication_failed', failure_class('FATAL: password authentication failed for user synthetic')
    assert_equal 'tls_certificate_validation_failed', failure_class('SSL error: certificate verify failed')
    assert_equal 'database_client_failed_see_encrypted_log', failure_class('synthetic private detail')
  end

  def test_source_has_narrow_write_and_backup_guards
    source = File.read(File.expand_path('../audits/collect_encrypted_database_backup.rb', __dir__))
    assert_includes source, "APPROVED_IP = '129.222.149.205'"
    assert_includes source, "may_have_added_rule = true # Set BEFORE"
    assert_includes source, "current.fetch('dbAllowedCidrs') - [cidr]"
    assert_includes source, 'default_transaction_read_only=on'
    assert_includes source, 'PGSSLMODE=verify-full'
    assert_includes source, "vault('readonly', identifier)"
    refute_match(/--no-owner|--no-privileges|--exclude-schema|db push|apply_migration/, source)
  end
end
