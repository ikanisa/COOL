require 'minitest/autorun'
require_relative '../audits/collect_hybrid_edge_cutover'

class CollectHybridEdgeCutoverTest < Minitest::Test
  def test_local_gate_and_preflight_are_exact
    CollectHybridEdgeCutover.local_gate!
    CollectHybridEdgeCutover.preflight_before!
    assert_equal 5, CollectHybridEdgeCutover::SLUGS.length
    assert_equal 3, CollectHybridEdgeCutover::EXPECTED_BEFORE.length
    assert_equal 2, CollectHybridEdgeCutover::NEW_SLUGS.length
  end

  def test_target_jwt_contract_is_explicit
    assert_equal({
      'verify-play-integrity' => true,
      'ingest-payment-sms' => true,
      'parse-payment-sms' => false,
      'prepare-roster-import' => true,
      'collect-notification-operator' => true
    }, CollectHybridEdgeCutover::EXPECTED_JWT)
  end

  def test_all_rollout_flags_remain_off
    assert_equal %w[
      hybrid_member_onboarding
      hybrid_direct_ussd_allocation
      native_sms_attestation_enforcement
      hybrid_sms_notifications
      hybrid_verified_account_claim
    ], CollectHybridEdgeCutover::DISABLED_FLAGS
  end
end
