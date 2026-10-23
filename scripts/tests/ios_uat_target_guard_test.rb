require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'json'

class IosUatTargetGuardTest < Minitest::Test
  SCRIPT=File.expand_path('../ios_simulator_route_uat.sh',__dir__)
  DEVICE='12345678-1234-1234-1234-123456789012'

  def invoke(confirmation)
    Dir.mktmpdir('collect-ios-target-guard-') do |directory|
      calls=File.join(directory,'calls')
      xcrun=File.join(directory,'xcrun')
      # Test-generated executable fixture: no real simulator or app is touched.
      File.write(xcrun,<<~SH)
        #!/bin/bash
        printf '%s\\n' "$*" >> "$MOCK_CALLS"
        if [[ "$*" == 'simctl list devices --json' ]]; then
          printf '%s\\n' '{"devices":{"iOS":[{"udid":"#{DEVICE}","name":"fixture","state":"Booted","isAvailable":true}]}}'
          exit 0
        fi
        exit 99
      SH
      File.chmod(0700,xcrun)
      evidence=File.join(directory,'evidence')
      out,err,status=Open3.capture3({
        'XCRUN'=>xcrun,'FLUTTER'=>'/usr/bin/true','MOCK_CALLS'=>calls,
        'IOS_UAT_SIMULATOR_ID'=>DEVICE,
        'IOS_UAT_CONFIRM_DISPOSABLE_SIMULATOR'=>confirmation,
        'IOS_UAT_EVIDENCE_DIR'=>evidence
      },'bash',SCRIPT)
      yield out,err,status,File.read(calls),JSON.parse(File.read(File.join(evidence,'summary.json')))
    end
  end

  def test_missing_confirmation_cannot_terminate_or_uninstall
    invoke(nil) do |_out,err,status,calls,summary|
      refute status.success?
      assert_includes err,'Refusing app uninstall'
      refute_match(/terminate|uninstall/,calls)
      assert_equal 'not_started',summary.fetch('runner')
    end
  end

  def test_confirmation_for_another_device_is_rejected
    invoke('different-device') do |_out,err,status,calls,summary|
      refute status.success?
      assert_includes err,'exact approved disposable simulator UDID'
      refute_match(/terminate|uninstall/,calls)
      assert_equal false,summary.fetch('completion_marker')
    end
  end

  def test_help_discloses_the_uninstall_and_required_confirmation
    out,err,status=Open3.capture3('bash',SCRIPT,'--help')
    assert status.success?,err
    assert_includes out,'IOS_UAT_CONFIRM_DISPOSABLE_SIMULATOR'
    assert_includes out,'uninstalls the app'
    assert_includes out,'Never target an existing signed-in app'
  end
end
