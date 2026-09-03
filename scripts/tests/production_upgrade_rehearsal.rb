# Called only inside the RAM-only, network-disabled production archive drill.
# No remote connection, provider sends, or production mutation is supported.
require_relative '../audits/collect_index_inventory'

module ProductionUpgradeRehearsal
  EXCLUDED_TABLES = %w[supabase_migrations.schema_migrations public.feature_flags public.admin_queue_filter_options].freeze

  def self.manifest(root)
    source = JSON.parse(File.read(File.join(root, 'docs/release/SUPABASE_PREFLIGHT_CURRENT_2026-09-02.json')))
    raise 'Unexpected source project' unless source.dig('project', 'id') == REF
    pending = source.dig('checks', 'migrations', 'pending')
    raise 'Expected exactly 14 reviewed migrations' unless pending.length == 14
    pending.map do |entry|
      file = entry.fetch('file')
      raise 'Unexpected migration filename' unless file == "#{entry.fetch('version')}_#{entry.fetch('name')}.sql" && file.match?(/\A[0-9]{14}_[a-z_]+\.sql\z/)
      content = File.read(File.join(root, 'supabase/migrations', file))
      raise 'Reviewed migration content changed' unless Digest::SHA256.hexdigest(content) == entry.fetch('sha256')
      entry.merge('content'=>content)
    end
  end

  def self.projection(headers)
    headers.each_with_object([]) do |header, result|
      match = /\ACOPY ([a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*) \(([^;\n]+)\) FROM stdin;\z/.match(header)
      raise 'Unexpected archived COPY identifier' unless match
      table, columns = match.captures
      raise 'Unexpected archived column identifier' unless columns.split(', ').all? { |column| column.match?(/\A(?:[a-z_][a-z0-9_]*|"[a-z_][a-z0-9_]*")\z/) }
      next if EXCLUDED_TABLES.include?(table)
      next if table == 'public.app_realtime_events' # Verified append-only below.
      # The official-group origin backfill legitimately touches updated_at.
      columns = columns.split(', ').reject { |column| table == 'public.collections' && column == 'updated_at' }.join(', ')
      result << [table, columns]
    end
  end

  def self.fingerprint(sql, projections)
    query = "SET timezone='UTC';\n" + projections.map do |table, columns|
      "SELECT 'COPY #{table} (#{columns}) FROM stdin;';\nCOPY (SELECT #{columns} FROM #{table}) TO STDOUT;\nSELECT E'\\\\.';\n"
    end.join
    data_fingerprint(sql.call(query) + "\n")
  end

  def self.appended_events(before, after)
    raise 'Upgrade removed or changed existing realtime events' unless (before - after).empty?
    added = after - before
    raise 'Unexpected upgrade realtime event area' unless added.all? { |row| %w[collections members feature_flags settings].include?(row.split("\t")[1]) }
    {existing_rows_preserved:before.length,new_invalidation_events:added.length,
      areas:added.group_by { |row| row.split("\t")[1] }.transform_values(&:length)}
  end

  def self.run(root:, sql:, source_data:, report:)
    pending = manifest(root)
    versions = JSON.parse(sql.call('SELECT jsonb_agg(version ORDER BY version) FROM supabase_migrations.schema_migrations;'))
    local_versions = Dir[File.join(root,'supabase/migrations/*.sql')].map { |p| File.basename(p).split('_').first }.sort
    raise 'Source history or pending set changed' unless versions.length == 97 && (local_versions - versions) == pending.map { |p| p.fetch('version') }
    projections = projection(source_data.fetch(:tables).keys)
    baseline = fingerprint(sql, projections)
    before_events = sql.call('COPY (SELECT id,area,created_at FROM public.app_realtime_events) TO STDOUT;').lines.map(&:chomp)
    report[:migration_rehearsal] = {hosted_changes: false, migrations: [], excluded_config_tables: EXCLUDED_TABLES,
      excluded_audit_timestamp: 'public.collections.updated_at only; official origin backfill invokes existing timestamp trigger'}
    pending.each do |entry|
      content = entry.fetch('content')
      tag = '$collect_reviewed_migration$'
      raise 'Migration quoting delimiter collision' if content.include?(tag)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sql.call("SET ROLE postgres;\nSET statement_timeout='60s';\nSET lock_timeout='5s';\n#{content}\n" +
        "INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES " +
        "('#{entry.fetch('version')}','#{entry.fetch('name')}',ARRAY[#{tag}#{content}#{tag}]);\nRESET ROLE;")
      report[:migration_rehearsal][:migrations] << {file: entry.fetch('file'),sha256:entry.fetch('sha256'),status:'pass',
        seconds:(Process.clock_gettime(Process::CLOCK_MONOTONIC)-started).round(3)}
      puts "Isolated upgrade passed: #{entry.fetch('file')}"
    end
    raise 'Post-upgrade history differs' unless sql.call('SELECT count(*) FROM supabase_migrations.schema_migrations;') == '111'
    after = fingerprint(sql, projections)
    unless baseline == after
      changed = (baseline[:tables].keys | after[:tables].keys).reject { |key| baseline[:tables][key] == after[:tables][key] }
      report[:migration_rehearsal][:changed_preexisting_tables] = changed.map { |header| header.split(' ')[1] }
      raise 'Upgrade altered preexisting protected data'
    end
    report[:migration_rehearsal][:preexisting_data_preserved] = {tables: baseline[:tables].size,rows:baseline[:tables].values.sum { |v|v[:rows] },match:true}
    after_events = sql.call('COPY (SELECT id,area,created_at FROM public.app_realtime_events) TO STDOUT;').lines.map(&:chomp)
    report[:migration_rehearsal][:realtime_events] = appended_events(before_events, after_events)
    readiness = File.read(File.join(root,'scripts/supabase_production_readiness.sh'))
    patterns = {
      privileges:/    with allowed_table_grants.*?    order by issue;/m,
      columns:/    with roles\(grantee\).*?    order by 1;/m,
      rails:/    with required_authenticated\(routine_name\).*?    order by issue;/m
    }
    patterns.each do |name, pattern|
      query = readiness[pattern] or raise 'Readiness query marker changed'
      result = sql.call("BEGIN READ ONLY;\n#{query}\nROLLBACK;")
      raise "Post-upgrade readiness failed: #{name}" unless result.empty?
    end
    indexes = CollectIndexInventory.expected(Dir[File.join(root,'supabase/migrations/*.sql')].sort.map { |p| File.read(p) })
    raise 'Candidate indexes missing' unless sql.call(CollectIndexInventory.query(indexes)).empty?
    report[:migration_rehearsal][:permission_and_index_gates] = 'pass'
    invariants = sql.call(<<~SQL)
      SELECT NOT EXISTS (SELECT 1 FROM public.profiles p LEFT JOIN collect_hybrid.member_records m ON m.linked_user_id=p.id
        WHERE m.id IS NULL OR m.id<>p.id OR m.collect_id<>p.public_id OR m.origin<>'app')
      AND NOT EXISTS (SELECT 1 FROM public.collection_members WHERE user_id IS NOT NULL AND member_record_id IS DISTINCT FROM user_id)
      AND NOT EXISTS (SELECT 1 FROM public.collections WHERE creation_origin<>CASE WHEN is_platform_sponsored THEN 'platform_sponsored' ELSE 'member_app' END)
      AND NOT EXISTS (SELECT 1 FROM collect_admin_access.whatsapp_approvals)
      AND NOT EXISTS (SELECT 1 FROM public.feature_flags WHERE key='hybrid_member_onboarding' AND enabled);
    SQL
    raise 'Backfill or default access invariant failed' unless invariants == 't'
    report[:migration_rehearsal][:identity_backfill_and_default_access] = 'pass'
    check_file = File.join(root,'scripts/tests/production_upgrade_readbacks.sql')
    raise 'Member/Admin upgrade readbacks failed' unless sql.call(File.read(check_file)).lines.last&.strip == 'PRODUCTION_COPY_READBACKS_PASS'
    report[:migration_rehearsal][:member_and_selected_admin_readbacks] = 'pass_rolled_back_no_provider_sends'
    raise 'Readbacks left data changes behind' unless fingerprint(sql, projections) == after
    raise 'Readbacks left realtime events behind' unless sql.call('COPY (SELECT id,area,created_at FROM public.app_realtime_events) TO STDOUT;').lines.map(&:chomp).sort == after_events.sort
    raise 'Readbacks left an Admin approval behind' unless sql.call('SELECT count(*) FROM collect_admin_access.whatsapp_approvals;') == '0'
    source_data.fetch(:sequences).each do |statement|
      match = /\ASELECT pg_catalog.setval\('([a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*)', ([0-9]+), (true|false)\);\z/.match(statement)
      raise 'Unexpected archived sequence statement' unless match
      values=JSON.parse(sql.call("SELECT jsonb_build_array(last_value,is_called) FROM #{match[1]};"))
      raise 'Migration or readback changed a preexisting sequence' unless values==[match[2].to_i,match[3]=='true']
    end
    report[:migration_rehearsal][:sequences_preserved] = source_data.fetch(:sequences).length
    report[:migration_rehearsal][:migration_count] = 111
    report[:migration_rehearsal][:status] = 'pass'
  end
end
