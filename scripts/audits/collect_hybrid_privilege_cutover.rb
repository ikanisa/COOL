# Approved 2026-09-03 forward-only repair for two accidentally exposed
# collect_hybrid routines. This runner accepts exactly the reviewed 92500
# migration on the 119-migration production baseline. It never deploys Edge
# Functions, enables flags, sends provider messages, changes network rules, or
# publishes client applications.
require 'json'
require 'digest'
require 'io/console'
require 'time'
require_relative 'collect_production_cutover'
require_relative 'collect_hosted_preflight'
require_relative 'collect_index_inventory'

module CollectHybridPrivilegeCutover
  ROOT = File.expand_path('../..', __dir__)
  REF = CollectProductionCutover::REF
  SOURCE = 'docs/release/SUPABASE_CONTINUATION_PREFLIGHT_V4_2026-09-03.json'.freeze
  REHEARSAL = 'docs/release/PRODUCTION_COPY_UPGRADE_REHEARSAL_V23_2026-09-03.json'.freeze
  BASELINE_COUNT = 119
  TARGET_COUNT = 120
  VERSION = '20260903092500'.freeze
  NAME = 'revoke_hybrid_internal_function_execute'.freeze
  SHA256 = '07c9c0897642c6c0df137c256ffa25e6bdcf754622e26a53ca33b09842766c79'.freeze
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
    raise 'Expected exactly the reviewed privilege migration' unless
      entries == [{
        'version' => VERSION,
        'name' => NAME,
        'file' => "#{VERSION}_#{NAME}.sql",
        'sha256' => SHA256
      }]
    entry = entries.first
    content = File.read(File.join(ROOT, 'supabase/migrations', entry.fetch('file')))
    raise 'Reviewed privilege migration bytes changed' unless
      Digest::SHA256.hexdigest(content) == SHA256
    entry.merge('content' => content)
  end

  def self.rehearsal!(entry)
    rehearsal = JSON.parse(File.read(File.join(ROOT, REHEARSAL)))
    raise 'Actual production-copy privilege rehearsal did not pass' unless
      rehearsal['source_project'] == REF &&
      rehearsal['hosted_changes'] == false &&
      rehearsal['provider_sends'] == false &&
      rehearsal['result'] == 'DATABASE_RESTORE_AND_UPGRADE_REHEARSAL_PASS_NOT_PRODUCTION_GO' &&
      rehearsal.dig('migration_rehearsal', 'status') == 'pass' &&
      rehearsal.dig('migration_rehearsal', 'migration_count') == TARGET_COUNT &&
      rehearsal.dig('cleanup', 'ram_only_container_removed') == true &&
      rehearsal.dig('cleanup', 'evidence_vault_detached') == true
    rehearsed = rehearsal.dig('migration_rehearsal', 'migrations').last
    expected = entry.slice('file', 'sha256').merge('status' => 'pass')
    raise 'Rehearsed privilege migration differs from cutover manifest' unless
      rehearsed.slice('file', 'sha256', 'status') == expected
  end

  def self.transaction(entry, remote)
    versions = remote.map { |row| row.fetch('version').to_s }
    raise 'Production migration history changed' unless
      versions.length == BASELINE_COUNT &&
      versions.uniq.length == BASELINE_COUNT &&
      versions == versions.sort &&
      !versions.include?(VERSION)
    content = entry.fetch('content')
    tag = '$collect_privilege_cutover_source$'
    raise 'Migration quoting delimiter collision' if content.include?(tag)
    <<~SQL
      BEGIN;
      SET LOCAL lock_timeout='5s';
      SET LOCAL statement_timeout='90s';
      DO $cutover_guard$ BEGIN
        IF NOT pg_try_advisory_xact_lock(20260903, 92500) THEN
          RAISE EXCEPTION 'Another privilege cutover is running';
        END IF;
        IF (SELECT array_agg(version::text ORDER BY version) FROM supabase_migrations.schema_migrations)
          IS DISTINCT FROM ARRAY[#{versions.map { |version| "'#{version}'" }.join(',')}]::text[] THEN
          RAISE EXCEPTION 'Production migration history changed';
        END IF;
      END $cutover_guard$;
      #{CollectProductionCutover.body(content)}
      ;
      INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
      VALUES ('#{VERSION}','#{NAME}',ARRAY[#{tag}#{content}#{tag}]);
      NOTIFY pgrst,'reload schema';
      COMMIT;
    SQL
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

  def self.readback(token, entry)
    history = CollectProductionCutover.history(token)
    raise 'Target migration history is incomplete' unless
      history.length == TARGET_COUNT && history.last == {
        'version' => VERSION, 'name' => NAME
      }
    deployed = CollectProductionCutover.query(token, <<~SQL).first
      SELECT version, encode(extensions.digest(statements[1], 'sha256'), 'hex') AS sha256
      FROM supabase_migrations.schema_migrations WHERE version='#{VERSION}';
    SQL
    raise 'Hosted privilege migration source hash differs' unless
      deployed == entry.slice('version', 'sha256')

    boundary = CollectProductionCutover.catalog_query(token, <<~SQL).first
      SELECT
        NOT has_function_privilege('public', 'collect_hybrid.enqueue_sms_receipt_from_snapshot()', 'execute')
          AND NOT has_function_privilege('anon', 'collect_hybrid.enqueue_sms_receipt_from_snapshot()', 'execute')
          AND NOT has_function_privilege('authenticated', 'collect_hybrid.enqueue_sms_receipt_from_snapshot()', 'execute')
          AND NOT has_function_privilege('service_role', 'collect_hybrid.enqueue_sms_receipt_from_snapshot()', 'execute')
          AS sms_trigger_internal_only,
        NOT has_function_privilege('public', 'collect_hybrid.claim_verified_current_account()', 'execute')
          AND NOT has_function_privilege('anon', 'collect_hybrid.claim_verified_current_account()', 'execute')
          AND NOT has_function_privilege('authenticated', 'collect_hybrid.claim_verified_current_account()', 'execute')
          AND NOT has_function_privilege('service_role', 'collect_hybrid.claim_verified_current_account()', 'execute')
          AS account_claim_internal_only,
        has_function_privilege('authenticated', 'public.claim_verified_current_account()', 'execute')
          AND NOT has_function_privilege('public', 'public.claim_verified_current_account()', 'execute')
          AND NOT has_function_privilege('anon', 'public.claim_verified_current_account()', 'execute')
          AND NOT has_function_privilege('service_role', 'public.claim_verified_current_account()', 'execute')
          AS authenticated_wrapper_only,
        EXISTS (
          SELECT 1 FROM pg_proc routine
          JOIN pg_namespace namespace ON namespace.oid=routine.pronamespace
          WHERE namespace.nspname='public'
            AND routine.proname='claim_verified_current_account'
            AND routine.pronargs=0
            AND routine.prosecdef
            AND 'search_path=""'=ANY(routine.proconfig)
        ) AS wrapper_fixed_path_security_definer,
        NOT EXISTS (
          SELECT 1 FROM information_schema.routine_privileges grant_row
          WHERE grant_row.specific_schema='collect_hybrid'
            AND grant_row.grantee IN ('PUBLIC','anon','authenticated','service_role')
        ) AS no_collect_hybrid_caller_grants;
    SQL
    raise 'Hosted internal function privilege boundary is not closed' unless
      boundary.values.all? { |value| value == true }

    flags = CollectProductionCutover.query(token, <<~SQL)
      SELECT key, enabled FROM public.feature_flags
      WHERE key IN (#{DISABLED_FLAGS.map { |flag| "'#{flag}'" }.join(',')})
      ORDER BY key;
    SQL
    raise 'A controlled-rollout flag is missing or enabled' unless
      flags.map { |row| row.fetch('key') }.sort == DISABLED_FLAGS.sort &&
      flags.all? { |row| row['enabled'] == false }
    contract = CollectProductionCutover.catalog_query(
      token, 'SELECT public.attested_sms_contract_version() AS version;'
    ).first
    raise 'Installed-client SMS compatibility contract is not active' unless
      contract == { 'version' => 0 }
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
      migration_sha256: SHA256,
      function_boundary: boundary,
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
    entry = manifest
    rehearsal!(entry)
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
        report[:checks] = readback(token, entry)
      else
        plan = CollectHostedPreflight.plan(remote, File.join(ROOT, 'supabase/migrations'))
        expected = [entry.reject { |key, _| key == 'content' }]
        raise 'Reviewed pending set changed' unless
          remote.length == BASELINE_COUNT &&
          plan[:pending] == expected &&
          plan[:remote_only].empty? &&
          plan[:history_holes].empty?
        sql = transaction(entry, remote)
        report[:baseline_migrations] = remote.length
        report[:migrations] = expected
        report[:atomic_transaction_sha256] = Digest::SHA256.hexdigest(sql)
        puts 'Exact privilege migration hash and 119-migration baseline verified.'
        if mode == 'apply'
          projections = CollectProductionCutover.projections(token)
          required = %w[profiles payments ledger_entries raw_payment_sms bank_transactions]
          raise 'Missing protected production table' unless
            required.all? { |table| projections.key?(table) }
          before = CollectProductionCutover.fingerprint(token, projections)
          report[:migration_commit_attempted] = true
          CollectProductionCutover.query(token, sql, write: true)
          after = CollectProductionCutover.fingerprint(token, projections)
          report[:protected_data] = { before: before, after: after, unchanged: before == after }
          raise 'Protected production data changed; stop for investigation' unless before == after
          report[:checks] = readback(token, entry)
        end
      end
      report[:result] = mode == 'apply' ?
        'PRIVILEGE_BOUNDARY_REPAIRED_FLAGS_OFF_NOT_FULL_PRODUCTION_GO' : 'PASS'
    rescue StandardError => error
      report[:result] = 'FAILED_REQUIRES_READBACK_BEFORE_RETRY'
      report[:error] = error.message.gsub(token, '[redacted]')
      warn "Privilege cutover stopped: #{report[:error]}"
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
  abort('Usage: collect_hybrid_privilege_cutover.rb plan|apply|readback NEW_REPORT.json') unless ARGV.length == 2
  exit(CollectHybridPrivilegeCutover.run(*ARGV) ? 0 : 1)
end
