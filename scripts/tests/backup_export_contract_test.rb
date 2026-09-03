require 'minitest/autorun'
require 'open3'

class BackupExportContractTest < Minitest::Test
  SCRIPT = File.expand_path('../supabase_logical_backup.sh', __dir__)

  def invoke(*args)
    Open3.capture3({'DATABASE_URL'=>nil,'SUPABASE_ACCESS_TOKEN'=>nil},'bash',SCRIPT,*args)
  end

  def test_help_is_credential_free_and_discloses_recovery_exclusions
    out,err,status=invoke('--help')
    assert status.success?,err
    %w[PARTIAL Auth privileges Storage secrets].each { |term| assert_includes out,term }
    assert_includes out,'not a full recovery backup'
  end

  def test_default_invocation_refuses_before_loading_credentials_or_exporting
    out,err,status=invoke
    assert_equal 2,status.exitstatus
    assert_empty out
    assert_includes err,'partial public export'
    refute_includes err,'DATABASE_URL'
  end

  def test_unknown_arguments_do_not_authorize_export
    out,err,status=invoke('--full-backup')
    assert_equal 2,status.exitstatus
    assert_empty out
    assert_includes err,'REFUSED'
  end
end
