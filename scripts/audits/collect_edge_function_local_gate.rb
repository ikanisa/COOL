# Local-only release gate for the five reviewed hybrid Edge Functions. It runs
# the complete shared Deno test suite, type-checks every target entry point and
# records source/config fingerprints. It has no hosted credentials or writes.
require 'json'
require 'digest'
require 'open3'
require 'time'

module CollectEdgeFunctionLocalGate
  ROOT = File.expand_path('../..', __dir__)
  DENO = '/Users/jeanbosco/.npm/_npx/05b6ef7b13673c57/node_modules/@deno/darwin-arm64/deno'.freeze
  SLUGS = %w[
    verify-play-integrity
    ingest-payment-sms
    parse-payment-sms
    prepare-roster-import
    collect-notification-operator
  ].freeze
  EXPECTED_JWT = {
    'verify-play-integrity' => true,
    'ingest-payment-sms' => true,
    'parse-payment-sms' => false,
    'prepare-roster-import' => true,
    'collect-notification-operator' => true
  }.freeze

  def self.config_jwt
    config = File.read(File.join(ROOT, 'supabase/config.toml'))
    EXPECTED_JWT.to_h do |slug, _expected|
      block = config[/^\[functions\.#{Regexp.escape(slug)}\]\n(.*?)(?=^\[|\z)/m]
      raise "Missing function config for #{slug}" unless block
      value = block[/^verify_jwt\s*=\s*(true|false)\s*$/, 1]
      raise "Missing verify_jwt for #{slug}" unless value
      [slug, value == 'true']
    end
  end

  def self.run(output)
    raise 'New JSON report required' unless output.end_with?('.json') && !File.exist?(output)
    raise 'Pinned Deno runtime is unavailable' unless File.executable?(DENO)
    report = {
      captured_at: Time.now.utc.iso8601,
      mode: 'local_only_no_hosted_credentials_or_mutations',
      deno: nil, tests: {}, checks: {}, verify_jwt: {}, sources: [],
      result: 'IN_PROGRESS'
    }
    version, version_error, version_status = Open3.capture3(DENO, '--version', chdir: ROOT)
    raise "Deno version check failed: #{version_error.lines.first}" unless version_status.success?
    report[:deno] = version.lines.first.to_s.strip
    tests = Dir[File.join(ROOT, 'supabase/functions/_shared/*_test.ts')].sort
    output_text, error_text, status = Open3.capture3(
      DENO, 'test', '--allow-env', *tests, chdir: ROOT
    )
    report[:tests] = {
      files: tests.map { |path| path.delete_prefix(ROOT + '/') },
      count: output_text[/ok \| (\d+) passed \| 0 failed/, 1]&.to_i,
      status: status.success? ? 'pass' : 'fail'
    }
    raise "Deno tests failed: #{error_text.lines.first}" unless
      status.success? && report.dig(:tests, :count) == 54
    entries = SLUGS.map { |slug| "supabase/functions/#{slug}/index.ts" }
    _check_output, check_error, check_status = Open3.capture3(
      DENO, 'check', *entries, chdir: ROOT
    )
    report[:checks] = { entrypoints: entries, status: check_status.success? ? 'pass' : 'fail' }
    raise "Deno check failed: #{check_error.lines.first}" unless check_status.success?
    report[:verify_jwt] = config_jwt
    raise 'Function JWT config differs from the reviewed contract' unless
      report[:verify_jwt] == EXPECTED_JWT
    sources = Dir[File.join(ROOT, 'supabase/functions/**/*.ts')].sort
    report[:sources] = sources.map do |path|
      { file: path.delete_prefix(ROOT + '/'), sha256: Digest::SHA256.file(path).hexdigest }
    end
    report[:result] = 'EDGE_FUNCTION_LOCAL_GATE_PASS'
    File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(JSON.pretty_generate(report) + "\n")
    end
    puts JSON.generate(report: output, result: report[:result], tests: 54, checked_entrypoints: entries.length)
    true
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: collect_edge_function_local_gate.rb NEW_REPORT.json') unless ARGV.length == 1
  begin
    exit(CollectEdgeFunctionLocalGate.run(ARGV.first) ? 0 : 1)
  rescue StandardError => error
    warn "Edge local gate failed: #{error.message}"
    exit 1
  end
end
