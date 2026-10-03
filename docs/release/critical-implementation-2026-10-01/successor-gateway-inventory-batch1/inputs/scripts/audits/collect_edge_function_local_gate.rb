# frozen_string_literal: true

# Local source gate for every Edge Function. The historical five-function
# deployment contract lives in collect_hybrid_edge_cutover.rb; this gate never
# deploys or invokes functions and does not approve provider/runtime behavior.
require 'json'
require 'digest'
require 'open3'
require 'time'

module CollectEdgeFunctionLocalGate
  ROOT = File.expand_path('../..', __dir__)
  EXPECTED_JWT = {
    'auth-send-whatsapp-otp' => false,
    'collect-notification-operator' => true,
    'dispatch-notifications' => false,
    'ingest-bank-email' => false,
    'ingest-bank-sms' => true,
    'ingest-bank-statement' => true,
    'ingest-payment-sms' => true,
    'parse-payment-sms' => false,
    'prepare-roster-import' => true,
    'send-notification' => false,
    'verify-play-integrity' => true
  }.freeze
  TEST_ENV = %w[
    SUPABASE_SERVICE_ROLE_KEY AUTH_PHONE_PASSWORD_SECRET OTP_CODE_HASH_SECRET
    OTP_TEST_PHONE OTP_TEST_CODE GOOGLE_SERVICE_ACCOUNT_EMAIL GOOGLE_PRIVATE_KEY
    AI_AUDIT_SHEET_ID
  ].freeze

  def self.runtime(env)
    candidate = env['DENO_BIN']
    if candidate.to_s.empty?
      candidate = env.fetch('PATH', '').split(File::PATH_SEPARATOR).map do |directory|
        File.join(directory, 'deno')
      end.find { |path| File.file?(path) && File.executable?(path) }
    end
    unless candidate && File.file?(candidate) && File.executable?(candidate)
      raise 'Deno unavailable; install the .dvmrc version on PATH or set DENO_BIN to its executable'
    end
    File.expand_path(candidate)
  end

  def self.inventory(root)
    source = Dir[File.join(root, 'supabase/functions/**/*.ts')].sort
    entries = Dir[File.join(root, 'supabase/functions/*/index.ts')].sort
    tests = source.select { |path| path.end_with?('_test.ts') }
    raise 'No Edge Function tests discovered' if tests.empty?
    slugs = entries.map { |path| File.basename(File.dirname(path)) }
    raise 'Edge entrypoint inventory differs from the explicit JWT contract' unless slugs.sort == EXPECTED_JWT.keys.sort
    { sources: source, entrypoints: entries, tests: tests }
  end

  def self.config_jwt(root = ROOT)
    config = File.read(File.join(root, 'supabase/config.toml'))
    configured = config.scan(/^\[functions\.([^\]]+)\]\s*$/).flatten
    raise 'Function config inventory differs from the reviewed contract' unless configured.sort == EXPECTED_JWT.keys.sort
    EXPECTED_JWT.to_h do |slug, _expected|
      block = config[/^\[functions\.#{Regexp.escape(slug)}\]\s*\n(.*?)(?=^\[|\z)/m]
      values = block.to_s.scan(/^verify_jwt\s*=\s*(true|false)\s*(?:#.*)?$/).flatten
      raise "Exactly one verify_jwt required for #{slug}" unless values.length == 1
      [slug, values.first == 'true']
    end
  end

  def self.fingerprints(root)
    paths = Dir[File.join(root, 'supabase/functions/**/*.ts')]
    paths += %w[.dvmrc supabase/config.toml deno.lock deno.json deno.jsonc].map { |path| File.join(root, path) }
    paths += Dir[File.join(root, 'supabase/functions/**/{deno.json,deno.jsonc,deno.lock,import_map.json}')]
    paths.select { |path| File.file?(path) }.uniq.sort.map do |path|
      { file: path.delete_prefix(root + '/'), sha256: Digest::SHA256.file(path).hexdigest }
    end
  end

  def self.run(output, root: ROOT, env: ENV)
    raise 'New JSON report required' unless output.end_with?('.json') && !File.exist?(output)
    root = File.expand_path(root)
    report = {
      schema_version: 2, started_at: Time.now.utc.iso8601(6),
      mode: 'local_only_no_hosted_credentials_or_mutations',
      scope: 'all_source_edge_functions', final_acceptance: false,
      deno: nil, tests: {}, checks: {}, verify_jwt: {}, commands: [],
      sources: fingerprints(root), result: 'IN_PROGRESS'
    }
    # Tests may set synthetic values, but cannot inherit these credential values
    # or read arbitrary host variables. No network/run/write permissions granted.
    child_env = TEST_ENV.to_h { |name| [name, nil] }.merge('NO_COLOR' => '1', 'DENO_NO_UPDATE_CHECK' => '1')
    capture = lambda do |deno, *arguments|
      started = Time.now.utc.iso8601(6)
      stdout, stderr, status = Open3.capture3(child_env, deno, *arguments, chdir: root)
      report[:commands] << {
        command: [deno, *arguments], started_at: started,
        finished_at: Time.now.utc.iso8601(6), exit_code: status.exitstatus,
        stdout: stdout, stderr: stderr
      }
      [stdout, stderr, status]
    end
    begin
      deno = runtime(env)
      pin = File.read(File.join(root, '.dvmrc')).strip
      raise 'Exact numeric Deno version required in .dvmrc' unless pin.match?(/\A\d+\.\d+\.\d+\z/)
      version, _error, status = capture.call(deno, '--version')
      report[:deno] = version.lines.first.to_s.strip
      report[:runtime] = { path: deno, sha256: Digest::SHA256.file(deno).hexdigest, pinned_version: pin }
      version_match = report[:deno].match(/\Adeno (\d+\.\d+\.\d+)(?: \(stable, release, [^)]+\))?\z/)
      unless status.success? && version_match && version_match[1] == pin
        raise "Deno runtime must match .dvmrc (#{pin})"
      end
      scope = inventory(root)
      report[:verify_jwt] = config_jwt(root)
      raise 'Function JWT config differs from the reviewed contract' unless report[:verify_jwt] == EXPECTED_JWT
      relative = ->(paths) { paths.map { |path| path.delete_prefix(root + '/') } }
      test_files = relative.call(scope[:tests])
      stdout, _stderr, status = capture.call(deno, 'test', '--no-prompt', '--reporter=dot',
                                           "--allow-env=#{TEST_ENV.join(',')}", *test_files)
      # A fixed historical count must not exclude newly added tests. Missing,
      # failing or ignored results cannot satisfy this full source gate.
      summary = stdout.match(/^ok \| (\d+) passed \| (\d+) failed(?: \| (\d+) ignored)?(?:\s|$)/)
      passed, failed, ignored = summary ? summary.captures.map { |value| value.to_i } : [0, 0, 0]
      valid = status.success? && summary && passed.positive? && failed.zero? && ignored.zero?
      report[:tests] = { files: test_files, count: passed, failed: failed, ignored: ignored,
                         status: valid ? 'pass' : 'fail' }
      raise 'Deno tests failed, were ignored or lacked a valid nonempty summary; see recorded output' unless valid
      source_files = relative.call(scope[:sources])
      _stdout, _stderr, status = capture.call(deno, 'check', *source_files)
      report[:checks] = { entrypoints: relative.call(scope[:entrypoints]), files: source_files,
                          status: status.success? ? 'pass' : 'fail' }
      raise 'Deno type check failed; see recorded output' unless status.success?
      raise 'Edge source or config changed during the gate' unless report[:sources] == fingerprints(root)
      report[:result] = 'EDGE_FUNCTION_LOCAL_GATE_PASS'
    rescue StandardError => error
      report[:result] = 'EDGE_FUNCTION_LOCAL_GATE_FAIL'
      report[:error] = error.message
    ensure
      report[:source_inputs_unchanged] = report[:sources] == fingerprints(root)
      unless report[:source_inputs_unchanged]
        report[:result] = 'EDGE_FUNCTION_LOCAL_GATE_FAIL'
        report[:error] = 'Edge source or config changed during the gate'
      end
      report[:finished_at] = Time.now.utc.iso8601(6)
      File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.pretty_generate(report) + "\n")
      end
      puts JSON.generate(report: output, result: report[:result], tests: report.dig(:tests, :count),
                         checked_entrypoints: report.dig(:checks, :entrypoints)&.length)
    end
    report[:result] == 'EDGE_FUNCTION_LOCAL_GATE_PASS'
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: collect_edge_function_local_gate.rb NEW_REPORT.json (Deno on PATH or DENO_BIN)') unless ARGV.length == 1
  begin
    exit(CollectEdgeFunctionLocalGate.run(ARGV.first) ? 0 : 1)
  rescue StandardError => error
    warn "Edge local gate failed: #{error.message}"
    exit 1
  end
end
