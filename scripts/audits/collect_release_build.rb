# Public-only build configuration from the approved credential source. Never
# passes a service key to Flutter and never loads an unrelated .env file.
require 'json'
require 'base64'
require 'io/console'

module CollectReleaseBuild
  ROOT = File.expand_path('../..', __dir__)
  REF = 'lhbowpbcpwoiparwnwgt'.freeze

  def self.environment(credential)
    url = credential.fetch('project_url')
    key = credential.fetch('anon_key')
    raise 'Unexpected public project' unless url == "https://#{REF}.supabase.co"
    payload = JSON.parse(Base64.urlsafe_decode64(key.split('.').fetch(1)))
    raise 'Only the matching anonymous public key may enter a build' unless payload['role'] == 'anon' && payload['ref'] == REF
    {
      'COLLECT_SKIP_DOTENV'=>'1', 'SUPABASE_PRODUCTION_URL'=>url,
      'SUPABASE_PRODUCTION_ANON_KEY'=>key,
      'APP_PUBLIC_URL'=>'https://collect.ikanisa.com',
      'ADMIN_APP_URL'=>'https://admin.collect.ikanisa.com'
    }
  end

  def self.run(target='admin')
    raise 'Expected admin, android or ios build' unless %w[admin android ios].include?(target)
    STDOUT.sync = true
    puts 'Awaiting public build configuration on non-echoing stdin.'
    input = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
    credential = JSON.parse(input.to_s)
    input&.clear
    env = environment(credential)
    env['FLUTTER_BIN']='/Users/jeanbosco/Developer/flutter/bin/flutter'
    env['COLLECT_ANDROID_BUILD_NAME']='1.2.4'
    env['COLLECT_ANDROID_BUILD_NUMBER']='23'
    env['COLLECT_IOS_BUILD_NAME']='1.2.4'
    env['COLLECT_IOS_BUILD_NUMBER']='23'
    script = {'admin'=>'admin_pwa_release_build.sh','android'=>'android_play_store_build.sh','ios'=>'ios_app_store_build.sh'}.fetch(target)
    raise "#{target} release build failed" unless system(env, 'bash', 'scripts/'+script, chdir: ROOT)
  ensure
    input&.clear
    credential&.clear
  end
end

CollectReleaseBuild.run(ARGV.fetch(0,'admin')) if $PROGRAM_NAME == __FILE__
