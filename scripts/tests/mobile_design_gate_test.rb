# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../qa/mobile_design_gate'

class MobileDesignGateTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @root = Dir.mktmpdir('collect-design-gate-test-')
    @gate = MobileDesignGate.new(@root)
    contract = JSON.parse(File.read(File.join(ROOT, MobileDesignGate::CONTRACT)))
    contract['reference_paths'] = ['references/home.png']
    contract['additional_states'] = ['home-joined']
    contract['variant_cases'] = ['home']
    contract['variants'] = ['light']
    contract['keyboard_cases'] = ['home']
    contract['annotations'] = ['home-cards-member-parity']
    write(MobileDesignGate::CONTRACT, JSON.generate(contract))
    write('lib/main.dart', 'void main() {}')
    write('DESIGN.md', 'MOBILE-DESIGN-100')
    write('pubspec.yaml', "version: 1.2.4+23\n")
    write(contract['route_inventory'], "_RouteSpec('home', '/home', 'primary')")
    write('test/annotation_test.dart', 'test annotation')
    png = File.binread(File.join(ROOT, 'test/goldens/baselines/member_home_dark.png'))
    write('references/home.png', png)
    write('.cache/references/original.png', png)
    width, height = png.byteslice(16, 8).unpack('NN')
    @original_manifest = {
      'schema_version' => 1, 'capture_kind' => 'original_mobile_screenshot',
      'images' => [{ 'id' => 'original-home', 'path' => '.cache/references/original.png',
        'sha256' => @gate.digest('.cache/references/original.png'), 'width' => width, 'height' => height,
        'source_url' => 'https://drive.google.com/file/d/synthetic-test-fixture/view' }]
    }
    write(contract['original_reference_manifest'], JSON.generate(@original_manifest))
    write('output/screenshot.png', png)
    write('output/comparison.png', png)
    MobileDesignGate::ARTIFACTS['android'].each_value { |path| write(path, 'test artifact') }
    write('.cache/mobile-design-build/android.json', JSON.generate(
      'schema_version' => 1, 'platform' => 'android', 'source_sha256' => @gate.source_digest,
      'version' => @gate.fingerprints['version'], 'built_at' => Time.now.utc.iso8601,
      'evidence_mode' => false,
      'artifacts' => MobileDesignGate::ARTIFACTS['android'].transform_values { |p| @gate.digest(p) }
    ))
    @evidence = @gate.fingerprints.merge(
      'schema_version' => 1, 'scope' => 'mobile', 'status' => 'approved',
      'open_findings' => [],
      'artifacts' => { 'android' => MobileDesignGate::ARTIFACTS['android'].transform_values { |p| @gate.digest(p) } },
      'cases' => @gate.required_cases.map do |id|
        {
          'id' => id, 'platform' => 'android',
          'scores' => MobileDesignGate::CRITERIA.to_h { |key| [key, 10] },
          'capture_kind' => 'native',
          'installed_artifact_sha256' => @gate.digest(MobileDesignGate::ARTIFACTS['android']['apk']),
          'screenshot' => image('output/screenshot.png'),
          'comparison' => image('output/comparison.png'),
          'reference_ids' => ['original-home'],
          'review' => { 'reviewer' => 'Synthetic unit-test reviewer', 'at' => Time.now.utc.iso8601,
                        'notes' => 'Synthetic test data only, never real release acceptance.' },
          'interaction_checks' => 'pass', 'accessibility_checks' => 'pass'
        }
      end,
      'annotations' => [{ 'id' => 'home-cards-member-parity', 'status' => 'verified',
        'test_path' => 'test/annotation_test.dart', 'test_sha256' => @gate.digest('test/annotation_test.dart'),
        'cases' => ['home@default'] }]
    )
  end

  def teardown
    FileUtils.remove_entry(@root)
    FileUtils.remove_entry(@external_outputs) if @external_outputs
  end

  def write(path, content)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.binwrite(full, content)
  end

  def image(path)
    { 'path' => path, 'sha256' => @gate.digest(path) }
  end

  def result
    write(MobileDesignGate::ACCEPTANCE, JSON.generate(@evidence))
    @gate.release_result
  end

  def assert_blocked
    payload = result
    assert_equal 'blocked', payload['status']
    assert_nil payload['score']
    refute_empty payload['failures']
  end

  def test_complete_synthetic_evidence_passes
    assert_equal 'pass', result['status']
    assert_equal 100, result['score']
  end

  def test_missing_acceptance_fails_closed
    assert_equal 'blocked', @gate.release_result['status']
  end

  def test_admin_approval_cannot_replace_mobile
    @evidence['scope'] = 'admin'
    assert_blocked
  end

  def test_partial_score_is_not_rounded_up
    @evidence['cases'][0]['scores']['typography'] = 9
    assert_blocked
  end

  def test_unknown_criterion_is_rejected
    @evidence['cases'][0]['scores']['bonus'] = 10
    assert_blocked
  end

  def test_pending_and_open_findings_are_blockers
    @evidence['status'] = 'pending'
    @evidence['open_findings'] = ['HOME']
    assert_blocked
  end

  def test_missing_membership_state_blocks
    @evidence['cases'].reject! { |row| row['id'] == 'home-joined@default' }
    assert_blocked
  end

  def test_duplicate_cases_cannot_inflate_coverage
    @evidence['cases'] << @evidence['cases'][0].dup
    assert_blocked
  end

  def test_new_route_invalidates_coverage_and_source
    write(@gate.contract['route_inventory'], "_RouteSpec('home', '/home', 'primary')\n_RouteSpec('new', '/new', 'primary')")
    assert_blocked
  end

  def test_source_change_invalidates_approval
    write('lib/main.dart', 'void main() { changed(); }')
    assert_blocked
  end

  def test_new_review_cannot_approve_an_old_build
    write('lib/main.dart', 'void main() { newSource(); }')
    @evidence.merge!(@gate.fingerprints)
    assert_blocked
    assert_includes result['failures'], 'Release build provenance does not match current source'
  end

  def test_missing_build_provenance_blocks
    FileUtils.rm(File.join(@root, '.cache/mobile-design-build/android.json'))
    assert_blocked
  end

  def test_reference_change_invalidates_approval
    write('references/home.png', 'changed reference')
    assert_blocked
  end

  def test_contract_can_be_checked_without_private_originals_but_release_cannot
    FileUtils.rm(File.join(@root, '.cache/references/original.png'))
    assert_empty @gate.validate_contract
    assert_blocked
    assert_includes result['failures'], 'Missing or changed original reference: original-home'
  end

  def test_original_pixels_cannot_be_replaced_by_browser_preview
    write('.cache/references/original.png', 'browser preview substituted')
    assert_blocked
  end

  def test_original_manifest_change_stales_acceptance
    @original_manifest['images'][0]['source_url'] = 'https://drive.google.com/file/d/different-original/view'
    write(@gate.contract['original_reference_manifest'], JSON.generate(@original_manifest))
    assert_blocked
    assert_includes result['failures'], 'Stale or absent references_sha256'
  end

  def test_original_dimensions_are_verified
    @original_manifest['images'][0]['width'] += 1
    write(@gate.contract['original_reference_manifest'], JSON.generate(@original_manifest))
    @evidence.merge!(@gate.fingerprints)
    assert_blocked
    assert_includes result['failures'], 'Original reference dimensions changed: original-home'
  end

  def test_comparison_requires_a_known_original_reference
    @evidence['cases'][0]['reference_ids'] = ['unknown']
    assert_blocked
  end

  def test_duplicate_original_ids_are_rejected
    @original_manifest['images'] << @original_manifest['images'][0].dup
    write(@gate.contract['original_reference_manifest'], JSON.generate(@original_manifest))
    assert_includes @gate.validate_contract, 'Duplicate original references'
  end

  def test_artifact_replacement_invalidates_approval
    write(MobileDesignGate::ARTIFACTS['android']['apk'], 'different binary')
    assert_blocked
  end

  def test_controlled_external_output_directory_is_supported
    @external_outputs = Dir.mktmpdir('collect-build-output-test-')
    outputs = File.join(@root, 'build/app/outputs')
    relocated = File.join(@external_outputs, 'outputs')
    FileUtils.mv(outputs, relocated)
    File.symlink(relocated, outputs)
    apk = MobileDesignGate::ARTIFACTS['android']['apk']
    assert_nil @gate.local_file(apk)
    assert @gate.artifact_file(apk)
    assert_equal 'pass', result['status']
    assert_nil @gate.artifact_file('output/screenshot.png')
  end

  def test_release_artifact_itself_must_not_be_a_symlink
    apk = MobileDesignGate::ARTIFACTS['android']['apk']
    full = File.join(@root, apk)
    FileUtils.mv(full, "#{full}.original")
    File.symlink("#{full}.original", full)
    assert_nil @gate.artifact_file(apk)
    assert_blocked
  end

  def test_browser_screenshot_is_not_native_acceptance
    @evidence['cases'][0]['capture_kind'] = 'web'
    assert_blocked
  end

  def test_fixture_binary_is_not_release_binary
    @evidence['cases'][0]['installed_artifact_sha256'] = '0' * 64
    assert_blocked
  end

  def test_changed_screenshot_is_rejected
    write('output/screenshot.png', 'changed image')
    assert_blocked
  end

  def test_missing_comparison_is_rejected
    @evidence['cases'][0].delete('comparison')
    assert_blocked
  end

  def test_outside_paths_and_symlinks_are_rejected
    @evidence['cases'][0]['screenshot'] = { 'path' => '../outside.png', 'sha256' => '0' * 64 }
    assert_blocked
    File.symlink(File.join(ROOT, 'test/goldens/baselines/member_home_dark.png'), File.join(@root, 'output/link.png'))
    assert_nil @gate.local_file('output/link.png')
  end

  def test_missing_reviewer_and_future_review_are_rejected
    @evidence['cases'][0]['review'] = { 'at' => (Time.now.utc + 3600).iso8601 }
    assert_blocked
  end

  def test_unverified_annotation_is_rejected
    @evidence['annotations'][0]['status'] = 'implemented'
    assert_blocked
  end

  def test_changed_regression_test_invalidates_annotation
    write('test/annotation_test.dart', 'changed assertion')
    assert_blocked
  end

  def test_missing_accessibility_check_blocks
    @evidence['cases'][0]['accessibility_checks'] = 'not_assessed'
    assert_blocked
  end

  def test_ios_never_inherits_android_approval
    write(MobileDesignGate::ACCEPTANCE, JSON.generate(@evidence))
    assert_equal 'blocked', @gate.release_result('ios')['status']
  end

  def test_no_cli_bypass_supported
    path = File.join(ROOT, 'scripts/qa/mobile_design_gate.rb')
    assert_equal false, system('ruby', path, '--skip', out: File::NULL, err: File::NULL)
  end
end
