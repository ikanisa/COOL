# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

# Temporary Git checkouts exercise source binding and actual Android metadata
# decoding using valid synthetic containers. SDK/signature/device proof is separate.
class NativeBuildProvenanceTest < Minitest::Test
  def setup
    @temporary = Dir.mktmpdir('collect-native-provenance-')
    @root = File.join(@temporary, 'repo')
    FileUtils.mkdir_p(@root)
    system('git', 'init', '-q', chdir: @root, exception: true)
    source = File.expand_path('../qa/native_build_provenance.rb', __dir__)
    write('scripts/qa/native_build_provenance.rb', File.binread(source))
    helper = File.expand_path('../qa/native_artifact_metadata.py', __dir__)
    write('scripts/qa/native_artifact_metadata.py', File.binread(helper))
    config = File.expand_path('../qa/native_build_config.py', __dir__)
    write('scripts/qa/native_build_config.py', File.binread(config))
    write('pubspec.yaml', "name: synthetic_provenance_fixture\nversion: 1.0.0+1\n")
    write('lib/main.dart', 'synthetic compiled source')
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def write(name, bytes = 'synthetic source')
    path = File.join(@root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, bytes)
    path
  end

  def invoke(*args)
    Open3.capture3('ruby', 'scripts/qa/native_build_provenance.rb', *args, chdir: @root)
  end

  def fingerprint
    output, error, status = invoke('begin', 'android')
    assert status.success?, error
    assert_match(/\A[a-f0-9]{64}\n\z/, output)
    output.strip
  end

  def build_artifacts(name: '1.0.0', code: 1, package: 'app.cool.mobile')
    fixture = File.expand_path('native_artifact_metadata_test.py', __dir__)
    _, error, status = Open3.capture3('python3', fixture, '--write-provenance-fixtures',
                                    @root, name, code.to_s, package)
    assert status.success?, error
  end

  def test_public_configuration_helper_is_required_and_drift_refuses_finish
    before = fingerprint
    write('scripts/qa/native_build_config.py', File.read(File.join(@root, 'scripts/qa/native_build_config.py')) + "\n# changed public profile producer\n")
    refute_equal before, fingerprint
    _, error, status = invoke('finish', 'android', before, '1.0.0+1', Time.now.to_i.to_s)
    refute status.success?
    assert_includes error, 'Source changed during native build'
    refute File.exist?(File.join(@root, '.cache/native-build/android.json'))
    File.unlink(File.join(@root, 'scripts/qa/native_build_config.py'))
    _, error, status = invoke('begin', 'android')
    refute status.success?
    assert_includes error, 'Required native public configuration helper is absent'
  end

  def test_metadata_helper_is_required_and_hash_bound
    before = fingerprint
    write('scripts/qa/native_artifact_metadata.py', File.read(File.join(@root, 'scripts/qa/native_artifact_metadata.py')) + "\n# changed public parser\n")
    refute_equal before, fingerprint
    File.unlink(File.join(@root, 'scripts/qa/native_artifact_metadata.py'))
    _, error, status = invoke('begin', 'android')
    refute status.success?
    assert_includes error, 'Required native artifact metadata helper is absent'
  end

  def test_admin_compilation_source_addition_and_mutation_change_fingerprint
    initial = fingerprint
    write('lib/admin/core/admin_runtime.dart', 'synthetic Admin source v1')
    added = fingerprint
    refute_equal initial, added
    write('lib/admin/core/admin_runtime.dart', 'synthetic Admin source v2')
    refute_equal added, fingerprint
  end

  def test_all_three_local_fork_runtime_and_native_inputs_are_bound
    %w[synthetic_fork file_saver firebase_messaging].each do |fork|
      path = "third_party/#{fork}/lib/entry.dart"
      write(path, 'synthetic fork v1')
      before = fingerprint
      write(path, 'synthetic fork v2')
      refute_equal before, fingerprint, fork
      native = "third_party/#{fork}/ios/Plugin.m"
      before_native = fingerprint
      write(native, 'synthetic native input')
      refute_equal before_native, fingerprint, native
    end
  end

  def test_native_lockfiles_and_license_bytes_are_bound
    %w[android/app/gradle.lockfile ios/Podfile.lock licenses/NOTICE third_party/synthetic_fork/LICENSE].each do |name|
      write(name, 'synthetic original')
      before = fingerprint
      write(name, 'synthetic changed')
      refute_equal before, fingerprint, name
    end
  end

  def test_ignored_generated_files_and_indexed_private_inputs_are_excluded
    write('.gitignore', "android/generated/\n")
    before = fingerprint
    write('android/generated/cache.bin', 'synthetic generated data')
    %w[android/key.properties android/upload.jks ios/Runner/GoogleService-Info.plist third_party/synthetic_fork/.env].each do |name|
      write(name, 'synthetic private fixture')
      system('git', 'add', name, chdir: @root, exception: true)
    end
    assert_equal before, fingerprint
  end

  def test_external_source_symlink_is_rejected_without_printing_its_bytes
    external = File.join(@temporary, 'external.dart')
    File.write(external, 'synthetic external content')
    File.symlink(external, File.join(@root, 'lib', 'external.dart'))
    output, error, status = invoke('begin', 'android')
    refute status.success?
    assert_equal '', output
    assert_includes error, 'Native source escapes checkout'
    refute_includes error, 'synthetic external content'
  end

  def test_finish_refuses_a_changed_admin_source_before_writing_manifest
    write('lib/admin/route.dart', 'synthetic original')
    before = fingerprint
    write('lib/admin/route.dart', 'synthetic changed')
    _, error, status = invoke('finish', 'android', before, '1.0.0+1', Time.now.to_i.to_s)
    refute status.success?
    assert_includes error, 'Source changed during native build'
    refute File.exist?(File.join(@root, '.cache/native-build/android.json'))
  end

  def test_finish_records_an_inspectable_exact_source_inventory
    write('lib/admin/route.dart')
    write('third_party/synthetic_fork/lib/entry.dart')
    before = fingerprint
    build_artifacts
    _, error, status = invoke('finish', 'android', before, '1.0.0+1', (Time.now.to_i - 1).to_s)
    assert status.success?, error
    manifest = JSON.parse(File.read(File.join(@root, '.cache/native-build/android.json')))
    assert_equal 3, manifest.fetch('schema_version')
    assert_equal before, manifest.fetch('source_sha256')
    assert_equal manifest.fetch('source_files').length, manifest.fetch('source_file_count')
    assert manifest.fetch('source_files').key?('lib/admin/route.dart')
    assert manifest.fetch('source_files').key?('third_party/synthetic_fork/lib/entry.dart')
    assert_equal false, manifest.fetch('release_approval')
    assert_equal manifest.fetch('source_files').fetch('scripts/qa/native_build_config.py'), manifest.fetch('public_configuration_helper_sha256')
    assert_equal manifest.fetch('source_files').fetch('scripts/qa/native_artifact_metadata.py'), manifest.fetch('metadata_helper_sha256')
    %w[apk aab].each do |kind|
      observed = manifest.fetch('artifact_metadata').fetch(kind)
      assert_equal 'pass', observed.fetch('status')
      assert_equal 'app.cool.mobile', observed.fetch('actual').fetch('package')
      assert_equal '1.0.0', observed.fetch('actual').fetch('version_name')
      assert_equal 1, observed.fetch('actual').fetch('version_code')
    end
  end

  def test_matching_version_argument_cannot_admit_wrong_artifact_versions_or_package
    [{ name: '1.0' }, { code: 2 }, { package: 'app.other.mobile' }].each do |changed|
      before = fingerprint
      build_artifacts(**changed)
      _, error, status = invoke('finish', 'android', before, '1.0.0+1', (Time.now.to_i - 1).to_s)
      refute status.success?
      assert_includes error, 'Android artifact metadata verification failed'
      refute File.exist?(File.join(@root, '.cache/native-build/android.json'))
    end
  end

  def test_fresh_large_unreadable_artifact_cannot_write_provenance
    before = fingerprint
    write('build/app/outputs/flutter-apk/app-production-release.apk', 'PRIVATE_FIXTURE_MUST_NOT_LEAK' * 50_000)
    write('build/app/outputs/bundle/productionRelease/app-production-release.aab', '1' * 1_000_001)
    output, error, status = invoke('finish', 'android', before, '1.0.0+1', (Time.now.to_i - 1).to_s)
    refute status.success?
    refute_includes output + error, 'PRIVATE_FIXTURE'
    refute File.exist?(File.join(@root, '.cache/native-build/android.json'))
  end

  def test_stale_or_symlink_artifacts_cannot_write_provenance
    before = fingerprint
    build_artifacts
    artifact = File.join(@root, 'build/app/outputs/flutter-apk/app-production-release.apk')
    old = Time.now.to_i - 30
    File.utime(Time.at(old), Time.at(old), artifact)
    _, error, status = invoke('finish', 'android', before, '1.0.0+1', (old + 5).to_s)
    refute status.success?
    assert_includes error, 'Artifact predates this build'
    build_artifacts
    target = File.join(@temporary, 'fixture.apk')
    FileUtils.mv(artifact, target)
    File.symlink(target, artifact)
    _, error, status = invoke('finish', 'android', before, '1.0.0+1', (Time.now.to_i - 1).to_s)
    refute status.success?
    assert_includes error, 'Missing native artifact'
    refute File.exist?(File.join(@root, '.cache/native-build/android.json'))
  end
end
