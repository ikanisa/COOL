# Approved 2026-09-03 hybrid foundation cutover. This runner accepts only the
# exact seven migrations rehearsed against the encrypted production copy. It
# never deploys Edge Functions, enables operational flags, sends provider
# messages, changes network rules, or publishes client applications.
require 'json'
require 'digest'
require 'io/console'
require 'time'
require_relative 'collect_production_cutover'
require_relative 'collect_index_inventory'

module CollectHybridProductionCutover
  ROOT = File.expand_path('../..', __dir__)
  REF = CollectProductionCutover::REF
  SOURCE = 'docs/release/SUPABASE_CONTINUATION_PREFLIGHT_V3_2026-09-03.json'.freeze
  REHEARSAL = 'docs/release/PRODUCTION_COPY_UPGRADE_REHEARSAL_V21_2026-09-03.json'.freeze
  BASELINE_COUNT = 112
  TARGET_COUNT = 119
  VERSIONS = %w[
    20260903084000
    20260903085000
    20260903090000
    20260903090500
    20260903091000
    20260903091500
    20260903092000
  ].freeze
  DISABLED_FLAGS = %w[
    hybrid_member_onboarding
    hybrid_direct_ussd_allocation
    native_sms_attestation_enforcement
    hybrid_sms_notifications
    hybrid_verified_account_claim
  ].freeze

  def self.manifest
    source = JSON.parse(File.read(File.join(ROOT, SOURCE)))
    raise 'Unexpected preflight project or mode' unless
      source.dig('project', 'id') == REF &&
      source['mode'] == 'read_only_no_deployment' &&
      source.fetch('errors').empty?
    plan = source.dig('checks', 'migrations')
    raise 'Unexpected migration history shape' unless
      plan['remote_count'] == BASELINE_COUNT &&
      plan['local_count'] == TARGET_COUNT &&
      plan.fetch('remote_only').empty? &&
      plan.fetch('history_holes').empty?
    entries = plan.fetch('pending')
    raise 'Unexpected pending migration versions' unless
      entries.map { |entry| entry.fetch('version') } == VERSIONS
    entries.map do |entry|
      file = entry.fetch('file')
      expected = "#{entry.fetch('version')}_#{entry.fetch('name')}.sql"
      raise 'Invalid migration filename' unless
        file == expected && file.match?(/\A\d{14}_[a-z_]+\.sql\z/)
      content = File.read(File.join(ROOT, 'supabase/migrations', file))
      raise 'Reviewed migration bytes changed' unless
        Digest::SHA256.hexdigest(content) == entry.fetch('sha256')
      entry.merge('content' => content)
    end
  end

  def self.rehearsal!(entries)
    rehearsal = JSON.parse(File.read(File.join(ROOT, REHEARSAL)))
    raise 'Actual production-copy rehearsal did not pass' unless
      rehearsal['source_project'] == REF &&
      rehearsal['hosted_changes'] == false &&
      rehearsal['provider_sends'] == false &&
      rehearsal['result'] == 'DATABASE_RESTORE_AND_UPGRADE_REHEARSAL_PASS_NOT_PRODUCTION_GO' &&
      rehearsal.dig('migration_rehearsal', 'status') == 'pass' &&
      rehearsal.dig('migration_rehearsal', 'migration_count') == TARGET_COUNT &&
      rehearsal.dig('cleanup', 'ram_only_container_removed') == true &&
      rehearsal.dig('cleanup', 'evidence_vault_detached') == true
    rehearsed = rehearsal.dig('migration_rehearsal', 'migrations').last(entries.length)
    expected = entries.map { |entry| { 'file' => entry.fetch('file'), 'sha256' => entry.fetch('sha256'), 'status' => 'pass' } }
    actual = rehearsed.map { |entry| entry.slice('file', 'sha256', 'status') }
    raise 'Rehearsed migration set differs from cutover manifest' unless actual == expected
  end

  def self.transaction(entries, remote)
    versions = remote.map { |row| row.fetch('version').to_s }
    raise 'Production migration history changed' unless
      versions.length == BASELINE_COUNT && versions.uniq.length == BASELINE_COUNT &&
      (versions & VERSIONS).empty? && versions == versions.sort
    sql = <<~SQL
      BEGIN;
      SET LOCAL lock_timeout='5s';
      SET LOCAL statement_timeout='180s';
      DO $cutover_guard$ BEGIN
        IF NOT pg_try_advisory_xact_lock(20260903, 84000) THEN
          RAISE EXCEPTION 'Another hybrid cutover is running';
        END IF;
        IF (SELECT array_agg(version::text ORDER BY version) FROM supabase_migrations.schema_migrations)
          IS DISTINCT FROM ARRAY[#{versions.map { |version| "'#{version}'" }.join(',')}]::text[] THEN
          RAISE EXCEPTION 'Production migration history changed';
        END IF;
      END $cutover_guard$;
    SQL
    entries.each do |entry|
      content = entry.fetch('content')
      tag = '$collect_hybrid_cutover_source$'
      raise 'Migration quoting delimiter collision' if content.include?(tag)
      sql << CollectProductionCutover.body(content) << "\n;\n"
      sql << "INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES " \
        "('#{entry.fetch('version')}','#{entry.fetch('name')}',ARRAY[#{tag}#{content}#{tag}]);\n"
    end
    sql << "NOTIFY pgrst,'reload schema';\nCOMMIT;"
    sql
  end

  def self.readiness_checks(token)
    readiness = File.read(File.join(ROOT, 'scripts/supabase_production_readiness.sh'))
    patterns = {
      privileges: /    with allowed_table_grants.*?    order by issue;/m,
      columns: /    with roles\(grantee\).*?    order by 1;/m,
      rails: /    with required_authenticated\(routine_name\).*?    order by issue;/m,
      hybrid_financial: /    with issues\(issue\) as \(.*?    select issue from issues order by issue;/m,
      hybrid_sms: /    with operator_routines\(routine_name\).*?    select issue from issues order by issue;/m
    }
    patterns.to_h do |name, pattern|
      query = readiness[pattern] or raise "Readiness SQL marker changed: #{name}"
      rows = CollectProductionCutover.catalog_query(token, query)
      unless rows.empty?
        issues = rows.map { |row| row.fetch('issue', 'unspecified issue') }.join('; ')
        raise "Hosted readiness failed: #{name}: #{issues}"
      end
      [name, 'pass']
    end
  end

  def self.readback(token, entries)
    history = CollectProductionCutover.history(token)
    raise 'Target migration history is incomplete' unless history.length == TARGET_COUNT
    quoted = VERSIONS.map { |version| "'#{version}'" }.join(',')
    hashes = CollectProductionCutover.query(token, <<~SQL)
      SELECT version, encode(extensions.digest(statements[1], 'sha256'), 'hex') AS sha256
      FROM supabase_migrations.schema_migrations
      WHERE version IN (#{quoted})
      ORDER BY version;
    SQL
    expected_hashes = entries.map { |entry| entry.slice('version', 'sha256') }
    raise 'Hosted migration source hashes differ' unless hashes == expected_hashes
    flags = CollectProductionCutover.query(token, <<~SQL)
      SELECT key, enabled FROM public.feature_flags
      WHERE key IN (#{DISABLED_FLAGS.map { |flag| "'#{flag}'" }.join(',')})
      ORDER BY key;
    SQL
    raise 'A controlled-rollout flag is missing or enabled' unless
      flags.map { |row| row.fetch('key') }.sort == DISABLED_FLAGS.sort &&
      flags.all? { |row| row['enabled'] == false }
    contract = CollectProductionCutover.catalog_query(
      token,
      'SELECT public.attested_sms_contract_version() AS version;'
    ).first
    raise 'Installed-client SMS compatibility contract is not active' unless contract == { 'version' => 0 }
    indexes = CollectIndexInventory.expected(
      Dir[File.join(ROOT, 'supabase/migrations/*.sql')].sort.map { |path| File.read(path) }
    )
    raise 'Required hosted index is missing' unless
      CollectProductionCutover.query(token, CollectIndexInventory.query(indexes)).empty?
    inventory = CollectProductionCutover.query(token, <<~SQL).first
      SELECT
        (SELECT count(*) FROM supabase_migrations.schema_migrations) AS migrations,
        (SELECT count(*) FROM collect_hybrid.member_records) AS member_records,
        (SELECT count(*) FROM collect_admin_access.whatsapp_approvals) AS platform_whatsapp_approvals,
        NOT EXISTS (
          SELECT 1 FROM public.profiles profile
          LEFT JOIN collect_hybrid.member_records member ON member.linked_user_id=profile.id
          WHERE member.id IS NULL OR member.id<>profile.id OR member.collect_id<>profile.public_id OR member.origin<>'app'
        ) AS member_backfill_valid;
    SQL
    raise 'Hosted identity backfill is inconsistent' unless
      inventory['migrations'] == TARGET_COUNT && inventory['member_backfill_valid'] == true
    {
      migration_hashes: '7 exact source matches',
      disabled_flags: flags,
      installed_client_sms_contract_version: contract.fetch('version'),
      readiness: readiness_checks(token),
      indexes: 'pass',
      inventory: inventory
    }
  end

  def self.run(mode, output)
    raise 'Invalid cutover mode' unless %w[plan apply readback].include?(mode)
    raise 'New JSON report required' unless output.end_with?('.json') && !File.exist?(output)
    raise 'Linked project mismatch' unless
      File.read(File.join(ROOT, 'supabase/.temp/project-ref')).strip == REF
    entries = manifest
    rehearsal!(entries)
    STDOUT.sync = true
    puts 'Awaiting release credential on non-echoing stdin.'
    raw = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
    credential = JSON.parse(raw.to_s)
    raw&.clear
    raise 'Wrong credential scope' unless credential.fetch('project_url') == "https://#{REF}.supabase.co"
    token = credential.fetch('access_token')
    raise 'Expected Management API credential' unless token.start_with?('sbp_')
    report = {
      started_at: Time.now.utc.iso8601, project: REF, mode: mode,
      result: 'IN_PROGRESS', migration_commit_attempted: false,
      provider_sends: 0, network_mutations: 0,
      edge_function_deployments: 0, operational_flags_enabled: 0
    }
    begin
      project = CollectProductionCutover.request(token, '')
      raise 'Wrong or unhealthy authenticated project' unless
        project['id'] == REF && project['name'] == 'COOL' && project['status'] == 'ACTIVE_HEALTHY'
      remote = CollectProductionCutover.history(token)
      if mode == 'readback'
        report[:checks] = readback(token, entries)
      else
        plan = CollectHostedPreflight.plan(remote, File.join(ROOT, 'supabase/migrations'))
        expected = entries.map { |entry| entry.reject { |key, _| key == 'content' } }
        raise 'Reviewed pending set changed' unless
          remote.length == BASELINE_COUNT && plan[:pending] == expected &&
          plan[:remote_only].empty? && plan[:history_holes].empty?
        sql = transaction(entries, remote)
        report[:baseline_migrations] = remote.length
        report[:migrations] = expected
        report[:atomic_transaction_sha256] = Digest::SHA256.hexdigest(sql)
        puts 'Exact seven migration hashes and 112-migration baseline verified.'
        if mode == 'apply'
          projections = CollectProductionCutover.projections(token)
          required = %w[profiles payments ledger_entries raw_payment_sms bank_transactions]
          raise 'Missing protected production table' unless required.all? { |table| projections.key?(table) }
          before = CollectProductionCutover.fingerprint(token, projections)
          report[:migration_commit_attempted] = true
          CollectProductionCutover.query(token, sql, write: true)
          after = CollectProductionCutover.fingerprint(token, projections)
          report[:protected_data] = { before: before, after: after, unchanged: before == after }
          raise 'Protected production data changed; stop for investigation' unless before == after
          report[:checks] = readback(token, entries)
        end
      end
      report[:result] = mode == 'apply' ?
        'SEVEN_MIGRATIONS_DEPLOYED_FLAGS_OFF_NOT_FULL_PRODUCTION_GO' : 'PASS'
    rescue StandardError => error
      report[:result] = 'FAILED_REQUIRES_READBACK_BEFORE_RETRY'
      report[:error] = error.message.gsub(token, '[redacted]')
      warn "Hybrid cutover stopped: #{report[:error]}"
    ensure
      report[:finished_at] = Time.now.utc.iso8601
      File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.pretty_generate(report) + "\n")
      end
      puts JSON.generate(report: output, result: report[:result])
    end
    report[:result] != 'FAILED_REQUIRES_READBACK_BEFORE_RETRY'
  ensure
    raw&.clear
    token&.clear
    credential&.clear
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: collect_hybrid_production_cutover.rb plan|apply|readback NEW_REPORT.json') unless ARGV.length == 2
  exit(CollectHybridProductionCutover.run(*ARGV) ? 0 : 1)
end
