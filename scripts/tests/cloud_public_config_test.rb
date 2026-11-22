# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "json"
require_relative "../public_deployment_profile"

class CloudPublicConfigTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  def profile_env
    profile = {"format" => "collect.deployment.v1", "id" => "collect-test", "mode" => "managed",
               "environment" => "qualification", "supabase_origin" => "https://rrlduytparvsjfmegalh.supabase.co",
               "member_api_origin" => "https://admin-supabase-qa.collect.ikanisa.com", "admin_origin" => "https://admin-supabase-qa.collect.ikanisa.com",
               "public_origin" => "https://collect.ikanisa.com", "google_callback_origin" => "https://admin-supabase-qa.collect.ikanisa.com"}
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
    assert_equal "https://collect.ikanisa.com", actual.fetch("public_origin")
    assert_equal "https://admin-supabase-qa.collect.ikanisa.com/privacy/account-deletion", actual.fetch("account_deletion_url")
    assert_equal "qualification", actual.fetch("deployment_profile").fetch("environment")
  end
  def test_mismatch_never_falls_back_to_production
    [{"COLLECT_DEPLOYMENT_PROFILE_SHA256" => "0" * 64}, {"APP_ENVIRONMENT" => "production"},
     {"APP_PUBLIC_URL" => "https://other.collect.example"}, {"COLLECT_DEPLOYMENT_PROFILE" => "{}"}].each do |override|
      assert_raises(ArgumentError) { CollectPublicDeployment.resolve(ROOT, profile_env.merge(override)) }
    end
  end
  def test_profile_validator_receives_only_public_inputs
    env = profile_env.merge("APP_PUBLIC_URL" => "https://collect.ikanisa.com",
                            "PRIVATE_FIXTURE_KEY" => "not-for-the-validator", "PYTHONPATH" => "/synthetic/override")
    capture = Open3.method(:capture3)
    inspect_environment = lambda do |child_env, *command, **options|
      assert_equal profile_env, child_env
      assert_equal true, options.fetch(:unsetenv_others)
      capture.call(child_env, *command, **options)
    end
    Open3.stub(:capture3, inspect_environment) { CollectPublicDeployment.resolve(ROOT, env) }
  end
end
