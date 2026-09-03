require 'minitest/autorun'
require_relative '../audits/collect_production_cutover'
require_relative '../audits/collect_release_build'

class ProductionCutoverTest < Minitest::Test
  def test_exact_manifest_and_atomic_history
    entries = CollectProductionCutover.manifest
    assert_equal 14, entries.length
    remote = (1..97).map { |i| {'version'=>format('%014d',i)} }
    sql = CollectProductionCutover.transaction(entries,remote)
    assert_equal 14, sql.scan('INSERT INTO supabase_migrations.schema_migrations').length
    assert sql.start_with?('BEGIN;')
    assert sql.end_with?('COMMIT;')
    assert_includes sql, 'pg_try_advisory_xact_lock'
    entries.each { |e| assert_includes sql, e.fetch('content') }
  end

  def test_refuses_ambiguous_transaction_and_history
    assert_raises(RuntimeError) { CollectProductionCutover.body('select 1;') }
    assert_raises(RuntimeError) { CollectProductionCutover.body("begin;\nselect 1;\ncommit;\ncommit;") }
    assert_raises(RuntimeError) { CollectProductionCutover.transaction([],[]) }
    assert_raises(RuntimeError) { CollectProductionCutover.transaction([],Array.new(97) { {'version'=>'1'} }) }
    assert_equal 'select 1;', CollectProductionCutover.body("begin;\nselect 1;\ncommit;")
  end

  def test_build_rejects_privileged_keys_and_wrong_project
    key = lambda { |role,ref| 'header.'+Base64.urlsafe_encode64(JSON.generate(role:role,ref:ref))+'.signature' }
    ref = CollectReleaseBuild::REF
    good = {'project_url'=>"https://#{ref}.supabase.co",'anon_key'=>key.call('anon',ref)}
    assert_equal '1', CollectReleaseBuild.environment(good).fetch('COLLECT_SKIP_DOTENV')
    assert_raises(RuntimeError) { CollectReleaseBuild.environment(good.merge('anon_key'=>key.call('service_role',ref))) }
    assert_raises(RuntimeError) { CollectReleaseBuild.environment(good.merge('anon_key'=>key.call('anon','other'))) }
    assert_raises(RuntimeError) { CollectReleaseBuild.environment(good.merge('project_url'=>'https://other.supabase.co')) }
  end

  def test_protected_column_metadata_is_json_not_postgres_array_text
    captured = nil
    fake = lambda do |_token,sql,**_options|
      captured = sql
      [{'table_name'=>'profiles','columns'=>['id','public_id']}]
    end
    CollectProductionCutover.stub(:query,fake) do
      assert_equal({'profiles'=>['id','public_id']},CollectProductionCutover.projections('synthetic'))
    end
    assert_includes captured,'jsonb_agg(column_name'
    assert_raises(RuntimeError) { CollectProductionCutover.fingerprint('synthetic',{'profiles'=>'{id,public_id}'}) }
  end

  def test_privilege_visibility_audit_stays_sql_read_only
    captured = nil
    CollectProductionCutover.stub(:request,lambda { |_token,_path,payload| captured=payload; [] }) do
      assert_equal [],CollectProductionCutover.catalog_query('synthetic','SELECT current_user;')
    end
    assert captured[:query].start_with?('BEGIN READ ONLY;')
    assert captured[:query].end_with?('ROLLBACK;')
    assert_equal false,captured[:read_only]
  end
end
