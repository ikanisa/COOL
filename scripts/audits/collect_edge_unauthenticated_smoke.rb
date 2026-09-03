# Production negative-path smoke test. Every request is an unauthenticated
# empty POST and must be rejected before database mutation or provider access.
require 'json'
require 'net/http'
require 'digest'
require 'time'
require_relative 'collect_production_cutover'

module CollectEdgeUnauthenticatedSmoke
  REF = CollectProductionCutover::REF
  SLUGS = %w[
    auth-send-whatsapp-otp
    collect-notification-operator
    dispatch-notifications
    ingest-bank-email
    ingest-bank-sms
    ingest-bank-statement
    ingest-payment-sms
    parse-payment-sms
    prepare-roster-import
    send-notification
    verify-play-integrity
  ].freeze

  def self.run(output)
    raise 'New JSON report required' unless output.end_with?('.json') && !File.exist?(output)
    checks = SLUGS.map do |slug|
      uri = URI("https://#{REF}.supabase.co/functions/v1/#{slug}")
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = '{}'
      client = Net::HTTP.new(uri.host, uri.port)
      client.use_ssl = true
      client.open_timeout = 10
      client.read_timeout = 20
      response = client.request(request)
      body = response.body.to_s
      error = JSON.parse(body)['error'] rescue nil
      {
        slug: slug,
        status: response.code.to_i,
        rejected: response.code.to_i == 401,
        error: error.to_s.slice(0, 120),
        body_sha256: Digest::SHA256.hexdigest(body)
      }
    end
    raise 'A production function did not reject the unauthenticated empty request' unless
      checks.all? { |check| check[:rejected] }
    report = {
      captured_at: Time.now.utc.iso8601,
      project: REF,
      mode: 'unauthenticated_empty_post_negative_path',
      checks: checks,
      requests: checks.length,
      authenticated_requests: 0,
      provider_sends: 0,
      expected_database_mutations: 0,
      result: 'ALL_EDGE_FUNCTIONS_REJECT_UNAUTHENTICATED_REQUESTS'
    }
    File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(JSON.pretty_generate(report) + "\n")
    end
    puts JSON.generate(report: output, result: report[:result], requests: checks.length)
    true
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: collect_edge_unauthenticated_smoke.rb NEW_REPORT.json') unless ARGV.length == 1
  begin
    exit(CollectEdgeUnauthenticatedSmoke.run(ARGV.first) ? 0 : 1)
  rescue StandardError => error
    warn "Edge negative-path smoke failed: #{error.message}"
    exit 1
  end
end
