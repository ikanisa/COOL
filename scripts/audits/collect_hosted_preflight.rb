# Read-only hosted release evidence. Credentials arrive on non-echoing stdin,
# never argv, dotenv, reports or shell history. This script cannot deploy.
require 'json'
require 'net/http'
require 'io/console'
require 'digest'
require 'time'

module CollectHostedPreflight
  ROOT = File.expand_path('../..', __dir__)
  REF = 'lhbowpbcpwoiparwnwgt'.freeze
  REQUIRED_SECRETS = %w[
    WHATSAPP_CLOUD_API_TOKEN WHATSAPP_PHONE_NUMBER_ID WHATSAPP_AUTH_TEMPLATE_NAME
    SEND_SMS_HOOK_SECRET INTERNAL_FUNCTION_SECRET BANK_EMAIL_INGEST_HMAC_SECRET
    APNS_KEY_ID APNS_TEAM_ID APNS_BUNDLE_ID APNS_PRIVATE_KEY_BASE64
    FCM_SERVICE_ACCOUNT_JSON GOOGLE_PLAY_SERVICE_ACCOUNT_JSON
  ].freeze

  def self.plan(remote, directory)
    raise 'Migration inventory must be an array' unless remote.is_a?(Array)
    versions = remote.map { |row| row.fetch('version').to_s }
    raise 'Duplicate remote migration version' unless versions.uniq == versions
    files = Dir[File.join(directory, '*.sql')].sort.map do |path|
      match = File.basename(path).match(/\A(\d+)_([^\/]+)\.sql\z/)
      raise 'Invalid migration filename' unless match
      { 'version' => match[1], 'name' => match[2],
        'file' => File.basename(path), 'sha256' => Digest::SHA256.file(path).hexdigest }
    end
    local_versions = files.map { |file| file['version'] }
    raise 'Duplicate local migration version' unless local_versions.uniq == local_versions
    {
      remote_count: versions.length, local_count: files.length,
      remote_only: versions - local_versions,
      name_mismatches: files.map do |file|
        existing = remote.find { |row| row['version'].to_s == file['version'] }
        file['version'] if existing && existing['name'] != file['name']
      end.compact,
      history_holes: files.select { |file| !versions.include?(file['version']) && versions.max && file['version'] < versions.max },
      pending: files.reject { |file| versions.include?(file['version']) }
    }
  end

  def self.advisor_summary(data)
    lints = data.fetch('lints')
    raise 'Invalid advisor response' unless lints.is_a?(Array)
    {
      count: lints.length,
      by_level: lints.group_by { |lint| lint.fetch('level') }.transform_values(&:length),
      findings: lints.group_by { |lint| [lint['level'], lint['name']] }.map do |key, rows|
        { level: key[0], name: key[1], count: rows.length }
      end
    }
  end

  def self.run(output)
    raise 'Output must be a new JSON file' unless output.end_with?('.json') && !File.exist?(output)
    linked = File.read(File.join(ROOT, 'supabase/.temp/project-ref')).strip
    raise 'Linked project mismatch' unless linked == REF
    STDOUT.sync = true
    puts 'Awaiting credential on non-echoing stdin; no credential is persisted.'
    input = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
    credential = JSON.parse(input.to_s)
    input&.clear
    raise 'Source URL mismatch' unless credential.fetch('project_url').sub(%r{/$}, '') == "https://#{REF}.supabase.co"
    token = credential.fetch('access_token')
    raise 'Invalid management credential' unless token.start_with?('sbp_')
    request = lambda do |path, query = nil|
      uri = URI("https://api.supabase.com/v1/projects/#{REF}#{path}")
      req = query ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{token}"
      if query
        req['Content-Type'] = 'application/json'
        req.body = JSON.generate(query: "begin read only; set local statement_timeout='30s'; #{query}; rollback;")
      end
      client = Net::HTTP.new(uri.host, uri.port)
      client.use_ssl = true
      client.open_timeout = 15
      client.read_timeout = 45
      response = client.request(req)
      raise "HTTP #{response.code} at #{path.empty? ? '/project' : path}" unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    end
    project = request.call('')
    raise 'Remote project mismatch' unless project['id'] == REF && project['name'] == 'COOL'
    report = {
      captured_at: Time.now.utc.iso8601,
      credential_source: { title: 'Supabase', tab: 'Sheet1', column: 'G', project_cell: 'G2', credential_values_saved: false },
      mode: 'read_only_no_deployment',
      project: project.slice('id', 'name', 'region', 'status'), checks: {}, errors: []
    }
    capture = lambda do |name, &block|
      report[:checks][name] = block.call
      puts "PASS #{name}"
    rescue StandardError => error
      report[:errors] << { check: name, error: error.message.gsub(token, '[redacted]') }
      puts "FAIL #{name} (see sanitized report)"
    end
    capture.call(:migrations) do
      plan(request.call('/database/query', 'select version, name from supabase_migrations.schema_migrations order by version'), File.join(ROOT, 'supabase/migrations'))
    end
    capture.call(:backups) do
      data = request.call('/database/backups')
      { pitr_enabled: data['pitr_enabled'], walg_enabled: data['walg_enabled'],
        listed_backup_count: data.fetch('backups').length, physical_backup_metadata_present: !data.fetch('physical_backup_data', {}).empty? }
    end
    capture.call(:functions) do
      request.call('/functions').map { |function| function.slice('slug', 'version', 'status', 'verify_jwt', 'ezbr_sha256', 'updated_at') }
    end
    capture.call(:security_advisors) { advisor_summary(request.call('/advisors/security')) }
    capture.call(:performance_advisors) { advisor_summary(request.call('/advisors/performance')) }
    capture.call(:network_restrictions) do
      data = request.call('/network-restrictions')
      { status: data['status'], ipv4_rule_count: data.dig('config', 'dbAllowedCidrs')&.length,
        ipv6_rule_count: data.dig('config', 'dbAllowedCidrsV6')&.length }
    end
    capture.call(:auth_config) do
      auth = request.call('/config/auth')
      auth.slice('site_url', 'uri_allow_list', 'disable_signup', 'external_phone_enabled',
        'jwt_exp', 'sessions_inactivity_timeout', 'sessions_timebox',
        'refresh_token_rotation_enabled', 'external_anonymous_users_enabled',
        'security_manual_linking_enabled', 'hook_send_sms_enabled', 'sms_otp_exp').merge(
          'sms_test_otp_configured' => !auth['sms_test_otp'].to_s.empty?,
          'sms_test_validity_override_configured' => !auth['sms_test_otp_valid_until'].to_s.empty?,
          'whatsapp_hook_target_matches' => auth['hook_send_sms_uri'] == "https://#{REF}.supabase.co/functions/v1/auth-send-whatsapp-otp")
    end
    capture.call(:required_secrets) do
      names = request.call('/secrets').map { |secret| secret.fetch('name') }
      { required: REQUIRED_SECRETS, missing: REQUIRED_SECRETS - names, values_validated: false }
    end
    capture.call(:runtime_counts) do
      request.call('/database/query', <<~SQL).first
        select (select count(*) from auth.users) as auth_users,
          (select count(*) from auth.sessions) as sessions,
          (select count(*) from public.profiles) as profiles,
          (select count(*) from public.collections) as groups,
          (select count(*) from public.raw_payment_sms) as raw_sms,
          (select count(*) from public.admin_user_roles where revoked_at is null) as active_platform_role_grants,
          to_regclass('collect_admin_access.whatsapp_approvals')::text as approval_table
      SQL
    end
    File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(JSON.pretty_generate(report) + "\n")
    end
    puts JSON.generate(report: output, errors: report[:errors].length, production_mutations: 0)
    report[:errors].empty?
  ensure
    token&.clear
    credential&.clear
    input&.clear
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: ruby scripts/audits/collect_hosted_preflight.rb NEW_REPORT.json') unless ARGV.length == 1
  begin
    exit(CollectHostedPreflight.run(File.expand_path(ARGV[0])) ? 0 : 1)
  rescue StandardError => error
    warn "Preflight failed: #{error.class} (credential and response details withheld)"
    exit 1
  end
end
