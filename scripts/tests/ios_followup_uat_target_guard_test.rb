require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'tmpdir'

class IosFollowupTargetGuardTest < Minitest::Test
  def test_missing_or_mismatched_confirmation_exits_before_native_commands
    [nil, '', 'wrong-target'].each do |confirmation|
      Dir.mktmpdir('collect-followup-guard-') do |dir|
        stdout, stderr, status = Open3.capture3(
          {'IOS_UAT_SIMULATOR_ID' => 'approved-target',
           'IOS_UAT_CONFIRM_DISPOSABLE_SIMULATOR' => confirmation,
           'IOS_UAT_EVIDENCE_DIR' => File.join(dir, 'evidence')},
          RbConfig.ruby, File.expand_path('../ios_simulator_followup_uat.rb', __dir__),
          unsetenv_others: true
        )
        refute status.success?
        assert_includes stderr, 'Exact disposable-simulator confirmation is required.'
        assert_empty stdout
        refute File.exist?(File.join(dir, 'evidence'))
      end
    end
  end
end
