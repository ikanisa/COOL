# Only declared public Supabase runtime configuration enters application builds.
require 'json'
require 'io/console'

module CollectReleaseBuild
  ROOT = File.expand_path('../..', __dir__)
  TARGET = {
    'supabase_url' => 'https://rrlduytparvsjfmegalh.supabase.co',
    'supabase_api_url' => 'https://platform-admin.collect.ikanisa.com',
    'public_url' => 'https://collect.ikanisa.com',
    'admin_url' => 'https://platform-admin.collect.ikanisa.com'
  }.freeze

  def self.environment(configuration, target = 'admin')
    raise 'Expected admin, android or ios build' unless %w[admin android ios].include?(target)
    public_keys = if target == 'admin'
                    TARGET.keys + %w[supabase_publishable_key auth_captcha_site_key google_auth_enabled]
                  else
                    %w[deployment_profile deployment_profile_sha256 supabase_publishable_key
                       auth_captcha_site_key google_auth_enabled sms_auth_enabled
                       whatsapp_auth_enabled anonymous_auth_enabled]
                  end
    raise 'Expected public Supabase build configuration' unless configuration.is_a?(Hash) && (configuration.keys - public_keys).empty?
    key = configuration.fetch('supabase_publishable_key', '')
    site_key = configuration.fetch('auth_captcha_site_key', '')
    google = configuration.fetch('google_auth_enabled', 'false')
    raise 'Expected public Supabase publishable key' unless key.is_a?(String) && key.match?(/\Asb_publishable_[A-Za-z0-9_-]{10,300}\z/)
    raise 'Expected public Turnstile site key' unless site_key.is_a?(String) && site_key.match?(/\A[A-Za-z0-9_-]{10,200}\z/)
    raise 'Expected explicit Google feature flag' unless %w[true false].include?(google)
    common = {
      'COLLECT_SKIP_DOTENV' => '1', 'COLLECT_BACKEND' => 'supabase',
      'SUPABASE_PUBLISHABLE_KEY' => key,
      'AUTH_CAPTCHA_ENABLED' => 'true', 'AUTH_CAPTCHA_PROVIDER' => 'turnstile',
      'AUTH_CAPTCHA_SITE_KEY' => site_key, 'GOOGLE_AUTH_ENABLED' => google
    }
    if target == 'admin'
      TARGET.each do |name, expected|
        raise "Unexpected #{name}" unless configuration.fetch(name, expected) == expected
      end
      return common.merge('SUPABASE_URL' => TARGET.fetch('supabase_url'),
                          'SUPABASE_API_URL' => TARGET.fetch('supabase_api_url'),
                          'APP_PUBLIC_URL' => TARGET.fetch('public_url'),
                          'ADMIN_APP_URL' => TARGET.fetch('admin_url'))
    end

    raw = configuration['deployment_profile']
    digest = configuration['deployment_profile_sha256']
    raise 'Expected canonical public deployment profile and SHA256' unless raw.is_a?(String) &&
      !raw.empty? && raw.bytesize <= 8192 && digest.is_a?(String) && digest.match?(/\A[a-f0-9]{64}\z/)
    raise 'Expected SMS authentication enabled' unless configuration['sms_auth_enabled'] == 'true'
    whatsapp = configuration.fetch('whatsapp_auth_enabled', 'false')
    anonymous = configuration.fetch('anonymous_auth_enabled', 'false')
    raise 'Expected explicit authentication feature flags' unless [whatsapp, anonymous].all? { |value| %w[true false].include?(value) }
    begin
      profile = JSON.parse(raw)
    rescue JSON::ParserError
      raise ArgumentError, 'Expected canonical public deployment profile and SHA256', cause: nil
    end
    fields = %w[supabase_origin member_api_origin public_origin admin_origin]
    raise 'Expected public deployment origins' unless profile.is_a?(Hash) &&
      fields.all? { |name| profile[name].is_a?(String) && !profile[name].empty? }
    # The shared Python validator is authoritative for canonical JSON, hash,
    # self-hosted mode, production origins and candidate authentication. Passing
    # the exact public bytes avoids selecting a second, implicit target here.
    common.merge(
      'COLLECT_DEPLOYMENT_PROFILE' => raw, 'COLLECT_DEPLOYMENT_PROFILE_SHA256' => digest,
      'COLLECT_SMS_AUTH_ENABLED' => 'true', 'COLLECT_GOOGLE_AUTH_ENABLED' => google,
      'COLLECT_WHATSAPP_AUTH_ENABLED' => whatsapp, 'COLLECT_ANONYMOUS_AUTH_ENABLED' => anonymous,
      'SUPABASE_URL' => profile.fetch('supabase_origin'),
      'SUPABASE_API_URL' => profile.fetch('member_api_origin'),
      'COLLECT_API_URL' => profile.fetch('member_api_origin'),
      'SUPABASE_ADMIN_API_URL' => profile.fetch('admin_origin'),
      'SUPABASE_AUTH_ISSUER' => profile.fetch('supabase_origin') + '/auth/v1',
      'APP_PUBLIC_URL' => profile.fetch('public_origin'), 'ADMIN_APP_URL' => profile.fetch('admin_origin')
    )
  end

  def self.run(target='admin')
    raise 'Expected admin, android or ios build' unless %w[admin android ios].include?(target)
    STDOUT.sync = true
    if target == 'admin'
      puts 'Provide public Supabase build configuration JSON on stdin.'
    else
      puts 'Provide public native candidate JSON on stdin: deployment_profile (canonical JSON string), deployment_profile_sha256, supabase_publishable_key, auth_captcha_site_key, sms_auth_enabled ("true"), and optional google_auth_enabled, whatsapp_auth_enabled, anonymous_auth_enabled ("true" or "false").'
    end
    input = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
    begin
      configuration = JSON.parse(input.to_s)
    rescue JSON::ParserError
      raise ArgumentError, 'Expected public Supabase build configuration JSON', cause: nil
    end
    env = environment(configuration, target)
    script = {'admin'=>'admin_pwa_release_build.sh','android'=>'android_play_store_build.sh','ios'=>'ios_app_store_build.sh'}.fetch(target)
    raise "#{target} release build failed" unless system(env, 'bash', 'scripts/'+script, chdir: ROOT)
  ensure
    input&.clear
    configuration.clear if configuration.is_a?(Hash)
  end
end

CollectReleaseBuild.run(ARGV.fetch(0,'admin')) if $PROGRAM_NAME == __FILE__
