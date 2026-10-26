require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class IosUatBuildAndDriveTest < Minitest::Test
  SCRIPT = File.expand_path('../ios_uat_build_and_drive.sh', __dir__)

  def invoke(build_status: 0, bundle: 'app.cool.mobile')
    Dir.mktmpdir('collect-ios-build-guard-') do |directory|
      calls = File.join(directory, 'calls')
      flutter = File.join(directory, 'flutter')
      app = File.join(directory, 'Collect.app')
      Dir.mkdir(app)
      # Stale binary deliberately exists even when the new build fails.
      File.write(File.join(app, 'Info.plist'), <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>#{bundle}</string></dict></plist>
      XML
      File.write(flutter, <<~SH)
        #!/bin/bash
        printf '%s\\n' "$*" >> "$MOCK_CALLS"
        if [[ "$1" == build ]]; then exit "$MOCK_BUILD_STATUS"; fi
        if [[ "$1" == drive ]]; then exit 0; fi
        exit 99
      SH
      File.chmod(0700, flutter)
      out, err, status = Open3.capture3(
        {'MOCK_CALLS' => calls, 'MOCK_BUILD_STATUS' => build_status.to_s},
        'bash', SCRIPT, flutter, 'test_driver/integration_test.dart',
        'integration_test/fixture.dart', 'approved-fixture-device',
        'app.cool.mobile', app, '--dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true'
      )
      yield out, err, status, File.read(calls), app
    end
  end

  def test_failed_build_never_launches_or_attaches_to_stale_binary
    invoke(build_status: 1) do |out, _err, status, calls, _app|
      refute status.success?
      refute_includes calls, 'drive '
      refute_includes out, 'fresh-build-ready'
    end
  end

  def test_wrong_bundle_never_launches
    invoke(bundle: 'different.app') do |_out, err, status, calls, _app|
      refute status.success?
      assert_includes err, 'does not match'
      refute_includes calls, 'drive '
    end
  end

  def test_success_uses_fresh_binary_and_exact_device
    invoke do |out, err, status, calls, app|
      assert status.success?, err
      assert_includes out, 'fresh-build-ready bundle=app.cool.mobile'
      assert_includes calls, '--use-application-binary=' + app
      assert_includes calls, '-d approved-fixture-device'
      assert_equal 2, calls.scan('COLLECT_MOBILE_EVIDENCE_MODE=true').length
    end
  end
end
