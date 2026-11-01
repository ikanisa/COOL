# Synthetic provenance regressions; these fixtures are not captured app evidence.
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'base64'
require_relative '../public_app_media'

class PublicNativeMediaProvenanceTest < Minitest::Test
  def fixture
    Dir.mktmpdir('collect-native-provenance-') do |root|
      directory = File.join(root, 'web/public/app-screens')
      packet = 'web/public/app-screens/evidence'
      FileUtils.mkdir_p([directory, File.join(root, packet), File.join(root, 'lib'), File.join(root, 'test_driver'), File.join(root, 'assets/brand')])
      File.write(File.join(root, 'pubspec.yaml'), 'version: 1.2.4+23')
      File.write(File.join(root, 'pubspec.lock'), 'synthetic lock')
      File.write(File.join(root, 'lib/app.dart'), 'synthetic runtime')
      File.write(File.join(root, 'test_driver/integration_test.dart'), 'synthetic capture driver')
      approved_path = PublicAppMedia::PUBLISHED_METADATA_INPUT
      File.write(File.join(root, approved_path), 'synthetic approved assets before publication')
      before = packet + '/approved-assets-before.sha256'
      FileUtils.cp(File.join(root, approved_path), File.join(root, before))
      inputs = %w[lib/app.dart pubspec.yaml pubspec.lock test_driver/integration_test.dart].push(approved_path)
        .to_h { |path| [path, Digest::SHA256.file(File.join(root, path)).hexdigest] }
      runtime = PublicAppMedia.new(root).runtime_fingerprint
      png = Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1kAAAAASUVORK5CYII=')
      entries = PublicAppMedia::NATIVE_MEDIA_ROUTES.map do |id, route|
        bytes = png + id
        File.binwrite(File.join(directory, id + '.png'), bytes)
        {'id' => id, 'file' => id + '.png', 'capture' => ".cache/native/#{id}.png", 'sha256' => Digest::SHA256.hexdigest(bytes),
         'width' => 1, 'height' => 1, 'app_route' => route, 'platform' => 'iOS Simulator',
         'capture_kind' => 'native_ios_fixture', 'reviewed_for_website' => true}
      end
      captures = entries.map { |row| row.merge('path' => row['capture'], 'marker_verified' => true, 'marker' => row['id']) }
      log = "collect_native_media:complete:7:network-attempts=0\n" + captures.map { |row| "collect_native_media:pass:#{row['id']}:#{row['app_route']}:#{row['marker']}\n" }.join
      log_path = packet + '/native-drive.stdout'
      File.write(File.join(root, log_path), log)
      bundle = {'Info.plist' => 'a' * 64}
      raw = {'kind' => 'native_ios_fixture', 'status' => 'failed', 'native_capture_passed' => false,
             'runtime_before_sha256' => runtime, 'runtime_after_sha256' => runtime,
             'source_files_unchanged_before_build' => true, 'installed_matches_retained_bundle' => true,
             'provider_calls' => 0, 'hosted_calls' => 0, 'database_calls' => 0, 'bundle_manifest' => bundle,
             'source' => '/synthetic-isolated-source', 'captures' => captures, 'errors' => ['Source drift during native capture'],
             'commands' => %w[native-direct-build native-drive installed-bundle].map { |name| {'name' => name, 'exit_code' => 0, 'stdout_sha256' => Digest::SHA256.hexdigest(log)} }}
      binding = {'kind' => 'native_capture_source_binding_review', 'status' => 'pass', 'runtime_sha256' => runtime,
                 'runtime_matches_capture' => true, 'native_input_checkout_changes' => [], 'native_input_export_changes' => [],
                 'post_export_checkout_changes' => ['test/unused_test.dart'], 'export_source_changes_during_build' => [],
                 'native_capture_input_count' => inputs.length, 'native_capture_inputs' => inputs}
      report = raw.merge('status' => 'captured_pending_visual_review', 'native_capture_passed' => true, 'errors' => [],
                         'native_capture_inputs_unchanged' => true, 'raw_run_errors_retained' => raw['errors'])
      review = {'status' => 'pass', 'native_acceptance' => false, 'runtime_sha256' => runtime,
                'screens' => captures.map { |row| {'id' => row['id'], 'sha256' => row['sha256'], 'reviewed_for_website' => true} }}
      provenance = {'kind' => 'native_ios_fixture', 'status' => 'pass', 'runtime_sha256' => runtime,
                    'native_capture_passed' => true, 'installed_matches_retained_bundle' => true, 'captures' => captures,
                    'bundle_manifest_sha256' => Digest::SHA256.hexdigest(JSON.generate(bundle)),
                    'native_drive_log' => log_path, 'native_drive_log_sha256' => Digest::SHA256.hexdigest(log),
                    'preserved_publication_input' => {'path' => approved_path, 'preserved' => before, 'sha256' => inputs[approved_path]}}
      export = {'destination' => raw['source'], 'source_sha256' => inputs.dup}
      driver = {'path' => 'test_driver/integration_test.dart', 'sha256' => inputs['test_driver/integration_test.dart']}
      manifest = {'runtime_sha256' => runtime, 'screens' => entries}
      save = lambda do
        {'source_binding_review' => binding, 'raw_capture_report' => raw, 'source_export' => export, 'driver_source_binding' => driver}.each do |role, content|
          path = packet + '/' + role + '.json'
          bytes = JSON.generate(content)
          File.write(File.join(root, path), bytes)
          provenance[role] = path
          provenance[role + '_sha256'] = Digest::SHA256.hexdigest(bytes)
        end
        report['source_binding_review_sha256'] = provenance['source_binding_review_sha256']
        report['raw_capture_report_sha256'] = provenance['raw_capture_report_sha256']
        report_bytes = JSON.generate(report)
        provenance['capture_report'] = packet + '/report.json'
        provenance['capture_report_sha256'] = Digest::SHA256.hexdigest(report_bytes)
        review['capture_report_sha256'] = provenance['capture_report_sha256']
        review_bytes = JSON.generate(review)
        provenance['visual_review'] = packet + '/review.json'
        provenance['visual_review_sha256'] = Digest::SHA256.hexdigest(review_bytes)
        File.write(File.join(root, provenance['capture_report']), report_bytes)
        File.write(File.join(root, provenance['visual_review']), review_bytes)
        File.write(File.join(directory, 'capture-provenance.json'), JSON.generate(provenance))
        File.write(File.join(directory, 'manifest.json'), JSON.generate(manifest))
      end
      save.call
      yield root, report, review, raw, binding, provenance, save, manifest
    end
  end

  def android_fixture
    fixture do |root, report, review, raw, binding, provenance, save, manifest|
      certificate = 'c' * 64
      apk_hash = 'b' * 64
      profile = {'device_id_sha256' => 'd' * 64, 'model' => 'Synthetic Android phone', 'android_release' => '13',
                 'api' => 33, 'abi' => 'arm64-v8a', 'width' => 1080, 'height' => 2340, 'density_dpi' => 440}
      android = {'package_name' => PublicAppMedia::ANDROID_PACKAGE, 'flavor' => 'media_capture', 'build_type' => 'debug',
                 'debuggable' => true, 'version_name' => '1.2.4', 'version_code' => 23, 'retained_apk_sha256' => apk_hash,
                 'installed_apk_sha256' => apk_hash, 'certificate_sha256' => certificate, 'device_profile' => profile}
      controls = PublicAppMedia::ANDROID_CAPTURE_CONTROLS.to_h do |path|
        target = File.join(root, path); FileUtils.mkdir_p(File.dirname(target)); File.write(target, 'synthetic control ' + path)
        [path, Digest::SHA256.file(target).hexdigest]
      end
      xml = '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="app.cool.mobile.mediafixture" android:versionName="1.2.4" android:versionCode="23"><uses-permission android:name="android.permission.INTERNET"/><application android:debuggable="true" android:allowBackup="false"><activity android:name="io.flutter.embedding.android.FlutterActivity" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity>'
      %w[firebase_data_collection_default_enabled firebase_messaging_auto_init_enabled firebase_analytics_collection_enabled firebase_crashlytics_collection_enabled].each do |name|
        xml += '<meta-data android:name="' + name + '" android:value="false"/>'
      end
      xml += '</application></manifest>'
      identity = %w[package_name version_name version_code certificate_sha256 retained_apk_sha256 installed_apk_sha256].to_h { |key| [key, android[key]] }
      payloads = {'merged_manifest' => xml, 'apk_manifest' => xml, 'apk_signature' => "Signer #1 certificate SHA-256 digest: #{certificate}",
                  'installed_apk_identity' => JSON.generate(identity), 'device_profile' => JSON.generate(profile)}
      android_evidence = {}
      payloads.each do |role, text|
        path = 'web/public/app-screens/evidence/android-' + role + '.txt'
        File.write(File.join(root, path), text)
        hash = Digest::SHA256.hexdigest(text)
        android_evidence[role] = {'path' => path, 'sha256' => hash}
        provenance['android_' + role] = path
        provenance['android_' + role + '_sha256'] = hash
        command_name = {'apk_manifest' => 'apk-manifest', 'apk_signature' => 'apk-signature', 'installed_apk_identity' => 'installed-bundle', 'device_profile' => 'device-profile'}[role]
        if command_name
          report['commands'].reject! { |row| row['name'] == command_name }
          report['commands'] << {'name' => command_name, 'exit_code' => 0, 'stdout_sha256' => hash}
        end
      end
      manifest['screens'].each { |row| row.merge!('capture_kind' => 'native_android_fixture', 'platform' => 'Android device') }
      report['captures'].each { |row| row.merge!('capture_kind' => 'native_android_fixture', 'platform' => 'Android device', 'capture_surface' => 'flutter_android_surface', 'theme' => 'dark', 'text_scale' => 1.0) }
      values = {'kind' => 'native_android_fixture', 'android' => android, 'android_evidence' => android_evidence,
                'capture_surface' => 'flutter_android_surface', 'bundle_manifest' => {'base.apk' => apk_hash},
                'capture_controls_before' => controls, 'capture_controls_after' => controls.dup,
                'existing_app_metadata_before' => {'app.cool.mobile' => ['versionCode=23'], 'app.cool.mobile.dev' => ['versionCode=23']},
                'existing_app_metadata_after' => {'app.cool.mobile' => ['versionCode=23'], 'app.cool.mobile.dev' => ['versionCode=23']}}
      raw.merge!(values); report.merge!(values)
      provenance['kind'] = 'native_android_fixture'
      provenance['bundle_manifest_sha256'] = Digest::SHA256.hexdigest(JSON.generate(values['bundle_manifest']))
      save.call
      yield root, report, raw, provenance, save
    end
  end

  def test_android_native_packet_has_its_own_strict_platform_chain
    android_fixture { |root, *| assert_equal 7, PublicAppMedia.new(root).screens.length }
  end

  def test_android_wrong_apk_certificate_or_existing_app_change_is_rejected
    %w[installed_apk_sha256 certificate_sha256].each do |field|
      android_fixture do |root, report, _raw, _provenance, save|
        report['android'][field] = 'e' * 64; save.call
        assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }
      end
    end
    android_fixture do |root, report, raw, _provenance, save|
      report['existing_app_metadata_after'] = raw['existing_app_metadata_after'] = {}; save.call
      assert_match(/metadata changed/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_android_provider_receiver_is_rejected_with_rebound_evidence_hashes
    android_fixture do |root, report, _raw, provenance, save|
      path = provenance['android_apk_manifest']
      text = File.read(File.join(root, path)).sub('</application>', '<receiver android:name="unsafe"/></application>')
      File.write(File.join(root, path), text); hash = Digest::SHA256.hexdigest(text)
      provenance['android_apk_manifest_sha256'] = hash
      report['android_evidence']['apk_manifest']['sha256'] = hash
      report['commands'].find { |row| row['name'] == 'apk-manifest' }['stdout_sha256'] = hash
      save.call
      assert_match(/provider or incoming-event/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_android_report_cannot_be_relabelled_as_ios
    android_fixture do |root, report, raw, _provenance, save|
      report['kind'] = raw['kind'] = 'native_ios_fixture'; save.call
      assert_match(/platform differs/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_android_control_source_mutation_is_rejected
    android_fixture do |root, *|
      File.write(File.join(root, 'scripts/qa/native_android_public_app_media.py'), 'mutated producer')
      assert_match(/control source changed/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_current_native_packet_is_reproducible_without_simulator_or_cache
    fixture do |root, *|
      File.write(File.join(root, PublicAppMedia::PUBLISHED_METADATA_INPUT), 'new publication metadata')
      assert_equal PublicAppMedia::NATIVE_MEDIA_ROUTES.keys.sort, PublicAppMedia.new(root).screens.keys.sort
    end
  end

  def test_unreviewed_image_is_rejected
    fixture do |root, _report, review, _raw, _binding, _provenance, save|
      review['screens'][0]['reviewed_for_website'] = false
      save.call
      assert_match(/route\/image review/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_raw_network_failure_cannot_be_corrected_by_source_review
    fixture do |root, _report, _review, raw, _binding, _provenance, save|
      raw['provider_calls'] = 1
      save.call
      assert_match(/source-binding review differs/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_omitting_source_input_is_rejected
    fixture do |root, _report, _review, _raw, binding, _provenance, save|
      binding['native_capture_inputs'].delete('lib/app.dart')
      binding['native_capture_input_count'] -= 1
      save.call
      assert_match(/inventory differs/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_exempting_native_drift_is_rejected
    fixture do |root, _report, _review, _raw, binding, _provenance, save|
      binding['post_export_checkout_changes'] << 'ios/Runner/AppDelegate.swift'
      save.call
      assert_match(/source-binding review differs/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_preserved_source_input_edit_is_rejected
    fixture do |root, _report, _review, _raw, _binding, provenance, _save|
      File.write(File.join(root, provenance['preserved_publication_input']['preserved']), 'edited prior input')
      assert_match(/compilation input changed/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end

  def test_bound_capture_report_edit_is_rejected
    fixture do |root, _report, _review, _raw, _binding, provenance, _save|
      File.write(File.join(root, provenance['capture_report']), '{}')
      assert_match(/evidence changed/, assert_raises(RuntimeError) { PublicAppMedia.new(root).screens }.message)
    end
  end
end
