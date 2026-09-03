# Applies only the reviewed Collect Auth URL correction. Credentials arrive on
# stdin and never enter argv, the environment, Git, or the evidence report.
require 'json'
require 'net/http'
require 'io/console'
require 'time'

module CollectAuthRedirectCutover
  REF = 'lhbowpbcpwoiparwnwgt'.freeze
  PROJECT_URL = "https://#{REF}.supabase.co".freeze
  SITE_URL = 'https://collect.ikanisa.com'.freeze
  ADMIN_URL = 'https://admin.collect.ikanisa.com'.freeze
  RETIRED_URL = 'https://easymo.vercel.app'.freeze
  TARGET_ALLOW_LIST = [SITE_URL, ADMIN_URL].join(',').freeze

  def self.normalized_allow_list(value)
    value.to_s.split(',').map(&:strip).reject(&:empty?).sort
  end

  def self.plan(current)
    site = current.fetch('site_url').to_s
    redirects = normalized_allow_list(current.fetch('uri_allow_list', ''))
    target = normalized_allow_list(TARGET_ALLOW_LIST)
    return { 'mutation_required' => false } if site == SITE_URL && redirects == target
    legacy = site == RETIRED_URL && redirects == [RETIRED_URL]
    raise 'Auth URL baseline changed; refusing an unreviewed overwrite' unless legacy
    { 'mutation_required' => true }
  end

  def self.api_request(token, method, path, body = nil)
    uri = URI("https://api.supabase.com/v1/projects/#{REF}#{path}")
    request = method == :patch ? Net::HTTP::Patch.new(uri) : Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{token}"
    if body
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate(body)
    end
    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: true,
      open_timeout: 15,
      read_timeout: 45,
    ) { |http| http.request(request) }
    raise "Management API HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  def self.origin_status(url)
    uri = URI(url)
    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: true,
      open_timeout: 10,
      read_timeout: 20,
    ) { |http| http.request(Net::HTTP::Get.new(uri)) }
    Integer(response.code)
  end

  def self.run(output)
    raise 'Output must be a new JSON file' unless output.end_with?('.json') && !File.exist?(output)
    STDOUT.sync = true
    puts 'Awaiting credential on non-echoing stdin; no credential is persisted.'
    input = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
    credential = JSON.parse(input.to_s)
    input&.clear
    raise 'Source URL mismatch' unless credential.fetch('project_url').sub(%r{/$}, '') == PROJECT_URL
    token = credential.fetch('access_token')
    raise 'Invalid management credential' unless token.start_with?('sbp_')

    project = api_request(token, :get, '')
    raise 'Production project mismatch' unless project['id'] == REF && project['name'] == 'COOL'
    origin_statuses = {
      SITE_URL => origin_status(SITE_URL),
      ADMIN_URL => origin_status(ADMIN_URL),
    }
    raise 'Canonical Collect origins must be live before Auth cutover' unless origin_statuses.values.all? { |status| status.between?(200, 399) }

    before = api_request(token, :get, '/config/auth')
    decision = plan(before)
    mutation_count = 0
    if decision.fetch('mutation_required')
      api_request(
        token,
        :patch,
        '/config/auth',
        { site_url: SITE_URL, uri_allow_list: TARGET_ALLOW_LIST },
      )
      mutation_count = 1
    end
    after = api_request(token, :get, '/config/auth')
    raise 'Auth Site URL readback mismatch' unless after['site_url'] == SITE_URL
    unless normalized_allow_list(after['uri_allow_list']) == normalized_allow_list(TARGET_ALLOW_LIST)
      raise 'Auth redirect allowlist readback mismatch'
    end
    report = {
      captured_at: Time.now.utc.iso8601,
      mode: 'controlled_exact_auth_redirect_cutover',
      project: project.slice('id', 'name', 'region', 'status'),
      source: 'Google Drive sheet Supabase; credential values not saved',
      live_origins: origin_statuses,
      before: before.slice('site_url', 'uri_allow_list'),
      after: after.slice('site_url', 'uri_allow_list'),
      production_mutations: mutation_count,
      unrelated_auth_fields_submitted: [],
      status: 'pass',
    }
    File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(JSON.pretty_generate(report) + "\n")
    end
    puts JSON.generate(report: output, status: 'pass', production_mutations: mutation_count)
    true
  ensure
    token&.clear
    credential&.clear
    input&.clear
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: ruby scripts/audits/collect_auth_redirect_cutover.rb NEW_REPORT.json') unless ARGV.length == 1
  begin
    exit(CollectAuthRedirectCutover.run(File.expand_path(ARGV.fetch(0))) ? 0 : 1)
  rescue StandardError => error
    warn "Auth URL cutover failed: #{error.message.gsub(/sbp_[A-Za-z0-9]+/, '[redacted]')}"
    exit 1
  end
end
