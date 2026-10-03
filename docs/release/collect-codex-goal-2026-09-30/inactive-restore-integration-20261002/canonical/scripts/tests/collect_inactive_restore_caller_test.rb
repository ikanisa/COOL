# Execute the exact new caller branch with a synthetic local adapter only.
# This is not an encrypted archive/Vault/container/full restore acceptance run.
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../audits/collect_inactive_restore_overlay'
class CollectInactiveRestoreCallerTest < Minitest::Test
  O=CollectInactiveRestoreOverlay
  PATH=File.expand_path('production_archive_restore.rb',__dir__)
  def source;File.binread(PATH);end
  def branch
    value=source[/    if inactive_overlay\n.*?    report\[:result\] = 'DATABASE_RESTORE_AND_DATA_COMPARISON_PASS_NOT_FULL_RECOVERY_ACCEPTANCE'\n/m]
    raise 'Actual caller branch absent' unless value
    value
  end
  def execute_branch(enabled,sql_result=true)
    inactive_overlay=enabled;report={};target='collect-recovery-synthetic-caller';options={};source_contract={};log_dir='/synthetic/no-write';sql=->(_){sql_result ? 't' : 'f'}
    root_scope=Module.new;root_scope.const_set(:ROOT,'/synthetic/root')
    # Preserve the exact caller branch and its actual failure result. ROOT is an inert fixture argument.
    code=branch.sub('root: ROOT','root: root_scope.const_get(:ROOT)')
    begin;eval(code,binding,PATH,source[0...source.index('    if inactive_overlay')].count("\n")+1)
    rescue StandardError=>error
      report[:result]='RESTORE_REHEARSAL_FAILED_NO_HOSTED_CHANGES';report[:error]=error.message
    end
    report
  end
  def test_default_path_never_calls_overlay_and_keeps_original_success_label
    O.stub(:apply,->(**_){raise 'unexpected mutation'})do
      assert_equal({'result'=>'DATABASE_RESTORE_AND_DATA_COMPARISON_PASS_NOT_FULL_RECOVERY_ACCEPTANCE'},execute_branch(false).transform_keys(&:to_s))
    end
  end
  def test_exact_adapter_parameters_and_original_report_are_passed_to_helper
    seen=nil;receipt={'synthetic_adapter'=>true}
    O.stub(:apply,->(**params){seen=params;receipt})do
      report=execute_branch(true);assert_equal receipt,report[:inactive_overlay]
      assert_equal 'DATABASE_RESTORE_AND_DATA_COMPARISON_PASS_NOT_FULL_RECOVERY_ACCEPTANCE',report[:result]
    end
    assert_equal %i[directory document options report root target],seen.keys.sort
    assert_equal '/synthetic/no-write',seen[:directory];assert_equal '/synthetic/root',seen[:root]
  end
  def test_helper_refusal_cannot_publish_caller_success
    O.stub(:apply,->(**_){raise O::Error,'Bounded synthetic refusal'})do
      report=execute_branch(true);assert_equal 'RESTORE_REHEARSAL_FAILED_NO_HOSTED_CHANGES',report[:result]
      refute report.key?(:inactive_overlay)
    end
  end
  def test_post_overlay_physical_guard_failure_cannot_publish_caller_success
    O.stub(:apply,{'synthetic_adapter'=>true})do
      report=execute_branch(true,false);assert_equal 'RESTORE_REHEARSAL_FAILED_NO_HOSTED_CHANGES',report[:result]
      assert_equal 'Restored physical worker guards changed',report[:error]
    end
  end
  def test_real_helper_refuses_missing_optin_before_source_or_subprocess
    report=execute_branch(true);assert_equal 'RESTORE_REHEARSAL_FAILED_NO_HOSTED_CHANGES',report[:result]
    assert_equal 'Inactive overlay explicit opt-in required',report[:error]
  end
  def test_source_order_preserves_all_original_checks_before_overlay_and_success
    before=source.index('report[:data_comparison]');roles=source.index('report[:roles_comparison]')
    catalog=source.index('report[:source_catalog_comparison]');worker=source.index('report[:worker_snapshot_comparison]')
    apply=source.index('report[:inactive_overlay]');success=source.index("report[:result] = 'DATABASE_RESTORE_AND_DATA_COMPARISON_PASS_NOT_FULL_RECOVERY_ACCEPTANCE'")
    assert before<roles&&roles<catalog&&catalog<worker&&worker<apply&&apply<success
    assert source.index('CollectInactiveRestoreOverlay.preflight!')<source.index("read_archive(database_path")
    assert_equal 1,source.scan('CollectInactiveRestoreOverlay.apply(').length
    assert_equal 1,source.scan('require_relative \'../audits/collect_inactive_restore_overlay\'').length
  end
end
