# Exact production deployment/readback for five reviewed hybrid Edge
# Functions. Database history must already be 120 and every operational flag
# must be off. The cutover never deletes functions, changes secrets, invokes a
# function, sends provider messages or changes network/auth configuration.
require 'json'
require 'digest'
require 'io/console'
require 'open3'
require 'tmpdir'
require 'time'
require_relative 'collect_production_cutover'
require_relative 'collect_edge_function_local_gate'

module CollectHybridEdgeCutover
  ROOT = CollectProductionCutover::ROOT
  REF = CollectProductionCutover::REF
  CLI = '/Users/jeanbosco/.npm/_npx/1517203cdeef2779/node_modules/@supabase/cli-darwin-arm64/bin/supabase'.freeze
  PREFLIGHT = 'docs/release/SUPABASE_CONTINUATION_PREFLIGHT_V4_2026-09-03.json'.freeze
  DATABASE_READBACK = 'docs/release/HYBRID_PRIVILEGE_CUTOVER_READBACK_2026-09-03.json'.freeze
  LOCAL_GATE = 'docs/release/HYBRID_EDGE_LOCAL_GATE_2026-09-03.json'.freeze
  SLUGS = CollectEdgeFunctionLocalGate::SLUGS
  EXPECTED_JWT = CollectEdgeFunctionLocalGate::EXPECTED_JWT
  EXPECTED_BEFORE = {
    'verify-play-integrity' => {
      'version' => 3,
      'verify_jwt' => true,
      'ezbr_sha256' => '4119a17a3638c41701a25dfd36ba6eb04351194d9202ca64345e69be775c8cc6'
    },
    'ingest-payment-sms' => {
      'version' => 4,
      'verify_jwt' => true,
      'ezbr_sha256' => '9fbd292a49d02ff2bec07253becbeb62910763138839b13f957560d343f0ae75'
    },
    'parse-payment-sms' => {
      'version' => 5,
      'verify_jwt' => false,
      'ezbr_sha256' => '707e809d676bb41596ea99355ad1b7f5a119cb8c4bc1a4a00e821ee12fc61926'
    }
  }.freeze
  NEW_SLUGS = %w[prepare-roster-import collect-notification-operator].freeze
  DISABLED_FLAGS = %w[
    hybrid_member_onboarding
    hybrid_direct_ussd_allocation
    native_sms_attestation_enforcement
    hybrid_sms_notifications
    hybrid_verified_account_claim
  ].freeze

  def self.local_gate!
    gate = JSON.parse(File.read(File.join(ROOT, LOCAL_GATE)))
    raise 'Reviewed local Edge Function gate did not pass' unless
      gate['mode'] == 'local_only_no_hosted_credentials_or_mutations' &&
      gate['result'] == 'EDGE_FUNCTION_LOCAL_GATE_PASS' &&
      gate.dig('tests', 'count') == 54 &&
      gate.dig('tests', 'status') == 'pass' &&
      gate.dig('checks', 'status') == 'pass' &&
      gate['verify_jwt'] == EXPECTED_JWT
    inventory = gate.fetch('sources').to_h { |row| [row.fetch('file'), row.fetch('sha256')] }
    current = Dir[File.join(ROOT, 'supabase/functions/**/*.ts')].sort.to_h do |path|
      [path.delete_prefix(ROOT + '/'), Digest::SHA256.file(path).hexdigest]
    end
    raise 'Edge Function source changed after the local gate' unless inventory == current
  end

  def self.database_gate!(token)
    report = JSON.parse(File.read(File.join(ROOT, DATABASE_READBACK)))
    raise 'Verified production database readback is required' unless
      report['project'] == REF && report['mode'] == 'readback' &&
      report['result'] == 'PASS' &&
      report.dig('checks', 'inventory', 'migrations') == 120 &&
      report.dig('checks', 'function_boundary')&.values&.all? { |value| value == true }
    history = CollectProductionCutover.history(token)
    raise 'Production migration history must be exactly 120' unless history.length == 120
    flags = CollectProductionCutover.query(token, <<~SQL)
      SELECT key, enabled FROM public.feature_flags
      WHERE key IN (#{DISABLED_FLAGS.map { |flag| "'#{flag}'" }.join(',')})
      ORDER BY key;
    SQL
    raise 'A controlled-rollout flag is missing or enabled' unless
      flags.map { |row| row.fetch('key') }.sort == DISABLED_FLAGS.sort &&
      flags.all? { |row| row['enabled'] == false }
    flags
  end

  def self.preflight_before!
    report = JSON.parse(File.read(File.join(ROOT, PREFLIGHT)))
    raise 'Exact read-only hosted preflight is required' unless
      report.dig('project', 'id') == REF && report.fetch('errors').empty? &&
      report.dig('checks', 'migrations', 'remote_count') == 119
    remote = report.dig('checks', 'functions').to_h { |row| [row.fetch('slug'), row] }
    EXPECTED_BEFORE.each do |slug, expected|
      actual = remote.fetch(slug).slice('version', 'verify_jwt', 'ezbr_sha256')
      raise "Unexpected reviewed baseline for #{slug}" unless actual == expected
    end
    raise 'A new hybrid function already existed at preflight' unless
      NEW_SLUGS.none? { |slug| remote.key?(slug) }
  end

  def self.current_functions(token)
    CollectProductionCutover.request(token, '/functions').to_h { |row| [row.fetch('slug'), row] }
  end

  def self.require_apply_baseline!(remote)
    EXPECTED_BEFORE.each do |slug, expected|
      actual = remote.fetch(slug).slice('version', 'verify_jwt', 'ezbr_sha256')
      raise "Production function baseline changed for #{slug}" unless actual == expected
    end
    raise 'A new target function already exists; use readback, never blind retry' unless
      NEW_SLUGS.none? { |slug| remote.key?(slug) }
  end

  def self.download_readback(token, slug)
    env = { 'SUPABASE_ACCESS_TOKEN' => token }
    Dir.mktmpdir('collect-edge-readback-') do |directory|
      _output, _error, status = Open3.capture3(
        env, CLI, 'functions', 'download', slug, '--project-ref', REF,
        '--use-api', '--workdir', directory
      )
      raise "Deployed source download failed for #{slug}" unless status.success?
      files = Dir[File.join(directory, 'supabase/functions/**/*.ts')].sort
      raise "No downloaded TypeScript source for #{slug}" if files.empty?
      files.map do |file|
        relative = file.delete_prefix(directory + '/')
        local = File.join(ROOT, relative)
        sha = Digest::SHA256.file(file).hexdigest
        raise "Deployed source mismatch: #{relative}" unless
          File.file?(local) && Digest::SHA256.file(local).hexdigest == sha
        { file: relative, sha256: sha }
      end
    end
  end

  def self.readback(token)
    remote = current_functions(token)
    source = SLUGS.map do |slug|
      function = remote[slug] or raise "Missing deployed function #{slug}"
      raise "Function not active or JWT guard changed: #{slug}" unless
        function['status'] == 'ACTIVE' && function['verify_jwt'] == EXPECTED_JWT.fetch(slug)
      {
        slug: slug,
        version: function['version'],
        status: function['status'],
        verify_jwt: function['verify_jwt'],
        ezbr_sha256: function['ezbr_sha256'],
        source_readback: 'exact_match',
        files: download_readback(token, slug)
      }
    end
    EXPECTED_BEFORE.each do |slug, baseline|
      raise "Function version did not advance: #{slug}" unless
        remote.fetch(slug)['version'].to_i > baseline.fetch('version')
    end
    NEW_SLUGS.each do |slug|
      raise "New function version is invalid: #{slug}" unless remote.fetch(slug)['version'].to_i >= 1
    end
    {
      functions: source,
      disabled_flags: database_gate!(token),
      function_count: remote.length
    }
  end

  def self.run(mode, output)
    raise 'Mode must be plan, apply or readback' unless %w[plan apply readback].include?(mode)
    raise 'New JSON report required' unless output.end_with?('.json') && !File.exist?(output)
    raise 'Pinned Supabase CLI is unavailable' unless File.executable?(CLI)
    raise 'Linked project mismatch' unless
      File.read(File.join(ROOT, 'supabase/.temp/project-ref')).strip == REF
    local_gate!
    preflight_before!
    STDOUT.sync = true
    puts 'Awaiting release credential on non-echoing stdin.'
    raw = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
    credential = JSON.parse(raw.to_s)
    raw&.clear
    raise 'Wrong credential scope' unless
      credential.fetch('project_url') == "https://#{REF}.supabase.co"
    token = credential.fetch('access_token')
    raise 'Expected Management API credential' unless token.start_with?('sbp_')
    report = {
      started_at: Time.now.utc.iso8601, project: REF, mode: mode,
      result: 'IN_PROGRESS', targeted_functions: SLUGS,
      deployments: [], provider_sends: 0, functions_invoked: 0,
      functions_deleted: 0, secrets_changed: 0, database_mutations: 0,
      network_mutations: 0, auth_config_mutations: 0, operational_flags_enabled: 0
    }
    begin
      project = CollectProductionCutover.request(token, '')
      raise 'Wrong or unhealthy authenticated project' unless
        project['id'] == REF && project['name'] == 'COOL' && project['status'] == 'ACTIVE_HEALTHY'
      report[:disabled_flags_before] = database_gate!(token)
      if mode == 'readback'
        report[:checks] = readback(token)
      else
        remote = current_functions(token)
        require_apply_baseline!(remote)
        report[:before] = SLUGS.map do |slug|
          remote[slug]&.slice('slug', 'version', 'status', 'verify_jwt', 'ezbr_sha256')
        end.compact
        if mode == 'apply'
          env = { 'SUPABASE_ACCESS_TOKEN' => token }
          SLUGS.each do |slug|
            _deploy_output, _deploy_error, status = Open3.capture3(
              env, CLI, 'functions', 'deploy', slug, '--project-ref', REF,
              '--use-api', chdir: ROOT
            )
            raise "Deployment failed for #{slug}; CLI exit #{status.exitstatus}" unless status.success?
            current = current_functions(token).fetch(slug)
            raise "Deployed function not active or JWT guard changed: #{slug}" unless
              current['status'] == 'ACTIVE' && current['verify_jwt'] == EXPECTED_JWT.fetch(slug)
            report[:deployments] << {
              slug: slug, version: current['version'], verify_jwt: current['verify_jwt'],
              ezbr_sha256: current['ezbr_sha256'], source_readback: 'exact_match',
              files: download_readback(token, slug)
            }
            puts "Deployed and source-verified #{slug}."
          end
          report[:checks] = readback(token)
        end
      end
      report[:result] = mode == 'apply' ?
        'FIVE_HYBRID_EDGE_FUNCTIONS_DEPLOYED_FLAGS_OFF_NOT_FULL_PRODUCTION_GO' : 'PASS'
    rescue StandardError => error
      report[:result] = 'STOPPED_REQUIRES_READBACK_BEFORE_RETRY'
      report[:error] = error.message.gsub(token, '[redacted]')
      warn "Edge cutover stopped: #{report[:error]}"
    ensure
      report[:finished_at] = Time.now.utc.iso8601
      File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.pretty_generate(report) + "\n")
      end
      puts JSON.generate(report: output, result: report[:result], deployed: report[:deployments].length)
    end
    report[:result] != 'STOPPED_REQUIRES_READBACK_BEFORE_RETRY'
  ensure
    raw&.clear
    token&.clear
    credential&.clear
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: collect_hybrid_edge_cutover.rb plan|apply|readback NEW_REPORT.json') unless ARGV.length == 2
  exit(CollectHybridEdgeCutover.run(*ARGV) ? 0 : 1)
end
