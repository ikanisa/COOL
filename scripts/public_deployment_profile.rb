# frozen_string_literal: true

require "json"
require "open3"

# Public URL selection uses the same canonical, hash-checked deployment profile
# as the API and clients. This module reads no provider/database credentials.
module CollectPublicDeployment
  PUBLIC_ORIGIN = "https://collect.ikanisa.com"
  DELETION_PATH = "/privacy/account-deletion"
  DEFAULT_URLS = {
    "public_origin" => PUBLIC_ORIGIN,
    "account_deletion_url" => "https://api.collect.ikanisa.com#{DELETION_PATH}".freeze
  }.freeze
  PROFILE_KEY = "COLLECT_DEPLOYMENT_PROFILE"
  DIGEST_KEY = "COLLECT_DEPLOYMENT_PROFILE_SHA256"
  VALIDATOR_ENV = [PROFILE_KEY, DIGEST_KEY, "APP_ENVIRONMENT", "PATH"].freeze
  PRODUCTION_API_ORIGINS = [
    PUBLIC_ORIGIN, "https://admin.collect.ikanisa.com", "https://platform-admin.collect.ikanisa.com"
  ].freeze
  QUALIFICATION_API_ORIGINS = ["https://admin-supabase-qa.collect.ikanisa.com"].freeze

  VALIDATE_PROFILE = <<~PYTHON.freeze
    import os
    from scripts.supabase.deployment_profile import canonical_profile, resolve_profile
    env = os.environ
    print(canonical_profile(resolve_profile(env, qualification=env.get("APP_ENVIRONMENT") == "qualification")))
  PYTHON

  def self.resolve(root, env = ENV)
    return DEFAULT_URLS unless env.key?(PROFILE_KEY) || env.key?(DIGEST_KEY)

    stdout, _stderr, status = Open3.capture3(
      env.slice(*VALIDATOR_ENV), "python3", "-B", "-c", VALIDATE_PROFILE, chdir: root, unsetenv_others: true
    )
    invalid = "A valid matching public deployment profile is required"
    raise ArgumentError, invalid unless status.success?

    profile = JSON.parse(stdout)
    environment = profile.fetch("environment")
    public_origin = profile.fetch("public_origin")
    api_origin = profile.fetch("member_api_origin")
    allowed_origins = environment == "qualification" ? QUALIFICATION_API_ORIGINS : PRODUCTION_API_ORIGINS
    unless env.fetch("APP_ENVIRONMENT", environment) == environment &&
           env.fetch("APP_PUBLIC_URL", public_origin) == public_origin &&
           public_origin == PUBLIC_ORIGIN && allowed_origins.include?(api_origin)
      raise ArgumentError, invalid
    end

    {"public_origin" => public_origin,
     "account_deletion_url" => api_origin + DELETION_PATH,
     "deployment_profile" => profile,
     "deployment_profile_sha256" => env.fetch(DIGEST_KEY)}.freeze
  end
end
