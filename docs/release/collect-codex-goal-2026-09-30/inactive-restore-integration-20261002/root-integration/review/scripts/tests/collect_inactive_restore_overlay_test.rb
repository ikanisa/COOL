--- canonical/scripts/tests/collect_inactive_restore_overlay_test.rb
+++ proposed/scripts/tests/collect_inactive_restore_overlay_test.rb
@@ -0,0 +1,105 @@
+require 'minitest/autorun'
+require_relative '../audits/collect_inactive_restore_overlay'
+class CollectInactiveRestoreOverlayTest < Minitest::Test
+  O=CollectInactiveRestoreOverlay
+  def document
+    {'catalog'=>{'migrations'=>O::REQUIRED},'catalog_sha256'=>'d'*64,'migration_files'=>[{'path'=>'approved.sql','sha256'=>'e'*64}]}
+  end
+  def options
+    {'--inactive-overlay'=>true,'--worker-snapshot'=>true,'--inactive-reason'=>'isolated database restore stop'}
+  end
+  def comparisons
+    {'data_comparison'=>{'all_fingerprints_match'=>true},'schema_comparison'=>{'match'=>true},'roles_comparison'=>{'match'=>true},
+     'source_catalog_comparison'=>{'match'=>true,'compared_before_any_business_policy_changes'=>true,'business_policy_overlay_applied'=>false},
+     'worker_snapshot_comparison'=>{'source_state_compared_before_overlay'=>true,'durable_inactive_overlay'=>false}}
+  end
+  def parser_args
+    ['--worker-snapshot','--source-contract','/approved/contract.json','--source-contract-sha256','a'*64,
+     '--database-report','/approved/db.json','--roles-report','/approved/roles.json','--extension-metadata','/approved/ext.json','output.json']
+  end
+  def test_default_is_inactive_without_contract_or_reason
+    assert_equal false,O.preflight!({},nil)
+    assert_equal false,O.preflight!({'--worker-snapshot'=>true},document)
+  end
+  def test_explicit_scope_requires_every_current_guard_family
+    assert O.preflight!(options,document)
+    O::REQUIRED.each do |version|
+      d=Marshal.load(Marshal.dump(document));d['catalog']['migrations'].delete(version)
+      assert_raises(O::Error){O.preflight!(options,d)}
+    end
+  end
+  def test_no_source_or_snapshot_and_no_historical_upgrade
+    assert_raises(O::Error){O.preflight!(options,nil)}
+    assert_raises(O::Error){O.preflight!(options.merge('--worker-snapshot'=>false),document)}
+    assert_raises(O::Error){O.preflight!(options.merge('--rehearse-migrations'=>true),document)}
+  end
+  def test_reason_is_explicit_bounded_and_no_control_characters
+    [nil,'short',' x valid reason','valid reason ',"reason\nline",'x'*501].each{|v|assert_raises(O::Error){O.preflight!(options.merge('--inactive-reason'=>v),document)}}
+  end
+  def test_parser_keeps_legacy_and_exact_worker_path
+    assert_equal 'output.json',CollectRecoverySource.options(['output.json'],:restore)['output']
+    assert_equal true,CollectRecoverySource.options(parser_args,:restore)['--worker-snapshot']
+    args=parser_args.dup;args.insert(-2,'--inactive-overlay','--inactive-reason','isolation outage stop')
+    value=CollectRecoverySource.options(args,:restore)
+    assert_equal true,value['--inactive-overlay'];assert_equal 'isolation outage stop',value['--inactive-reason']
+  end
+  def test_parser_refuses_unpaired_overlay_reason_and_duplicate_flags
+    [['--inactive-overlay','out.json'],['--inactive-reason','valid reason','out.json'],parser_args+['--inactive-overlay'],
+      parser_args+['--inactive-overlay','--inactive-overlay','--inactive-reason','valid reason']].each{|args|assert_raises(CollectRecoverySource::Error){CollectRecoverySource.options(args,:restore)}}
+    assert_raises(CollectRecoverySource::Error){CollectRecoverySource.options(['--approved-ip-129.222.149.205','--inactive-overlay','x','y'],:backup)}
+  end
+  def test_comparison_association_requires_every_original_completed_scope
+    assert_match(/\A[0-9a-f]{64}\z/,O.comparison_association!(comparisons))
+    O::COMPARISONS.each do |key|
+      c=Marshal.load(Marshal.dump(comparisons));c.delete(key)
+      assert_raises(O::Error){O.comparison_association!(c)}
+    end
+  end
+  def test_catalog_and_worker_source_claims_cannot_be_relabelled
+    c=Marshal.load(Marshal.dump(comparisons));c['source_catalog_comparison']['business_policy_overlay_applied']=true
+    assert_raises(O::Error){O.comparison_association!(c)}
+    c=Marshal.load(Marshal.dump(comparisons));c['worker_snapshot_comparison']['durable_inactive_overlay']=true
+    assert_raises(O::Error){O.comparison_association!(c)}
+    c=Marshal.load(Marshal.dump(comparisons));c['data_comparison']['all_fingerprints_match']=false
+    assert_raises(O::Error){O.comparison_association!(c)}
+  end
+  def test_invalid_invocation_refuses_before_any_subprocess
+    [['docker','exec','-i','hosted','psql'],['psql','-U','supabase_admin']].each{|av|assert_raises(O::Error){O.execute(av,'unexecuted',error_path:'/nonexistent/no-log')}}
+  end
+  def test_known_uuid_and_input_digest_are_strict
+    defaults={target:'collect-recovery-owned-fixture',document:document,contract_sha256:'a'*64,archive_sha256:'b'*64,comparison_sha256:'c'*64,reason:'approved restore stop',tools_sha256:'d'*64}
+    c=O.input!(**defaults);assert_match(O::UUID,c['restore_id']);assert_equal O::FORMAT,c['format']
+    assert_raises(O::Error){O.input!(**defaults.merge(target:'hosted-production'))}
+    assert_raises(O::Error){O.input!(**defaults.merge(restore_id:'unknown'))}
+    assert_raises(O::Error){O.input!(**defaults.merge(archive_sha256:'no-digest'))}
+  end
+  def test_apply_without_optin_refuses_before_target_or_source_access
+    assert_raises(O::Error){O.apply(target:'invalid',options:{},document:nil,report:{},directory:'/not-created',root:'/not-created')}
+  end
+end
+
+class CollectInactiveRestoreOverlayBoundaryTest < Minitest::Test
+  O=CollectInactiveRestoreOverlay
+  def response
+    {'format'=>'collect-inactive-restore-result-v1','restore_id'=>'11111111-2222-4333-8444-555555555555',
+     'recorded_at'=>'2026-10-02T03:00:00.123456+00:00','delta_sha256'=>'a'*64,'item_count'=>14,
+     'resume_required'=>true,'financial_action'=>false,'send_action'=>false,'session_owner'=>'postgres','effective_owner'=>'postgres'}
+  end
+  def test_owner_result_has_one_closed_exact_receipt_shape
+    assert_equal response,O.result!(JSON.generate(response))
+    [response.merge('unknown'=>true),response.merge('restore_id'=>nil),response.merge('recorded_at'=>'infinity'),
+     response.merge('item_count'=>2014),response.merge('item_count'=>'14'),response.merge('send_action'=>true),
+     response.merge('effective_owner'=>'supabase_admin'),response.merge('delta_sha256'=>nil),[],nil].each do|value|
+      assert_raises(O::Error){O.result!(JSON.generate(value))}
+    end
+  end
+  def test_tool_source_capture_is_repeatable_and_uses_exact_loaded_sources
+    root=File.expand_path('../..',__dir__)
+    first=O.tooling(root);assert_equal first,O.tooling(root)
+    assert_equal %w[docker helper restore_caller ruby source_helper source_query],first.fetch('files').keys.sort
+    first['files'].each_value do|value|
+      assert File.file?(value['path']);assert_equal File.size(value['path']),value['bytes']
+      assert_equal Digest::SHA256.file(value['path']).hexdigest,value['sha256']
+    end
+  end
+end
