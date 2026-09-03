require 'minitest/autorun'
require_relative '../audits/collect_auth_redirect_cutover'

class CollectAuthRedirectCutoverTest < Minitest::Test
  def test_exact_retired_baseline_requires_one_mutation
    result = CollectAuthRedirectCutover.plan(
      'site_url' => CollectAuthRedirectCutover::RETIRED_URL,
      'uri_allow_list' => CollectAuthRedirectCutover::RETIRED_URL,
    )
    assert_equal true, result.fetch('mutation_required')
  end

  def test_exact_target_is_idempotent
    result = CollectAuthRedirectCutover.plan(
      'site_url' => CollectAuthRedirectCutover::SITE_URL,
      'uri_allow_list' => CollectAuthRedirectCutover::TARGET_ALLOW_LIST,
    )
    assert_equal false, result.fetch('mutation_required')
  end

  def test_unreviewed_baseline_is_rejected
    error = assert_raises(RuntimeError) do
      CollectAuthRedirectCutover.plan(
        'site_url' => 'https://unexpected.example',
        'uri_allow_list' => 'https://unexpected.example',
      )
    end
    assert_match(/baseline changed/, error.message)
  end
end
