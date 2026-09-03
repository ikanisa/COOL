require 'minitest/autorun'
require_relative '../audits/collect_hybrid_privilege_cutover'

class CollectHybridPrivilegeCutoverTest < Minitest::Test
  def test_manifest_is_the_exact_rehearsed_privilege_migration
    entry = CollectHybridPrivilegeCutover.manifest
    CollectHybridPrivilegeCutover.rehearsal!(entry)
    assert_equal CollectHybridPrivilegeCutover::VERSION, entry.fetch('version')
    assert_equal CollectHybridPrivilegeCutover::NAME, entry.fetch('name')
    assert_equal CollectHybridPrivilegeCutover::SHA256, entry.fetch('sha256')
    assert_equal entry.fetch('sha256'), Digest::SHA256.hexdigest(entry.fetch('content'))
  end

  def test_transaction_has_one_commit_and_exact_119_history_guard
    entry = CollectHybridPrivilegeCutover.manifest
    remote = (1..CollectHybridPrivilegeCutover::BASELINE_COUNT).map do |index|
      { 'version' => format('%014d', index), 'name' => "migration_#{index}" }
    end
    sql = CollectHybridPrivilegeCutover.transaction(entry, remote)
    assert_match(/\ABEGIN;/, sql)
    assert_match(/pg_try_advisory_xact_lock\(20260903, 92500\)/, sql)
    assert_equal 1, sql.scan(/^COMMIT;$/).length
    assert_equal 1, sql.scan(/INSERT INTO supabase_migrations\.schema_migrations/).length
  end

  def test_disabled_rollout_flags_are_complete
    assert_equal %w[
      hybrid_member_onboarding
      hybrid_direct_ussd_allocation
      native_sms_attestation_enforcement
      hybrid_sms_notifications
      hybrid_verified_account_claim
    ], CollectHybridPrivilegeCutover::DISABLED_FLAGS
  end
end
