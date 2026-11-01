# frozen_string_literal: true

require "json"
require "open3"

# Public URL selection uses the same canonical, hash-checked deployment profile
# as the API and clients. This module reads no provider/database credentials.
module CollectPublicDeployment
  def self.resolve(root, env = ENV.to_h)
    explicit = env.key?("COLLECT_DEPLOYMENT_PROFILE") || env.key?("COLLECT_DEPLOYMENT_PROFILE_SHA256")
    return {"public_origin" => "https://collect.ikanisa.com",
            "account_deletion_url" => "https://api.collect.ikanisa.com/privacy/account-deletion"}.freeze unless explicit

    code = <<~PYTHON
      import json, os
      from scripts.supabase.deployment_profile import resolve_profile
      env = dict(os.environ)
      profile = resolve_profile(env, qualification=env.get('APP_ENVIRONMENT') == 'qualification')
      if env.get('APP_ENVIRONMENT', profile['environment']) != profile['environment']:
          raise ValueError('Public environment differs from the deployment profile')
      if env.get('APP_PUBLIC_URL', profile['public_origin']) != profile['public_origin']:
          raise ValueError('Public URL differs from the deployment profile')
      print(json.dumps(profile, sort_keys=True, separators=(',', ':')))
    PYTHON
    # Capture both streams. A failed profile never falls back to production URLs
    # and no caller-provided value is copied into error output.
    stdout, _stderr, status = Open3.capture3(env, "python3", "-c", code, chdir: root, unsetenv_others: true)
    raise ArgumentError, "A valid matching public deployment profile is required" unless status.success?
    profile = JSON.parse(stdout)
    {"public_origin" => profile.fetch("public_origin"),
     "account_deletion_url" => profile.fetch("member_api_origin") + "/privacy/account-deletion",
     "deployment_profile" => profile,
     "deployment_profile_sha256" => env.fetch("COLLECT_DEPLOYMENT_PROFILE_SHA256")}.freeze
  end
end
