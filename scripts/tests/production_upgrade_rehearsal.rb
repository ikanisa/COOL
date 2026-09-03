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
    pending += [
      {
        'version' => '20260903083947',
        'name' => 'member_profile_rpc_only_writes',
        'file' => '20260903083947_member_profile_rpc_only_writes.sql',
        'sha256' => '76830e6a6dd32f1b708cefd986470f4b46ae50ad4cba31fca395a5bd1ff3287f'
      },
      {
        'version' => '20260903084000',
        'name' => 'hybrid_direct_ussd_financial_core',
        'file' => '20260903084000_hybrid_direct_ussd_financial_core.sql',
        'sha256' => '1f1a77a04bd0e9e369a134f49a6022e5645fe28798603fd94d316c115774744f'
      },
      {
        'version' => '20260903085000',
        'name' => 'hybrid_roster_import_control_plane',
        'file' => '20260903085000_hybrid_roster_import_control_plane.sql',
        'sha256' => 'dfa19ad7cde6ec400558bda9a8e5e068ee912d62f4e9f6dcc3b6d1ebd88023ac'
      },
      {
        'version' => '20260903090000',
        'name' => 'hybrid_sms_notification_outbox',
        'file' => '20260903090000_hybrid_sms_notification_outbox.sql',
        'sha256' => 'bd0867eefc49cfe1bfb024dd4759f48023769ae1ae41dcba443b1c7146a844f9'
      },
      {
        'version' => '20260903090500',
        'name' => 'admin_sms_receipt_queue',
        'file' => '20260903090500_admin_sms_receipt_queue.sql',
        'sha256' => '9048c2079b4222086ab004f25fa7f5441eb3082094a72ed3d53ff2761e074d7a'
      },
      {
        'version' => '20260903091000',
        'name' => 'hybrid_verified_account_claim',
        'file' => '20260903091000_hybrid_verified_account_claim.sql',
        'sha256' => '18e4c1ccb18d3d1ae80852ea5d173a0cd57722d7777a0adc824a8df347b5e980'
      },
      {
        'version' => '20260903091500',
        'name' => 'hybrid_member_directory_views',
        'file' => '20260903091500_hybrid_member_directory_views.sql',
        'sha256' => '34c2429840f7bed1999d86cac73e49c60ea5db9cebb047db3fef7ec06ee557e5'
      },
      {
        'version' => '20260903092000',
        'name' => 'admin_sms_receipt_failed_filter',
        'file' => '20260903092000_admin_sms_receipt_failed_filter.sql',
        'sha256' => '5a1a55f77f6f7a73eb4484a6312b20eee2cd33d3c2f27b7b0e7a64605a46b514'
      },
      {
        'version' => '20260903092500',
        'name' => 'revoke_hybrid_internal_function_execute',
        'file' => '20260903092500_revoke_hybrid_internal_function_execute.sql',
        'sha256' => '07c9c0897642c6c0df137c256ffa25e6bdcf754622e26a53ca33b09842766c79'
      }
    ]
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

  def self.projection_predicate(table)
    case table
    when 'public.admin_navigation_items'
      " WHERE key <> 'hybrid_sms_receipts'"
    when 'public.admin_queue_specs'
      " WHERE rpc_name <> 'admin_list_hybrid_sms_receipts'"
    else
      ''
    end
  end

  def self.fingerprint(sql, projections)
    query = "SET timezone='UTC';\n" + projections.map do |table, columns|
      predicate = projection_predicate(table)
      "SELECT 'COPY #{table} (#{columns}) FROM stdin;';\nCOPY (SELECT #{columns} FROM #{table}#{predicate}) TO STDOUT;\nSELECT E'\\\\.';\n"
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

  def self.control_metadata_fingerprint(sql)
    {
      feature_flags: sql.call(<<~SQL),
        COPY (
          SELECT to_jsonb(item)
          FROM public.feature_flags item
          WHERE item.key NOT IN (
            'hybrid_member_onboarding',
            'hybrid_direct_ussd_allocation',
            'native_sms_attestation_enforcement',
            'hybrid_sms_notifications',
            'hybrid_verified_account_claim'
          )
          ORDER BY item.key
        ) TO STDOUT;
      SQL
      navigation: sql.call(<<~SQL),
        COPY (
          SELECT to_jsonb(item)
          FROM public.admin_navigation_items item
          WHERE item.key <> 'hybrid_sms_receipts'
          ORDER BY item.key
        ) TO STDOUT;
      SQL
      queue_specs: sql.call(<<~SQL),
        COPY (
          SELECT to_jsonb(item)
          FROM public.admin_queue_specs item
          WHERE item.rpc_name <> 'admin_list_hybrid_sms_receipts'
          ORDER BY item.rpc_name
        ) TO STDOUT;
      SQL
      queue_filters: sql.call(<<~SQL)
        COPY (
          SELECT to_jsonb(item)
          FROM public.admin_queue_filter_options item
          WHERE item.rpc_name NOT IN (
            'admin_list_admin_users',
            'admin_list_hybrid_sms_receipts'
          )
          ORDER BY item.rpc_name, item.filter_kind, item.display_order, item.value
        ) TO STDOUT;
      SQL
    }
  end

  def self.run(root:, sql:, source_data:, report:)
    pending = manifest(root)
    versions = JSON.parse(sql.call('SELECT jsonb_agg(version ORDER BY version) FROM supabase_migrations.schema_migrations;'))
    local_versions = Dir[File.join(root,'supabase/migrations/*.sql')].map { |p| File.basename(p).split('_').first }.sort
    raise 'Source history or pending set changed' unless versions.length == 97 && (local_versions - versions) == pending.map { |p| p.fetch('version') }
    projections = projection(source_data.fetch(:tables).keys)
    baseline = fingerprint(sql, projections)
    control_metadata_before = control_metadata_fingerprint(sql)
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
    raise 'Post-upgrade history differs' unless sql.call('SELECT count(*) FROM supabase_migrations.schema_migrations;') == '120'
    after = fingerprint(sql, projections)
    unless baseline == after
      changed = (baseline[:tables].keys | after[:tables].keys).reject { |key| baseline[:tables][key] == after[:tables][key] }
      report[:migration_rehearsal][:changed_preexisting_tables] = changed.map { |header| header.split(' ')[1] }
      raise 'Upgrade altered preexisting protected data'
    end
    raise 'Upgrade altered unrelated control metadata' unless
      control_metadata_before == control_metadata_fingerprint(sql)
    control_metadata = sql.call(<<~SQL)
      SELECT
        EXISTS (
          SELECT 1 FROM public.admin_navigation_items
          WHERE key = 'hybrid_sms_receipts'
            AND route_path = '/admin/sms-receipts'
            AND required_permission = 'notifications.read'
            AND enabled
        )
        AND EXISTS (
          SELECT 1 FROM public.admin_queue_specs
          WHERE rpc_name = 'admin_list_hybrid_sms_receipts'
            AND required_permission = 'notifications.read'
            AND enabled
            AND metadata ->> 'detail_rpc' = 'admin_get_hybrid_sms_receipt'
        )
        AND (
          SELECT count(*) = 10 AND bool_and(enabled)
          FROM public.admin_queue_filter_options
          WHERE rpc_name = 'admin_list_hybrid_sms_receipts'
        );
    SQL
    raise 'Candidate control metadata contract differs' unless control_metadata == 't'
    report[:migration_rehearsal][:control_metadata] =
      'named candidate rows added; all unrelated rows preserved'
    report[:migration_rehearsal][:preexisting_data_preserved] = {tables: baseline[:tables].size,rows:baseline[:tables].values.sum { |v|v[:rows] },match:true}
    after_events = sql.call('COPY (SELECT id,area,created_at FROM public.app_realtime_events) TO STDOUT;').lines.map(&:chomp)
    report[:migration_rehearsal][:realtime_events] = appended_events(before_events, after_events)
    readiness = File.read(File.join(root,'scripts/supabase_production_readiness.sh'))
    patterns = {
      privileges:/    with allowed_table_grants.*?    order by issue;/m,
      columns:/    with roles\(grantee\).*?    order by 1;/m,
      rails:/    with required_authenticated\(routine_name\).*?    order by issue;/m,
      hybrid_sms:/    with operator_routines\(routine_name\).*?    select issue from issues order by issue;/m
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
      AND NOT EXISTS (SELECT 1 FROM public.feature_flags WHERE key='hybrid_member_onboarding' AND enabled)
      AND EXISTS (SELECT 1 FROM public.feature_flags WHERE key='hybrid_direct_ussd_allocation' AND NOT enabled)
      AND EXISTS (SELECT 1 FROM public.feature_flags WHERE key='native_sms_attestation_enforcement' AND NOT enabled)
      AND EXISTS (SELECT 1 FROM public.feature_flags WHERE key='hybrid_sms_notifications' AND NOT enabled)
      AND EXISTS (SELECT 1 FROM public.feature_flags WHERE key='hybrid_verified_account_claim' AND NOT enabled)
      AND NOT EXISTS (SELECT 1 FROM collect_hybrid.sms_receipt_member_consents)
      AND NOT EXISTS (SELECT 1 FROM collect_hybrid.member_account_claims)
      AND EXISTS (
        SELECT 1 FROM public.admin_navigation_items
        WHERE key='hybrid_sms_receipts'
          AND label='SMS receipts'
          AND icon_key='sms'
          AND route_path='/admin/sms-receipts'
          AND required_permission='notifications.read'
          AND display_order=46
          AND enabled
          AND metadata='{"channel":"assisted_sms","country":"RW"}'::jsonb
          AND updated_reason='Account-independent member receipt queue'
      )
      AND EXISTS (
        SELECT 1 FROM public.admin_queue_specs
        WHERE rpc_name='admin_list_hybrid_sms_receipts'
          AND title='SMS receipts'
          AND subtitle='Feature-phone acknowledgements prepared from immutable posted balances.'
          AND required_permission='notifications.read'
          AND display_order=28
          AND enabled
          AND metadata='{"detail_rpc":"admin_get_hybrid_sms_receipt","channel":"assisted_sms"}'::jsonb
          AND updated_reason='Account-independent member receipt queue'
      )
      AND EXISTS (
        SELECT 1 FROM public.admin_queue_filter_options
        WHERE rpc_name='admin_list_hybrid_sms_receipts'
          AND filter_kind='status'
          AND value='failed_no_send'
          AND label='Failed—no send'
          AND display_order=55
          AND enabled
      )
      AND to_regprocedure('public.ingest_attested_raw_payment_sms(uuid,uuid,uuid,text,text,text,uuid,text,text)') IS NOT NULL
      AND to_regprocedure('public.finalize_attested_payment_sms(uuid)') IS NOT NULL;
    SQL
    raise 'Backfill or default access invariant failed' unless invariants == 't'
    report[:migration_rehearsal][:identity_backfill_and_default_access] = 'pass'
    check_file = File.join(root,'scripts/tests/production_upgrade_readbacks.sql')
    raise 'Member/Admin upgrade readbacks failed' unless sql.call(File.read(check_file)).lines.last&.strip == 'PRODUCTION_COPY_READBACKS_PASS'
    report[:migration_rehearsal][:member_and_selected_admin_readbacks] = 'pass_rolled_back_no_provider_sends'
    attested_check = File.join(root, 'scripts/tests/attested_sms_finality_uat.sql')
    attested_result = sql.call(File.read(attested_check))
    raise 'Attested SMS finality UAT failed' unless attested_result.lines.last&.strip&.start_with?('ATTESTED_SMS_FINALITY_UAT_PASS:')
    report[:migration_rehearsal][:attested_sms_finality_uat] =
      'pass_rolled_back_synthetic_provider_sms_no_external_send'
    roster_check = File.join(root, 'scripts/tests/hybrid_roster_import_uat.sql')
    roster_result = sql.call(File.read(roster_check))
    raise 'Hybrid roster import UAT failed' unless roster_result.lines.last&.strip&.start_with?('HYBRID_ROSTER_IMPORT_UAT_PASS:')
    report[:migration_rehearsal][:hybrid_roster_import_uat] =
      'pass_rolled_back_synthetic_admin_and_members_no_external_send'
    sms_outbox_check = File.join(root, 'scripts/tests/hybrid_sms_notification_outbox_uat.sql')
    sms_outbox_result = sql.call(File.read(sms_outbox_check))
    raise 'Hybrid SMS notification outbox UAT failed' unless sms_outbox_result.lines.last&.strip&.start_with?('HYBRID_SMS_NOTIFICATION_OUTBOX_UAT_PASS:')
    report[:migration_rehearsal][:hybrid_sms_notification_outbox_uat] =
      'pass_rolled_back_synthetic_consent_and_operator_flow_no_external_send'
    claim_check = File.join(root, 'scripts/tests/hybrid_verified_account_claim_uat.sql')
    claim_result = sql.call(File.read(claim_check))
    raise 'Hybrid verified account claim UAT failed' unless claim_result.lines.last&.strip&.start_with?('HYBRID_VERIFIED_ACCOUNT_CLAIM_UAT_PASS:')
    report[:migration_rehearsal][:hybrid_verified_account_claim_uat] =
      'pass_rolled_back_exact_verified_phone_claim_no_external_send'
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
    report[:migration_rehearsal][:migration_count] = 120
    report[:migration_rehearsal][:status] = 'pass'
  end
end
