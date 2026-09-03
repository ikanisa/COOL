require 'minitest/autorun'
require 'open3'
require 'json'
require 'digest'
require_relative '../audits/collect_index_inventory'

# Exact local-only targets. No URL, environment credential, or production mode.
class CombinedReleaseContractTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  TARGETS = {
    combined: ['supabase_db_collect', 'collect_release_combined_uat_20260902'],
    replay: ['supabase_db_collect_release_replay_20260902', 'postgres']
  }.freeze
  READINESS = File.read(ROOT + '/scripts/supabase_production_readiness.sh')
  QUERIES = {
    privileges: /    with allowed_table_grants.*?    order by issue;/m,
    columns: /    with roles\(grantee\).*?    order by 1;/m,
    rails: /    with required_authenticated\(routine_name\).*?    order by issue;/m
  }.transform_values do |pattern|
    READINESS[pattern] or raise 'Readiness SQL marker changed'
  end.freeze

  def sql(target, query)
    container, db = TARGETS.fetch(target)
    out, err, status = Open3.capture3('docker', 'exec', '-i', container,
      'psql', '-XqAt', '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1',
      stdin_data: "set statement_timeout='30s';\n" + query)
    assert status.success?, err
    out.strip
  end

  def test_readiness_queries_accept_both_candidate_constructions
    TARGETS.each_key do |target|
      QUERIES.each do |name, query|
        assert_empty sql(target, "begin read only;\n#{query}\nrollback;"), "#{target}: #{name}"
      end
    end
  end

  def test_revived_name_rpc_is_detected_and_rolled_back
    result = sql(:combined, <<~SQL)
      begin;
      grant execute on function public.get_current_profile() to authenticated;
      #{QUERIES.fetch(:privileges)}
      rollback;
    SQL
    assert_includes result, 'forbidden function grant: authenticated EXECUTE on get_current_profile'
    assert_equal 'f', sql(:combined, "select has_function_privilege('authenticated','public.get_current_profile()','execute');")
  end

  def test_revived_financial_table_grant_is_detected_and_rolled_back
    result = sql(:combined, <<~SQL)
      begin;
      grant select on public.payment_intents to authenticated;
      #{QUERIES.fetch(:rails)}
      rollback;
    SQL
    assert_includes result, 'legacy financial table grant: authenticated SELECT on payment_intents'
    assert_equal 'f', sql(:combined, "select has_table_privilege('authenticated','public.payment_intents','select');")
  end

  def test_public_trigger_execute_is_detected_and_rolled_back
    result = sql(:combined, <<~SQL)
      begin;
      grant execute on function public.enforce_official_payee_route_immutable() to public;
      #{QUERIES.fetch(:privileges)}
      rollback;
    SQL
    assert_includes result, 'unexpected PUBLIC function grant: enforce_official_payee_route_immutable EXECUTE'
    assert_equal 'f', sql(:combined, "select has_function_privilege('anon','public.enforce_official_payee_route_immutable()','execute');")
  end

  def test_column_only_financial_and_name_grants_are_detected
    result = sql(:combined, <<~SQL)
      begin;
      grant select(amount_rwf) on public.payments to authenticated;
      grant select(display_name) on public.profiles to authenticated;
      grant select(phone_e164) on collect_admin_access.whatsapp_approvals to authenticated;
      #{QUERIES.fetch(:rails)}
      rollback;
    SQL
    assert_includes result, 'legacy financial table grant: authenticated SELECT on payments.amount_rwf'
    assert_includes result, 'member name column grant: authenticated SELECT on profiles.display_name'
    assert_includes result, 'private identity data grant: authenticated SELECT on collect_admin_access.whatsapp_approvals.phone_e164'
    assert_equal 'f', sql(:combined, "select has_column_privilege('authenticated','public.profiles','display_name','select');")
  end

  def test_missing_new_member_rpc_is_detected_and_rolled_back
    result = sql(:combined, <<~SQL)
      begin;
      revoke execute on function public.get_current_member_profile() from authenticated;
      #{QUERIES.fetch(:privileges)}
      rollback;
    SQL
    assert_includes result, 'missing function grant: authenticated EXECUTE on get_current_member_profile'
    assert_equal 't', sql(:combined, "select has_function_privilege('authenticated','public.get_current_member_profile()','execute');")
  end

  def test_official_route_is_still_immutable_after_trigger_grant_revocation
    assert_equal 'OFFICIAL_ROUTE_IMMUTABLE_PASS', sql(:replay, <<~SQL)
      begin;
      do $$ declare receiver uuid; blocked boolean := false;
      begin
        select r.id into receiver from public.collection_receivers r
          join public.collections c on c.id=r.collection_id
          where c.is_platform_sponsored limit 1;
        if receiver is null then raise exception 'Official reference route fixture missing'; end if;
        begin
          update public.collection_receivers set momo_number='99887' where id=receiver;
        exception when sqlstate 'P0001' then
          if sqlerrm <> 'Official payee MoMo number or code and provider are immutable; deactivate the route instead' then raise; end if;
          blocked := true;
        end;
        if not blocked then raise exception 'Official route mutation was accepted'; end if;
      end $$;
      select 'OFFICIAL_ROUTE_IMMUTABLE_PASS';
      rollback;
    SQL
  end

  def test_private_names_and_approval_tables_are_not_client_readable
    TARGETS.each_key do |target|
      assert_equal '0', sql(target, <<~SQL)
        select count(*) from (values('anon'),('authenticated')) r(role)
        cross join (values('collect_hybrid.member_momo_identities'),
          ('collect_hybrid.member_records'),('collect_admin_access.whatsapp_approvals')) t(tab)
        where has_table_privilege(r.role,t.tab,'select');
      SQL
    end
  end

  def test_replay_report_covers_exact_current_migration_bytes
    report = JSON.parse(File.read(ROOT + '/docs/release/COMBINED_CLEAN_REPLAY_2026-09-02.json'))
    assert_equal 'pass', report.fetch('status')
    actual = report.fetch('migrations').map { |r| [r.fetch('migration'), r.fetch('sha256'), r.fetch('status')] }
    expected = Dir[ROOT + '/supabase/migrations/*.sql'].sort.map do |path|
      [File.basename(path), Digest::SHA256.file(path).hexdigest, 'pass']
    end
    assert_equal expected, actual
    assert_equal expected.length.to_s, sql(:replay, 'select count(*) from supabase_migrations.schema_migrations;')
  end

  def test_index_inventory_resolves_private_schemas
    indexes = CollectIndexInventory.expected(Dir[ROOT + '/supabase/migrations/*.sql'].sort.map { |p| File.read(p) })
    assert_includes indexes, ['collect_hybrid', 'hybrid_identity_match_idx']
    assert_includes indexes, ['collect_admin_access', 'whatsapp_approvals_active_phone_key']
    TARGETS.each_key { |target| assert_empty sql(target, CollectIndexInventory.query(indexes)) }
    assert_equal "public.synthetic_missing_index", sql(:combined, CollectIndexInventory.query([['public', 'synthetic_missing_index']]))
  end

  def test_combined_upgrade_and_clean_replay_have_identical_application_functions
    query = <<~SQL
      select jsonb_agg(jsonb_build_array(n.nspname,p.proname,
        pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),
        p.proacl::text,pg_get_userbyid(p.proowner))
        order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid))
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname in ('public','private','collect_member_actions','collect_hybrid','collect_admin_access')
        and p.prokind='f';
    SQL
    fingerprints = TARGETS.keys.map { |target| Digest::SHA256.hexdigest(sql(target, query)) }
    assert_equal fingerprints.first, fingerprints.last, 'Application function bodies, ACLs or owners differ across migration order'
  end
end
