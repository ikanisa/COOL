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

  def self.environment(configuration)
    public_keys = TARGET.keys + %w[supabase_publishable_key auth_captcha_site_key google_auth_enabled]
    raise 'Expected public Supabase build configuration' unless configuration.is_a?(Hash) && (configuration.keys - public_keys).empty?
    TARGET.each do |key, expected|
      raise "Unexpected #{key}" unless configuration.fetch(key, expected) == expected
    end
    key = configuration.fetch('supabase_publishable_key', '')
    site_key = configuration.fetch('auth_captcha_site_key', '')
    google = configuration.fetch('google_auth_enabled', 'false')
    raise 'Expected public Supabase publishable key' unless key.is_a?(String) && key.match?(/\Asb_publishable_[A-Za-z0-9_-]{10,300}\z/)
    raise 'Expected public Turnstile site key' unless site_key.is_a?(String) && site_key.match?(/\A[A-Za-z0-9_-]{10,200}\z/)
    raise 'Expected explicit Google feature flag' unless %w[true false].include?(google)
    {
      'COLLECT_SKIP_DOTENV' => '1', 'COLLECT_BACKEND' => 'supabase',
      'SUPABASE_URL' => TARGET.fetch('supabase_url'),
      'SUPABASE_API_URL' => TARGET.fetch('supabase_api_url'),
      'SUPABASE_PUBLISHABLE_KEY' => key,
      'AUTH_CAPTCHA_ENABLED' => 'true', 'AUTH_CAPTCHA_PROVIDER' => 'turnstile',
      'AUTH_CAPTCHA_SITE_KEY' => site_key, 'GOOGLE_AUTH_ENABLED' => google,
      'APP_PUBLIC_URL' => TARGET.fetch('public_url'),
      'ADMIN_APP_URL' => TARGET.fetch('admin_url')
    }
  end

  def self.run(target='admin')
    raise 'Expected admin, android or ios build' unless %w[admin android ios].include?(target)
    STDOUT.sync = true
    puts 'Provide public Supabase build configuration JSON on stdin.'
    input = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
    configuration = JSON.parse(input.to_s)
    env = environment(configuration)
    script = {'admin'=>'admin_pwa_release_build.sh','android'=>'android_play_store_build.sh','ios'=>'ios_app_store_build.sh'}.fetch(target)
    raise "#{target} release build failed" unless system(env, 'bash', 'scripts/'+script, chdir: ROOT)
  ensure
    input&.clear
    configuration&.clear
  end
end

CollectReleaseBuild.run(ARGV.fetch(0,'admin')) if $PROGRAM_NAME == __FILE__
