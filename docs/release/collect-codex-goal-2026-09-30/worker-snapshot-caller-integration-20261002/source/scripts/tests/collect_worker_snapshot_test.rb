require 'minitest/autorun'
require 'tmpdir'
require_relative '../audits/collect_receipt_worker_snapshot'

class WorkerSnapshotTest < Minitest::Test
  S = CollectReceiptWorkerSnapshot
  def logical(rows = [])
    { 'contract_version'=>1, 'rows'=>rows, 'checked'=>rows.length,
      'last_family'=>rows.last && rows.last['family'], 'last_key'=>rows.last && rows.last['key'],
      'financial_action'=>false, 'send_action'=>false, 'source_scan_complete'=>false }
  end
  def row(key = '1')
    { 'family'=>'worker_configuration', 'key'=>key, 'logical_sha256'=>'a'*64, 'binding'=>nil, 'tier'=>'hot' }
  end
  def objects(rows = [])
    { 'contract_version'=>1, 'rows'=>rows, 'checked'=>rows.length, 'last_sha256'=>rows.last && rows.last['sha256'],
      'financial_action'=>false, 'send_action'=>false }
  end
  def refuse
    assert_raises(S::Error) { yield }
  end
  def test_terminal_and_advancing_pages
    assert_nil S.validate_page!(logical, 'logical', nil)
    assert_equal ['worker_configuration','1'], S.validate_page!(logical([row]), 'logical', nil)
    assert_equal 'a'*64, S.validate_page!(objects([{ 'sha256'=>'a'*64, 'bytes'=>0 }]), 'objects', nil)
  end
  def test_count_terminal_cursor_and_duplicate_refusals
    p = logical([row]); p['checked']=0; refuse { S.validate_page!(p, 'logical', nil) }
    p=logical; p['last_key']='1'; refuse { S.validate_page!(p, 'logical', nil) }
    refuse { S.validate_page!(logical([row,row]), 'logical', nil) }
    refuse { S.validate_page!(logical([row]), 'logical', ['worker_configuration','2']) }
  end
  def test_closed_shapes_authority_and_original_ids
    p=logical; p['extra']=false; refuse { S.validate_page!(p, 'logical', nil) }
    p=logical; p['source_scan_complete']=true; refuse { S.validate_page!(p, 'logical', nil) }
    p=objects; p['send_action']=true; refuse { S.validate_page!(p, 'objects', nil) }
    refuse { S.validate_page!(logical([row("1';SELECT 1")]), 'logical', nil) }
    p=row; p['tier']='cold'; refuse { S.validate_page!(logical([p]), 'logical', nil) }
  end
  def test_duplicate_json_and_noninteger_refusal
    refuse { S.parse('{"rows":[],"rows":[]}') }
    p=objects([{ 'sha256'=>'a'*64, 'bytes'=>1.0 }]); refuse { S.validate_page!(p, 'objects', nil) }
    p=objects([{ 'sha256'=>'a'*64, 'bytes'=>-1 }]); refuse { S.validate_page!(p, 'objects', nil) }
  end
  def test_private_file_missing_hash_symlink_permissions
    Dir.mktmpdir do |dir|
      raw=JSON.generate(logical)+"\n"; sha=Digest::SHA256.hexdigest(raw); path=File.join(dir,'logical-00000.json')
      S.private_write(path,raw)
      assert_equal raw,S.safe_file(dir,'logical-00000.json',raw.bytesize,sha)
      refuse { S.safe_file(dir,'logical-00000.json',raw.bytesize,'b'*64) }
      refuse { S.safe_file(dir,'../logical-00000.json',raw.bytesize,sha) }
      File.chmod(0644,path);refuse { S.safe_file(dir,'logical-00000.json',raw.bytesize,sha) };File.chmod(0600,path)
      File.symlink(path,File.join(dir,'logical-00001.json'));refuse { S.safe_file(dir,'logical-00001.json',raw.bytesize,sha) }
    end
  end
  def test_stream_completeness_exact_descriptors
    Dir.mktmpdir do |dir|
      raw=JSON.generate(logical)+"\n";sha=Digest::SHA256.hexdigest(raw);S.private_write(File.join(dir,'logical-00000.json'),raw)
      meta={'pages'=>[{'name'=>'logical-00000.json','bytes'=>raw.bytesize,'sha256'=>sha,'cursor_before'=>nil,'cursor_after'=>nil,'checked'=>0}],
        'rows'=>0,'sha256'=>Digest::SHA256.hexdigest('')}
      assert_equal [logical], S.read_stream(dir,meta,'logical',{'pages'=>0,'bytes'=>0})
      m=Marshal.load(Marshal.dump(meta));m['rows']=1;refuse { S.read_stream(dir,m,'logical',{'pages'=>0,'bytes'=>0}) }
      m=Marshal.load(Marshal.dump(meta));m['pages'] << m['pages'][0];refuse { S.read_stream(dir,m,'logical',{'pages'=>0,'bytes'=>0}) }
      refuse { S.read_stream(dir,meta,'logical',{'pages'=>S::MAX_PAGES,'bytes'=>0}) }
    end
  end
  def test_catalog_outer_wrapper_is_exactly_guarded_and_never_commits_holder
    query=File.binread(CollectRecoverySource::QUERY_PATH)
    document={'catalog_query_sha256'=>Digest::SHA256.hexdigest(query)}
    held=S.held_catalog_query(query,document)
    refute_includes held,'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;'
    refute_includes held,"COMMIT;\n"
    assert_includes held,'SET LOCAL statement_timeout'
    refuse { S.held_catalog_query(query+' ',document) }
    changed=query.sub('COMMIT;','COMMIT;COMMIT;')
    refuse { S.held_catalog_query(changed,{'catalog_query_sha256'=>Digest::SHA256.hexdigest(changed)}) }
  end
  def test_full_dump_profile_refuses_payload_filters_and_owner_privilege_reduction
    id='00000001-00000001-1'
    base=['docker','exec','pg_dump','--format=custom','--snapshot='+id]
    assert S.full_dump_argv!(base,id).nil?
    %w[--exclude-table-data=public.contributions --schema-only --data-only --section=data --no-owner --no-privileges -a -s -t].each do |flag|
      refuse { S.full_dump_argv!(base+[flag],id) }
    end
  end
  def test_opt_in_and_legacy_options
    source=['--source-contract','/private/source.json','--source-contract-sha256','a'*64]
    b=['--approved-ip-129.222.149.205','/private/report.json']
    assert CollectRecoverySource.options(b+source+['--worker-snapshot'],:backup)['--worker-snapshot']
    assert_nil CollectRecoverySource.options(b,:backup)['--worker-snapshot']
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.options(b+['--worker-snapshot'],:backup) }
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.options(b+source+['--worker-snapshot','--roles-only'],:backup) }
    inputs=['--database-report','/private/db.json','--roles-report','/private/roles.json','--extension-metadata','/private/extensions.json']
    assert CollectRecoverySource.options(['/private/report.json']+source+inputs+['--worker-snapshot'],:restore)['--worker-snapshot']
    assert_raises(CollectRecoverySource::Error) { CollectRecoverySource.options(['/private/report.json']+source+inputs+['--worker-snapshot','--worker-snapshot'],:restore) }
  end
end
