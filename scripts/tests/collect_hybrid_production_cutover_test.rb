require 'minitest/autorun'
require_relative '../audits/collect_hybrid_production_cutover'

class CollectHybridProductionCutoverTest < Minitest::Test
  def test_manifest_is_exact_rehearsed_seven_file_set
    entries = CollectHybridProductionCutover.manifest
    CollectHybridProductionCutover.rehearsal!(entries)
    assert_equal 7, entries.length
    assert_equal CollectHybridProductionCutover::VERSIONS,
      entries.map { |entry| entry.fetch('version') }
    assert entries.all? { |entry| Digest::SHA256.hexdigest(entry.fetch('content')) == entry.fetch('sha256') }
  end

  def test_transaction_has_one_outer_commit_and_exact_history_guard
    entries = CollectHybridProductionCutover.manifest
    remote = (1..CollectHybridProductionCutover::BASELINE_COUNT).map do |index|
      { 'version' => format('%014d', index), 'name' => "migration_#{index}" }
    end
    sql = CollectHybridProductionCutover.transaction(entries, remote)
    assert_match(/\ABEGIN;/, sql)
    assert_match(/pg_try_advisory_xact_lock\(20260903, 84000\)/, sql)
    assert_equal 1, sql.scan(/^COMMIT;$/).length
    assert_equal 7, sql.scan(/INSERT INTO supabase_migrations\.schema_migrations/).length
  end

  def test_disabled_rollout_flags_are_complete
    assert_equal %w[
      hybrid_member_onboarding
      hybrid_direct_ussd_allocation
      native_sms_attestation_enforcement
      hybrid_sms_notifications
      hybrid_verified_account_claim
    ], CollectHybridProductionCutover::DISABLED_FLAGS
  end
end
