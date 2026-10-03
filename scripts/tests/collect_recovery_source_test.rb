require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require_relative '../audits/collect_recovery_source'

class CollectRecoverySourceTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('collect-recovery-source-test-')
    FileUtils.mkdir_p(File.join(@root,'supabase/migrations'))
    @file = File.join(@root,'supabase/migrations/202605230001_first.sql')
    File.write(@file, '-- synthetic fixture only')
    File.write(File.join(@root,'supabase/migrations/20261002050000_second.sql'), '-- synthetic fixture only')
    @catalog = { 'format'=>'collect-recovery-catalog-v1', 'server'=>{'major'=>17,'version'=>'17.6'},
      'database'=>CollectRecoverySource::DATABASE_KEYS.to_h { |k| [k,nil] }.merge('name'=>'postgres'),
      'migrations'=>%w[202605230001 20261002050000] }.merge(CollectRecoverySource::ROW_LENGTHS.to_h { |key,_| [key,[]] })
    @catalog['schemas'] = [['public','postgres',nil],['receipt_worker_private','postgres',[]]]
    @document = CollectRecoverySource.build(@catalog, root: @root)
    @path = File.join(@root,'source.json')
    @raw = JSON.pretty_generate(@document) + "\n"
    File.write(@path, @raw)
    @sha256 = Digest::SHA256.hexdigest(@raw)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_exact_source_contract_loads_and_binds_both_version_lengths
    assert_equal @document, CollectRecoverySource.load(@path,@sha256,root:@root)
    assert_equal 2, CollectRecoverySource.association(@document,@sha256)['migrations']
    assert_equal %w[202605230001 20261002050000], @document['migration_files'].map { |row| row['version'] }
  end

  def test_same_count_different_migration_fails
    @catalog['migrations'][1] = '20261002060000'
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.build(@catalog,root:@root) }
  end

  def test_edited_added_deleted_and_duplicate_source_versions_fail
    File.write(@file, '-- different source')
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.load(@path,@sha256,root:@root) }
    File.write(@file, '-- synthetic fixture only')
    extra = File.join(@root,'supabase/migrations/20261002060000_third.sql')
    File.write(extra, '-- new source')
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.load(@path,@sha256,root:@root) }
    File.unlink(extra)
    File.unlink(@file)
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.load(@path,@sha256,root:@root) }
    File.write(@file, '-- synthetic fixture only')
    File.write(File.join(@root,'supabase/migrations/202605230001_duplicate.sql'), '-- duplicate source')
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.sources(root:@root) }
  end

  def test_explicit_hash_and_regular_absolute_file_required
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.load(@path,'0'*64,root:@root) }
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.load(@path,'invalid',root:@root) }
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.read('relative.json') }
    link = File.join(@root,'link.json')
    File.symlink(@path,link)
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.read(link) }
  end

  def test_json_duplicate_shape_size_and_secret_errors_are_closed
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.parse('{"format":1,"format":2}') }
    error = assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.parse('{SYNTHETIC_SECRET') }
    refute_includes error.message, 'SYNTHETIC_SECRET'
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.parse('x'*(CollectRecoverySource::LIMIT+1)) }
    @catalog['unexpected'] = 'private'
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.catalog!(@catalog) }
    @catalog.delete('unexpected')
    @catalog['roles'] = [['wrong-arity']]
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.catalog!(@catalog) }
  end

  def test_catalog_digest_ignores_object_key_order_but_preserves_array_values_and_order
    assert_equal CollectRecoverySource.digest(@catalog), CollectRecoverySource.digest(@catalog.to_a.reverse.to_h)
    assert CollectRecoverySource.verify_catalog!(@document,@catalog)
    @catalog['schemas'][1][2] = ['reader=U/postgres']
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.verify_catalog!(@document,@catalog) }
    @catalog['schemas'][1][2] = []
    @catalog['schemas'].reverse!
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.verify_catalog!(@document,@catalog) }
  end

  def test_closed_catalog_server_database_and_version_guards
    @catalog['server']['major'] = 16
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.catalog!(@catalog) }
    @catalog['server']['major'] = 17
    @catalog['database']['name'] = 'other'
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.catalog!(@catalog) }
    @catalog['database']['name'] = 'postgres'
    @catalog['migrations'] = %w[202605230001 202605230001]
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.catalog!(@catalog) }
  end

  def test_backup_pairs_duplicates_and_unknown_options_are_refused
    base = ['--approved-ip-129.222.149.205','new.json']
    assert_nil CollectRecoverySource.selected_contract(CollectRecoverySource.options(base,:backup))
    assert_equal true, CollectRecoverySource.options(base+['--roles-only'],:backup)['--roles-only']
    [base+['--source-contract',@path],base+['--roles-only','--roles-only'],base+['--unknown'],
      ['--approved-ip-192.0.2.1','new.json'],base+['--source-contract']].each do |args|
      assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.options(args,:backup) }
    end
  end

  def test_restore_requires_all_explicit_inputs_and_rejects_legacy_rehearsal_with_contract
    pair = ['--source-contract',@path,'--source-contract-sha256',@sha256]
    inputs = ['--database-report','/db.json','--roles-report','/roles.json','--extension-metadata','/extension.json']
    assert_equal '/db.json', CollectRecoverySource.options(['new.json']+pair+inputs,:restore)['--database-report']
    [ ['new.json']+pair,['new.json']+inputs[0,2],['new.json']+pair+inputs+['--rehearse-migrations'] ].each do |args|
      assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.options(args,:restore) }
    end
  end

  def test_capture_reports_must_bind_exact_contract_catalog_and_scope
    report = {'project'=>CollectRecoverySource::PROJECT,'capture_scope'=>'database',
      'source_contract'=>CollectRecoverySource.association(@document,@sha256),
      'source_check'=>CollectRecoverySource.check(@catalog),'source_catalog_after_matches'=>true}
    assert CollectRecoverySource.verify_report!(report,@document,@sha256,'database')
    report['source_check']['migrations'] += 1
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.verify_report!(report,@document,@sha256,'database') }
    report['source_check'] = CollectRecoverySource.check(@catalog)
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.verify_report!(report,@document,@sha256,'global_roles_without_passwords') }
    report['source_catalog_after_matches'] = false
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.verify_report!(report,@document,@sha256,'database') }
  end

  def test_extension_supplement_matches_exact_function_owners_and_versions
    definition = 'CREATE OR REPLACE FUNCTION graphql_public.graphql() RETURNS void LANGUAGE sql AS $$SELECT$$'
    hash = Digest::SHA256.hexdigest(definition)
    @catalog['extensions'] = [['pg_graphql','1.5.11','graphql','supabase_admin']]
    @catalog['functions'] = [['graphql_public','graphql','', 'f','supabase_admin',false,'s','s',false,false,nil,'0'*64,hash]]
    @document = CollectRecoverySource.build(@catalog,root:@root)
    metadata = {'project'=>CollectRecoverySource::PROJECT,'definition_sha256'=>hash,'wrapper'=>{
      'definition'=>definition,'owner'=>'supabase_admin','extension'=>'pg_graphql',
      'installed_extensions'=>[{'name'=>'pg_graphql','version'=>'1.5.11'}],
      'extension_owners'=>[{'name'=>'pg_graphql','owner'=>'supabase_admin'}]}}
    assert CollectRecoverySource.verify_extension_metadata!(@document,metadata)
    metadata['wrapper']['definition'] += ';'
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.verify_extension_metadata!(@document,metadata) }
    metadata['wrapper']['definition'] = definition
    metadata['wrapper']['installed_extensions'][0]['version'] = 'different'
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.verify_extension_metadata!(@document,metadata) }
  end

  def test_actual_backup_and_restore_cli_refuse_invalid_contract_before_credentials_or_vault
    pair = ['--source-contract',@path,'--source-contract-sha256','0'*64]
    commands = [
      ['scripts/audits/collect_encrypted_database_backup.rb','--approved-ip-129.222.149.205','new.json',*pair],
      ['scripts/tests/production_archive_restore.rb','new.json',*pair,'--database-report','/missing.json',
        '--roles-report','/missing.json','--extension-metadata','/missing.json'] ]
    commands.each do |args|
      out,err,status = Open3.capture3('ruby',*args,chdir:CollectRecoverySource::ROOT,stdin_data:'SYNTHETIC_SECRET')
      refute status.success?
      assert_includes err, 'source preflight refused'
      refute_includes out+err, 'Awaiting'
      refute_includes out+err, 'SYNTHETIC_SECRET'
    end
  end

  def test_dynamic_schema_extraction_uses_declarations_and_actual_toc_namespaces
    toc = "10; 2615 16384 SCHEMA - receipt_worker_private postgres\n" +
      "11; 2615 16385 SCHEMA - new_future_schema postgres\n" +
      "12; 1255 16386 FUNCTION public fake_schema() postgres\n" +
      "13; 2615 16385 SCHEMA - new_future_schema postgres\n" +
      "14; 0 0 COMMENT - SCHEMA fake_schema postgres\n"
    assert_equal %w[new_future_schema public receipt_worker_private], CollectRecoverySource.archive_schemas(toc)
  end
end
