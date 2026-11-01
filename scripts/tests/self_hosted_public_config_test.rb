# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "json"
require_relative "../public_deployment_profile"

class SelfHostedPublicConfigTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  def profile_env
    profile = {"format" => "collect.deployment.v1", "id" => "collect-test", "mode" => "self_hosted",
               "environment" => "qualification", "supabase_origin" => "https://supabase.collect.example",
               "member_api_origin" => "https://api.collect.example", "admin_origin" => "https://admin.collect.example",
               "public_origin" => "https://collect.example", "google_callback_origin" => "https://admin.collect.example"}
    raw = JSON.generate(profile.sort.to_h)
    {"PATH" => ENV.fetch("PATH"), "APP_ENVIRONMENT" => "qualification", "COLLECT_DEPLOYMENT_PROFILE" => raw,
     "COLLECT_DEPLOYMENT_PROFILE_SHA256" => Digest::SHA256.hexdigest(raw)}
  end
  def test_legacy_urls_remain_reproducible
    actual = CollectPublicDeployment.resolve(ROOT, {})
    assert_equal "https://collect.ikanisa.com", actual.fetch("public_origin")
    assert_equal "https://api.collect.ikanisa.com/privacy/account-deletion", actual.fetch("account_deletion_url")
  end
  def test_public_and_privacy_urls_follow_the_verified_profile
    actual = CollectPublicDeployment.resolve(ROOT, profile_env)
    assert_equal "https://collect.example", actual.fetch("public_origin")
    assert_equal "https://api.collect.example/privacy/account-deletion", actual.fetch("account_deletion_url")
    assert_equal "qualification", actual.fetch("deployment_profile").fetch("environment")
  end
  def test_mismatch_never_falls_back_to_production
    [{"COLLECT_DEPLOYMENT_PROFILE_SHA256" => "0" * 64}, {"APP_ENVIRONMENT" => "production"},
     {"APP_PUBLIC_URL" => "https://other.collect.example"}, {"COLLECT_DEPLOYMENT_PROFILE" => "{}"}].each do |override|
      assert_raises(ArgumentError) { CollectPublicDeployment.resolve(ROOT, profile_env.merge(override)) }
    end
  end
end
