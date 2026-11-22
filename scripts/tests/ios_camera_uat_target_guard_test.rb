require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'json'

class IosCameraUatTargetGuardTest < Minitest::Test
  SCRIPT = File.expand_path('../ios_simulator_camera_permission_uat.sh', __dir__)

  def test_missing_or_wrong_disposable_confirmation_never_calls_native_tools
    [nil, 'another-device'].each do |confirmation|
      Dir.mktmpdir('collect-camera-target-guard-') do |directory|
        native_tool = File.join(directory, 'native-tool')
        calls = File.join(directory, 'calls')
        File.write(native_tool, "#!/bin/bash\nprintf '%s\\n' \"$*\" >> \"$MOCK_CALLS\"\nexit 99\n")
        File.chmod(0700, native_tool)
        evidence = File.join(directory, 'evidence')
        _out, err, status = Open3.capture3({
          'FLUTTER' => native_tool, 'XCRUN' => native_tool,
          'XCODEBUILD' => native_tool, 'MOCK_CALLS' => calls,
          'IOS_CAMERA_UAT_SIMULATOR_ID' => 'intended-device',
          'IOS_UAT_CONFIRM_DISPOSABLE_SIMULATOR' => confirmation,
          'IOS_CAMERA_UAT_EVIDENCE_DIR' => evidence
        }, 'bash', SCRIPT)
        refute status.success?
        assert_includes err, 'exact disposable-simulator confirmation'
        refute File.exist?(calls), 'No native tool may run before approval'
        summary = JSON.parse(File.read(File.join(evidence, 'summary.json')))
        assert_equal false, summary.fetch('evidence_accepted')
      end
    end
  end

  def test_help_discloses_fixture_and_permission_changes
    out, err, status = Open3.capture3('bash', SCRIPT, '--help')
    assert status.success?, err
    assert_includes out, 'IOS_UAT_CONFIRM_DISPOSABLE_SIMULATOR'
    assert_includes out, 'changes its camera permission'
  end
end
