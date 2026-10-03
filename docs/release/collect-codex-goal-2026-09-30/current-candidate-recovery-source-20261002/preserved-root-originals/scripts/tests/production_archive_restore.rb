# Restore approved encrypted production archives into a disposable RAM-only,
# network-disabled local cluster. Never run providers. Candidate migration
# rehearsal requires its explicit local-only flag and exact reviewed hashes.
require_relative '../audits/collect_encrypted_database_backup'

ROOT = File.expand_path('../..', __dir__)
DB_REPORT = File.join(ROOT, 'docs/release/ENCRYPTED_PRODUCTION_DATABASE_BACKUP_V2_2026-09-03.json')
ROLE_REPORT = File.join(ROOT, 'docs/release/ENCRYPTED_PRODUCTION_ROLES_BACKUP_2026-09-03.json')
GRAPHQL_REPORT = File.join(ROOT, 'docs/release/SUPABASE_EXTENSION_RECOVERY_METADATA_2026-09-03.json')

def preserve_extension_owners(sql_text, metadata, roles)
  raise 'Extension metadata source mismatch' unless metadata['project'] == REF
  owners = metadata.fetch('wrapper').fetch('extension_owners').to_h { |row| [row.fetch('name'), row.fetch('owner')] }
  raise 'Unexpected extension owner' unless owners.values.all? { |owner| %w[postgres supabase_admin].include?(owner) }
  postgres_attributes = roles.lines.select { |line| line.start_with?('ALTER ROLE postgres WITH NOSUPERUSER ') }
  raise 'Postgres source role attributes missing' unless postgres_attributes.one?
  seen = []
  result = sql_text.gsub(/^CREATE EXTENSION IF NOT EXISTS (?:"([a-z_-]+)"|([a-z_]+)) WITH SCHEMA [a-z_]+;$/) do |statement|
    extension = Regexp.last_match(1) || Regexp.last_match(2)
    owner = owners.fetch(extension)
    seen << extension
    next statement if owner == 'supabase_admin'
    # Supabase's managed postgres role can install these extensions. The bare
    # isolated cluster needs temporary local superuser status to reproduce it.
    # Restore every original attribute immediately, before remaining objects.
    "ALTER ROLE postgres SUPERUSER;\nSET SESSION AUTHORIZATION postgres;\n#{statement}\n" +
      "RESET SESSION AUTHORIZATION;\n#{postgres_attributes.first}"
  end
  raise 'Extension creation set mismatch' unless seen.sort == (owners.keys - ['plpgsql']).sort
  result
end

def database_restore_properties(schema)
  sections = schema.split(/(?=^-- Name: )/)
  properties = sections.select { |s| s.start_with?('-- Name: postgres; Type: DATABASE PROPERTIES;') }
  grants = sections.select { |s| s.start_with?('-- Name: DATABASE postgres; Type: ACL;') }
  raise 'Source database properties/ACL missing or duplicate' unless properties.one? && grants.one?
  statements = properties.first.lines.select { |line| line.start_with?('ALTER DATABASE postgres SET ') } +
    grants.first.lines.select { |line| line.match?(/\A(?:GRANT|REVOKE) .* ON DATABASE postgres /) }
  raise 'Source database settings or grants missing' unless statements.length >= 2
  statements.join
end

def add_graphql_bootstrap(sql_text, metadata)
  definition = metadata.fetch('wrapper').fetch('definition')
  raise 'GraphQL metadata hash mismatch' unless metadata['project'] == REF &&
    Digest::SHA256.hexdigest(definition) == metadata.fetch('definition_sha256') &&
    metadata.dig('wrapper', 'owner') == 'supabase_admin' && metadata.dig('wrapper', 'extension') == 'pg_graphql'
  marker = "\nGRANT ALL ON FUNCTION graphql_public.graphql("
  raise 'Unexpected GraphQL ACL placement' unless sql_text.scan(marker).length == 4
  supplement = definition + ";\n" +
    "ALTER FUNCTION graphql_public.graphql(text,text,jsonb,jsonb) OWNER TO supabase_admin;\n" +
    "ALTER EXTENSION pg_graphql ADD FUNCTION graphql_public.graphql(text,text,jsonb,jsonb);\n"
  sql_text.sub(marker, "\n#{supplement}#{marker}")
end

def read_archive(report_path, filename)
  report = JSON.parse(File.read(report_path))
  raise 'Source capture not verified' unless report['project'] == REF &&
    report.dig('archive', 'hash_verified_after_remount') == true && report.dig('cleanup', 'vault_detached') == true
  identifier = report.fetch('vault').fetch('keychain_account')
  mounted = false
  begin
    info = vault('readonly', identifier)
    mounted = true
    data = File.binread(File.join(info.fetch('mount'), filename))
    raise 'Encrypted source hash mismatch' unless Digest::SHA256.hexdigest(data) == report.fetch('archive').fetch('sha256')
    [data, report]
  ensure
    vault('detach', identifier) if mounted
  end
end

def data_fingerprint(sql_text)
  tables = {}
  current = nil
  rows = []
  sequences = []
  other_data = []
  sql_text.each_line do |line|
    if current
      if line == "\\.\n"
        raise 'Duplicate COPY section' if tables.key?(current)
        tables[current] = { rows: rows.length, sha256: Digest::SHA256.hexdigest(rows.sort.join) }
        current = nil
        rows = []
      else
        rows << line
      end
    elsif line.start_with?('COPY ') && line.end_with?(" FROM stdin;\n")
      current = line.strip
    elsif line.start_with?('SELECT pg_catalog.setval(')
      sequences << line.strip
    elsif line.match?(/\A(?:SELECT.*lo_|SELECT.*lowrite|SELECT.*lo_put|INSERT INTO)/)
      other_data << line
    end
  end
  raise 'Incomplete COPY section' if current
  { tables: tables, sequences: sequences.sort, other_data: other_data.sort }
end

def normalized_dump(sql_text)
  normalized = sql_text.lines.reject do |line|
    line.start_with?('\\restrict ', '\\unrestrict ', '-- Dumped from database version',
                     '-- Dumped by pg_dump version', '-- Started on ', '-- Completed on ')
  end.join
  # pg_dump orders policy roles by internal OID, which changes on fresh initdb.
  normalized = normalized.gsub('FOR SELECT TO authenticated, anon USING (enabled);',
                               'FOR SELECT TO anon, authenticated USING (enabled);')
  # Adjacent default-GRANT statements commute; role OIDs change their dump order.
  # Never reorder across a REVOKE or drop any privilege/owner/grantee text.
  normalized = normalized.gsub(/(?:^ALTER DEFAULT PRIVILEGES FOR ROLE [a-z_]+ IN SCHEMA [a-z_]+ GRANT [A-Z, ]+ ON (?:SEQUENCES|FUNCTIONS|TABLES) TO [a-z_]+(?: WITH GRANT OPTION)?;\n)+/) do |grants|
    grants.lines.sort.join
  end
  # PostgreSQL flattens this nested AND group when reparsing the archived CHECK.
  # Keep the exact operands, bounds, remaining parentheses and NOT VALID state.
  normalized.gsub('CHECK ((((char_length(TRIM(BOTH FROM title)) >= 1) AND (char_length(TRIM(BOTH FROM title)) <= 120)) AND',
                  'CHECK (((char_length(TRIM(BOTH FROM title)) >= 1) AND (char_length(TRIM(BOTH FROM title)) <= 120) AND').strip
end

if $PROGRAM_NAME == __FILE__
  rehearse = !!ARGV.delete('--rehearse-migrations')
  abort('Usage: production_archive_restore.rb NEW_REPORT.json [--rehearse-migrations]') unless ARGV.length == 1
  output = ARGV[0]
  raise 'New JSON report required' unless output.end_with?('.json') && !File.exist?(output)
  STDOUT.sync = true
  suffix = Time.now.utc.strftime('%Y%m%dT%H%M%S').downcase + '-' + SecureRandom.hex(3)
  target = 'collect-recovery-' + suffix
  evidence_id = 'collect-restore-' + suffix
  report = { started_at: Time.now.utc.iso8601, mode: 'isolated_local_production_archive_restore',
    source_project: REF, container: target, hosted_changes: false, provider_sends: false,
    result: 'IN_PROGRESS', cleanup: {}, limitations: [
      'Storage object bytes and provider configuration are outside this database restore',
      'Global role passwords intentionally omitted from the role archive',
      'Role and database captures were separate snapshots',
      'No off-site disaster recovery, key escrow or owner RPO/RTO acceptance established'] }
  created = false
  mounted = false
  begin
    archive, database_report = read_archive(DB_REPORT, 'database.dump')
    roles, role_report = read_archive(ROLE_REPORT, 'roles.sql')
    original_roles = roles.dup
    # PostgreSQL 16+ records role ownership against its bootstrap superuser.
    # Match production's bootstrap identity, keeping every ALTER/GRANT intact.
    raise 'Unexpected bootstrap role export' unless roles.lines.count { |line| line == "CREATE ROLE supabase_admin;\n" } == 1 &&
      roles.match?(/^ALTER ROLE supabase_admin WITH SUPERUSER /)
    roles = roles.sub("CREATE ROLE supabase_admin;\n", '')
    report[:bootstrap] = { role: 'supabase_admin', already_created_role_statement_omitted: 1,
      role_attributes_and_grantors_preserved: true }
    report[:source_database_sha256] = database_report.dig('archive', 'sha256')
    report[:source_roles_sha256] = role_report.dig('archive', 'sha256')
    vault('create', evidence_id)
    evidence = vault('attach', evidence_id)
    mounted = true
    report[:encrypted_evidence_vault] = evidence.fetch('image')
    log_dir = evidence.fetch('mount')
    start = <<~'SH'
      set -eu
      initdb -D /run/collect/data -U supabase_admin --auth-local=trust --auth-host=reject --no-instructions \
        --encoding=UTF8 --locale-provider=icu --icu-locale=en-US --locale=en_US.UTF-8
      exec postgres -D /run/collect/data -c listen_addresses='' -c unix_socket_directories=/run/collect \
        -c collect.recovery_drill=production-archive-v1 \
        -c shared_preload_libraries=pg_cron,pg_net -c cron.database_name=postgres -c cron.launch_active_jobs=off \
        -c pg_net.database_name=template1 -c pg_net.batch_size=0 \
        -c logging_collector=off -c log_statement=none -c log_min_error_statement=panic \
        -c log_error_verbosity=terse -c log_min_messages=panic
    SH
    out, _err, status = command('docker', 'run', '-d', '--name', target, '--label', 'collect.recovery=production-archive-drill',
      '--network', 'none', '--read-only', '--cap-drop=ALL', '--security-opt=no-new-privileges',
      '--memory', '2g', '--memory-swap', '2g', '--user', '101:102',
      '--tmpfs', '/run/collect:rw,noexec,nosuid,size=1g,mode=0700,uid=101,gid=102',
      '--tmpfs', '/tmp:rw,noexec,nosuid,size=64m,mode=1777',
      '--entrypoint', 'sh', IMAGE, '-c', start)
    raise 'Isolated container creation failed' unless status.success?
    created = true
    raw, _, status = command('docker', 'inspect', target)
    raise 'Container inspection failed' unless status.success?
    config = JSON.parse(raw).first
    host = config.fetch('HostConfig')
    raise 'Restore isolation guard failed' unless host['NetworkMode'] == 'none' && host['ReadonlyRootfs'] == true &&
      host['Memory'] == host['MemorySwap'] && host['Memory'] == 2 * 1024**3 &&
      host.fetch('PortBindings', {}).to_h.empty? &&
      config.fetch('Mounts').all? { |mount| mount['Type'] == 'tmpfs' }
    report[:isolation] = { network: 'none', published_ports: 0, readonly_rootfs: true,
      database_storage: 'tmpfs', container_swap_disabled: true }
    ready = false
    30.times do
      _, _, state = command('docker', 'exec', target, 'pg_isready', '-h', '/run/collect', '-U', 'supabase_admin', '-d', 'postgres')
      if state.success?
        ready = true
        break
      end
      sleep 1
    end
    raise 'Isolated database did not start' unless ready
    sql = lambda do |statement|
      result, error, state = command('docker', 'exec', '-i', target, 'psql', '-XqAt', '-h', '/run/collect',
        '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', input: statement)
      unless state.success?
        private_write(File.join(log_dir, "sql-error-#{SecureRandom.hex(3)}.log"), error)
        raise 'Isolated SQL failed; details only in encrypted evidence'
      end
      result.strip
    end
    raise 'Scheduler or network guard failed' unless sql.call("select current_setting('cron.launch_active_jobs')='off' and current_setting('listen_addresses')='' and current_setting('pg_net.database_name')='template1' and current_setting('pg_net.batch_size')='0';") == 't'
    report[:isolation][:http_worker] = 'bound_to_empty_template1_with_zero_batch_size'
    puts 'Isolated RAM-only cluster ready; network and scheduler guards verified.'
    sql.call(roles)
    roles.clear
    report[:roles_restored] = true
    # This exact owner/locale is checked against the immutable archive below.
    sql.call('ALTER DATABASE postgres OWNER TO postgres;')
    puts 'Global role definitions restored without passwords.'
    restore_sql, error, state = command('docker', 'run', '--rm', '-i', '--read-only', '--network', 'none',
      '--entrypoint', 'pg_restore', IMAGE, '--file=-', input: archive)
    raise 'Archive SQL conversion failed' unless state.success?
    graphql_metadata = JSON.parse(File.read(GRAPHQL_REPORT))
    restore_sql = add_graphql_bootstrap(restore_sql, graphql_metadata)
    restore_sql = preserve_extension_owners(restore_sql, graphql_metadata, original_roles)
    report[:graphql_bootstrap] = { definition_sha256: graphql_metadata.fetch('definition_sha256'),
      captured_extension_member_restored_before_its_acl: true, source_archive_modified: false }
    _out, error, state = command('docker', 'exec', '-i', target, 'psql', '-w', '-XqAt', '-h', '/run/collect',
      '-U', 'supabase_admin', '-d', 'postgres', '--single-transaction', '-v', 'ON_ERROR_STOP=1', '-f', '-', input: restore_sql)
    restore_sql.clear
    private_write(File.join(log_dir, 'pg-restore.log'), error)
    raise 'Archive restore failed; details only in encrypted evidence' unless state.success?
    report[:database_restored] = true
    report[:migration_count] = sql.call('select count(*) from supabase_migrations.schema_migrations;').to_i
    raise 'Restored migration count mismatch' unless report[:migration_count] == database_report.dig('source_check', 'migrations')
    installed = JSON.parse(sql.call("select jsonb_agg(jsonb_build_object('name',extname,'version',extversion) order by extname) from pg_extension;"))
    raise 'Restored extension versions mismatch' unless installed == graphql_metadata.dig('wrapper', 'installed_extensions')
    report[:extension_versions_match] = true
    raise 'Restored scheduler enabled unexpectedly' unless sql.call("select current_setting('cron.launch_active_jobs')='off';") == 't'
    puts 'Database restored in one transaction; 97-migration history verified.'
    original_sql, error, state = command('docker', 'run', '--rm', '-i', '--read-only', '--network', 'none',
      '--entrypoint', 'pg_restore', IMAGE, '--data-only', '--file=-', input: archive)
    raise 'Source data inspection failed' unless state.success?
    source_data = data_fingerprint(original_sql)
    raise 'No source table data found' if source_data[:tables].empty?
    original_sql.clear
    restored_sql, error, state = command('docker', 'exec', target, 'pg_dump', '-w', '-h', '/run/collect',
      '-U', 'supabase_admin', '-d', 'postgres', '--data-only')
    raise 'Restored data inspection failed' unless state.success?
    restored_data = data_fingerprint(restored_sql)
    restored_sql.clear
    raise 'Table-data or sequence fingerprint mismatch' unless source_data == restored_data
    report[:data_comparison] = { table_copy_sections: source_data[:tables].length,
      total_rows: source_data[:tables].values.sum { |table| table[:rows] },
      sequence_statements: source_data[:sequences].length, other_data_statements: source_data[:other_data].length,
      all_fingerprints_match: true }
    original_schema, _, state = command('docker', 'run', '--rm', '-i', '--read-only', '--network', 'none',
      '--entrypoint', 'pg_restore', IMAGE, '--schema-only', '--create', '--file=-', input: archive)
    raise 'Original schema inspection failed' unless state.success?
    sql.call(database_restore_properties(original_schema))
    expected_create = "CREATE DATABASE postgres WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = icu LOCALE = 'en_US.UTF-8' ICU_LOCALE = 'en-US';"
    raise 'Unexpected source database properties' unless original_schema.lines.map(&:strip).include?(expected_create) &&
      original_schema.lines.map(&:strip).include?('ALTER DATABASE postgres OWNER TO postgres;')
    report[:database_properties] = { owner: 'postgres', encoding: 'UTF8', locale_provider: 'icu', locale: 'en_US.UTF-8', icu_locale: 'en-US' }
    restored_schema, _, state = command('docker', 'exec', target, 'pg_dump', '-w', '-h', '/run/collect',
      '-U', 'supabase_admin', '-d', 'postgres', '--schema-only', '--create')
    raise 'Restored schema inspection failed' unless state.success?
    original_schema = normalized_dump(original_schema)
    restored_schema = normalized_dump(restored_schema)
    if original_schema != restored_schema
      private_write(File.join(log_dir, 'original-schema.sql'), original_schema)
      private_write(File.join(log_dir, 'restored-schema.sql'), restored_schema)
      raise 'Schema/ACL dump comparison differs; details only in encrypted evidence'
    end
    report[:schema_comparison] = { sha256: Digest::SHA256.hexdigest(original_schema), match: true,
      normalized_only: 'tool comments/restrict keys, order of policy roles/adjacent default GRANTs, and one exact redundant CHECK AND grouping' }
    restored_roles, _, state = command('docker', 'exec', target, 'pg_dumpall', '-w', '-h', '/run/collect',
      '-U', 'supabase_admin', '-l', 'postgres', '--roles-only', '--no-role-passwords')
    raise 'Restored roles inspection failed' unless state.success?
    raise 'Global role attributes/grants differ' unless normalized_dump(original_roles) == normalized_dump(restored_roles)
    report[:roles_comparison] = { match: true, sha256: Digest::SHA256.hexdigest(normalized_dump(original_roles)) }
    report[:result] = 'DATABASE_RESTORE_AND_DATA_COMPARISON_PASS_NOT_FULL_RECOVERY_ACCEPTANCE'
    puts 'Table data, sequences, schema/ACLs and global role definitions match.'
    if rehearse
      require_relative 'production_upgrade_rehearsal'
      ProductionUpgradeRehearsal.run(root: ROOT, sql: sql, source_data: source_data, report: report)
      report[:result] = 'DATABASE_RESTORE_AND_UPGRADE_REHEARSAL_PASS_NOT_PRODUCTION_GO'
    end
  rescue StandardError => error
    report[:result] = 'RESTORE_REHEARSAL_FAILED_NO_HOSTED_CHANGES'
    report[:error] = error.message
    puts "Restore rehearsal stopped: #{error.message}"
  ensure
    archive&.clear
    roles&.clear
    original_roles&.clear
    if created
      raw, _, state = command('docker', 'inspect', target)
      begin
        owned = state.success? && JSON.parse(raw).first.dig('Config', 'Labels', 'collect.recovery') == 'production-archive-drill'
        raise 'Container ownership guard failed' unless owned
        _, _, state = command('docker', 'rm', '-f', target)
        raise 'Container cleanup failed' unless state.success?
        report[:cleanup][:ram_only_container_removed] = true
      rescue StandardError
        report[:cleanup][:container_requires_attention] = true
      end
    end
    if mounted
      begin
        vault('detach', evidence_id)
        report[:cleanup][:evidence_vault_detached] = true
      rescue StandardError
        report[:cleanup][:evidence_vault_requires_attention] = true
      end
    end
    report[:finished_at] = Time.now.utc.iso8601
    private_write(output, JSON.pretty_generate(report) + "\n")
  end
  exit(report[:result].start_with?('DATABASE_RESTORE') && !report[:cleanup].keys.any? { |key| key.to_s.end_with?('requires_attention') } ? 0 : 1)
end
