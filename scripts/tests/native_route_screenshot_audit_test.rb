require 'minitest/autorun'
require 'tmpdir'
require_relative '../verify_native_route_screenshots'

class NativeRouteScreenshotAuditTest < Minitest::Test
  def audit(images)
    Dir.mktmpdir('collect-native-captures-') do |directory|
      paths = images.map do |name, content|
        path = File.join(directory, "mobile_route_#{name}.png")
        File.binwrite(path, content)
        path
      end
      NativeRouteScreenshotAudit.evaluate(paths)
    end
  end

  def test_declared_aliases_can_share_a_capture
    result = audit('home' => 'home', 'app-share-entry' => 'home', 'groups' => 'groups')
    assert result.fetch('accepted')
    assert_equal 2, result.fetch('minimum_distinct_destinations')
  end

  def test_a_wrong_screen_is_rejected_even_when_overall_diversity_is_high
    result = audit('home' => 'wrong', 'groups' => 'wrong', 'auth' => 'auth', 'profile-edit' => 'profile')
    refute result.fetch('accepted')
    assert_equal [%w[groups home]], result.fetch('unexpected_duplicate_groups')
  end

  def test_momo_and_bank_captures_cannot_be_interchanged
    refute audit('public-buri-momo' => 'bank', 'diaspora-contribution' => 'bank').fetch('accepted')
    assert audit('public-buri-momo' => 'momo', 'diaspora-public-buri-momo' => 'momo').fetch('accepted')
  end

  def test_empty_evidence_cannot_pass
    refute NativeRouteScreenshotAudit.evaluate([]).fetch('accepted')
  end
end
