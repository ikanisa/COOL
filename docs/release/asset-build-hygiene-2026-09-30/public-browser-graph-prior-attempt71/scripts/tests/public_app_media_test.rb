require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'base64'
require_relative '../public_app_media'

class PublicAppMediaTest < Minitest::Test
  def fixture
    Dir.mktmpdir('collect-public-media-') do |root|
      FileUtils.mkdir_p([File.join(root, 'web/public/app-screens'), File.join(root, '.cache/captures'), File.join(root, 'lib')])
      File.write(File.join(root, 'pubspec.yaml'), 'version: 1.2.4+23')
      File.write(File.join(root, 'pubspec.lock'), 'fixture')
      File.write(File.join(root, 'lib/app.dart'), 'current application')
      image = Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1kAAAAASUVORK5CYII=')
      asset = File.join(root, 'web/public/app-screens/home.png')
      File.binwrite(asset, image)
      File.binwrite(File.join(root, '.cache/captures/home.png'), image)
      manifest = {
        'runtime_sha256' => PublicAppMedia.new(root).runtime_fingerprint,
        'screens' => [{'id' => 'home', 'file' => 'home.png', 'capture' => '.cache/captures/home.png',
                      'sha256' => Digest::SHA256.hexdigest(image), 'width' => 1, 'height' => 1,
                      'reviewed_for_website' => true, 'capture_kind' => 'native_ios_fixture'}]
      }
      File.write(File.join(root, 'web/public/app-screens/manifest.json'), JSON.generate(manifest))
      File.write(File.join(root, 'web/public/app-screens/capture-provenance.json'), JSON.generate({
        'status' => 'pass', 'installed_matches_retained_bundle' => true,
        'runtime_sha256' => manifest['runtime_sha256'],
        'captures' => [{'path' => '.cache/captures/home.png', 'sha256' => Digest::SHA256.hexdigest(image), 'width' => 1, 'height' => 1}]
      }))
      yield root, asset
    end
  end

  def test_unchanged_original_capture_is_available
    fixture { |root, _| assert_equal '/assets/app-screens/home.png', PublicAppMedia.new(root).screens.fetch('home')['url'] }
  end

  def test_replaced_or_edited_image_is_rejected
    fixture do |root, asset|
      File.binwrite(asset, 'invented replacement image')
      assert_match(/differs from its original/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_app_change_requires_new_captures
    fixture do |root, _|
      File.write(File.join(root, 'lib/app.dart'), 'changed application')
      assert_match(/runtime changed/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def local_fork_fixture
    fixture do |root, _|
      File.write(File.join(root, 'pubspec.yaml'), YAML.dump({'version' => '1.2.4+23', 'dependency_overrides' => {'gotrue' => {'path' => 'third_party/gotrue'}}}))
      FileUtils.mkdir_p(File.join(root, 'third_party/gotrue/lib'))
      %w[lib/gotrue.dart pubspec.yaml LICENSE COLLECT_FORK.md UPSTREAM-SHA256.json].each do |name|
        File.write(File.join(root, 'third_party/gotrue', name), 'synthetic public fork input')
      end
      directory = File.join(root, 'web/public/app-screens')
      sha = PublicAppMedia.new(root).runtime_fingerprint
      %w[manifest.json capture-provenance.json].each do |name|
        path = File.join(directory, name)
        value = JSON.parse(File.read(path))
        value['runtime_sha256'] = sha
        File.write(path, JSON.generate(value))
      end
      yield root
    end
  end

  def test_local_fork_runtime_and_retained_provenance_changes_require_recapture
    %w[lib/gotrue.dart LICENSE COLLECT_FORK.md UPSTREAM-SHA256.json].each do |name|
      local_fork_fixture do |root|
        File.write(File.join(root, 'third_party/gotrue', name), 'changed fork input')
        assert_match(/runtime changed/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
      end
    end
  end

  def test_local_fork_missing_license_symlink_and_escape_are_rejected
    local_fork_fixture do |root|
      File.unlink(File.join(root, 'third_party/gotrue/LICENSE'))
      assert_raises(AssetManifestIntegrity::InvalidPath) { PublicAppMedia.new(root).runtime_fingerprint }
    end
    local_fork_fixture do |root|
      path = File.join(root, 'third_party/gotrue/lib/gotrue.dart')
      File.unlink(path)
      File.symlink(File.join(root, 'lib/app.dart'), path)
      assert_raises(AssetManifestIntegrity::InvalidPath) { PublicAppMedia.new(root).runtime_fingerprint }
    end
    local_fork_fixture do |root|
      File.write(File.join(root, 'pubspec.yaml'), YAML.dump({'dependency_overrides' => {'gotrue' => {'path' => '../outside'}}}))
      assert_raises(AssetManifestIntegrity::InvalidPath) { PublicAppMedia.new(root).runtime_fingerprint }
    end
  end

  def test_local_native_plugin_callback_change_requires_recapture
    local_fork_fixture do |root|
      directory = File.join(root, 'third_party/gotrue/ios')
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, 'callback.m'), 'synthetic changed native callback')
      assert_match(/runtime changed/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_clean_checkout_uses_retained_native_capture_inventory
    fixture do |root, _|
      FileUtils.rm_r(File.join(root, '.cache'))
      assert_equal '/assets/app-screens/home.png', PublicAppMedia.new(root).screens.fetch('home')['url']
    end
  end

  def test_injected_android_provider_configuration_does_not_change_ios_media
    fixture do |root, _|
      directory = File.join(root, 'android/app/src/production')
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, 'google-services.json'), '{"project_info":{}}')
      assert_equal '/assets/app-screens/home.png', PublicAppMedia.new(root).screens.fetch('home')['url']
    end
  end

  def test_native_application_manifest_change_still_requires_recapture
    fixture do |root, _|
      directory = File.join(root, 'android/app/src/main')
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, 'AndroidManifest.xml'), '<manifest/>')
      assert_match(/runtime changed/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_fabricated_capture_manifest_is_rejected
    fixture do |root, _|
      path = File.join(root, 'web/public/app-screens/capture-provenance.json')
      provenance = JSON.parse(File.read(path))
      provenance['captures'][0]['sha256'] = 'invented'
      File.write(path, JSON.generate(provenance))
      assert_match(/absent from native capture provenance/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def browser_fixture
    fixture do |root, asset|
      directory = File.join(root, 'web/public/app-screens')
      manifest = JSON.parse(File.read(File.join(directory, 'manifest.json')))
      capture = manifest.fetch('screens').first
      capture.merge!('capture_kind' => 'browser_flutter_fixture', 'platform' => 'Chromium browser', 'app_route' => '/home')
      File.write(File.join(directory, 'manifest.json'), JSON.generate(manifest))
      build = {'main.dart.js' => 'a' * 64, 'flutter_bootstrap.js' => 'b' * 64}
      report = {'kind' => 'browser_flutter_fixture', 'status' => 'captured_pending_visual_review',
                'sources_unchanged' => true, 'sources_before' => {'lib/app.dart' => 'c' * 64},
                'sources_after' => {'lib/app.dart' => 'c' * 64},
                'runtime_before_sha256' => manifest['runtime_sha256'], 'runtime_after_sha256' => manifest['runtime_sha256'],
                'build_files' => build, 'build_manifest_sha256' => Digest::SHA256.hexdigest(JSON.generate(build)),
                'served_resources' => build, 'errors' => [], 'external_requests' => [],
                'remote_resources_blocked_before_http' => true,
                'provider_calls' => 0, 'hosted_calls' => 0, 'database_calls' => 0,
                'commands' => [{'name' => 'flutter-build', 'exit_code' => 0}],
                'captures' => [capture.merge('path' => capture['capture'], 'marker_verified' => true)]}
      review = {'status' => 'pass', 'runtime_sha256' => manifest['runtime_sha256'],
                'build_manifest_sha256' => report['build_manifest_sha256'], 'native_acceptance' => false,
                'screens' => [{'id' => 'home', 'sha256' => capture['sha256'], 'reviewed_for_website' => true}]}
      provenance = {'status' => 'pass', 'kind' => 'browser_flutter_fixture', 'native_capture_passed' => false,
                    'runtime_sha256' => manifest['runtime_sha256'], 'captures' => report['captures'],
                    'capture_report' => '.cache/captures/report.json', 'visual_review' => '.cache/captures/review.json'}
      save_browser = lambda do
        report_bytes = JSON.generate(report)
        provenance['capture_report_sha256'] = Digest::SHA256.hexdigest(report_bytes)
        review['capture_report_sha256'] = provenance['capture_report_sha256']
        review_bytes = JSON.generate(review)
        provenance['visual_review_sha256'] = Digest::SHA256.hexdigest(review_bytes)
        File.write(File.join(root, provenance['capture_report']), report_bytes)
        File.write(File.join(root, provenance['visual_review']), review_bytes)
        File.write(File.join(directory, 'capture-provenance.json'), JSON.generate(provenance))
      end
      save_browser.call
      yield root, asset, report, review, provenance, save_browser
    end
  end

  def test_browser_capture_passes_only_with_separate_browser_evidence
    browser_fixture do |root, _asset, _report, _review, provenance, _save|
      refute provenance['native_capture_passed']
      assert_equal 'browser_flutter_fixture', PublicAppMedia.new(root).screens.fetch('home')['capture_kind']
    end
  end

  def test_browser_capture_does_not_satisfy_native_installed_bundle_check
    browser_fixture do |root, _asset, _report, _review, _provenance, _save|
      path = File.join(root, 'web/public/app-screens/manifest.json')
      manifest = JSON.parse(File.read(path))
      manifest['screens'][0]['capture_kind'] = 'native_ios_fixture'
      File.write(path, JSON.generate(manifest))
      assert_match(/native provenance is incomplete/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_isolated_browser_capture_requires_unchanged_generated_bindings_and_checkout_runtime
    browser_fixture do |root, _asset, report, _review, _provenance, save|
      report.merge!('isolated_source_export' => true, 'source_root' => '/synthetic/export',
                    'checkout_runtime_before_sha256' => report['runtime_before_sha256'],
                    'checkout_runtime_after_sha256' => report['runtime_after_sha256'],
                    'capture_recorder_sha256' => 'a' * 64,
                    'generated_bindings_unchanged' => true,
                    'generated_bindings_before' => {'.dart_tool/package_config.json' => 'b' * 64,
                                                    '.flutter-plugins-dependencies' => 'c' * 64})
      report['generated_bindings_after'] = report['generated_bindings_before'].dup
      report['resolved_local_bindings_before'] = {
        'collect_app' => '/synthetic/export', 'file_saver' => '/synthetic/export/third_party/file_saver',
        'gotrue' => '/synthetic/export/third_party/gotrue',
        'firebase_messaging' => '/synthetic/export/third_party/firebase_messaging'
      }
      report['resolved_local_bindings_after'] = report['resolved_local_bindings_before'].dup
      save.call
      assert_equal 'browser_flutter_fixture', PublicAppMedia.new(root).screens.fetch('home')['capture_kind']
      report['generated_bindings_after']['.flutter-plugins-dependencies'] = 'd' * 64
      save.call
      assert_match(/source binding is incomplete/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
      report['generated_bindings_after'] = report['generated_bindings_before'].dup
      report['checkout_runtime_after_sha256'] = 'e' * 64
      save.call
      assert_match(/source binding is incomplete/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_browser_wrong_served_application_bytes_fail
    browser_fixture do |root, _asset, report, _review, _provenance, save|
      report['served_resources']['main.dart.js'] = 'd' * 64
      save.call
      assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }
    end
  end

  def test_browser_changed_inputs_during_capture_fail
    browser_fixture do |root, _asset, report, _review, _provenance, save|
      report['sources_after']['lib/app.dart'] = 'd' * 64
      save.call
      assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }
    end
  end

  def test_browser_unreviewed_capture_fails
    browser_fixture do |root, _asset, _report, review, _provenance, save|
      review['screens'][0]['reviewed_for_website'] = false
      save.call
      assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }
    end
  end

  def test_browser_review_for_wrong_image_fails
    browser_fixture do |root, _asset, _report, review, _provenance, save|
      review['screens'][0]['sha256'] = 'e' * 64
      save.call
      assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }
    end
  end

  def test_browser_wrong_route_fails
    browser_fixture do |root, _asset, report, _review, _provenance, save|
      report['captures'][0]['app_route'] = '/auth'
      save.call
      assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }
    end
  end

  def test_browser_failed_build_fails
    browser_fixture do |root, _asset, report, _review, _provenance, save|
      report['commands'][0]['exit_code'] = 1
      save.call
      assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }
    end
  end

  def test_browser_network_and_provider_calls_fail
    browser_fixture do |root, _asset, report, _review, _provenance, save|
      report['external_requests'] = ['https://example.invalid/']
      report['provider_calls'] = 1
      save.call
      assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }
    end
  end

  def test_browser_evidence_edit_or_symlink_fails
    browser_fixture do |root, _asset, _report, _review, provenance, _save|
      path = File.join(root, provenance['capture_report'])
      File.write(path, 'edited evidence')
      assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }
    end
  end
end
