# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'digest'
require 'json'
require 'open3'

# Isolated gate fixtures, not production artwork or release approval.
class AssetHygieneIntegrationTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('collect-hygiene-')
    @outside = Dir.mktmpdir('collect-hygiene-outside-')
    source = File.expand_path('..', __dir__)
    write('scripts/source_integrity_gate.sh', File.binread(File.join(source, 'source_integrity_gate.sh')))
    write('scripts/qa/asset_manifest_integrity.rb', File.binread(File.join(source, 'qa/asset_manifest_integrity.rb')))
    write('lib/main.dart', "'COLLECT_MOBILE_EVIDENCE_MODE'\nif (mobileEvidenceMode) {}")
    write('scripts/release_secret_scan.sh', "#!/bin/bash\nexit 0\n")
    write('scripts/collect_product_boundary_scan.sh', "#!/bin/bash\nprintf '%s\\n' '{\"status\":\"pass\",\"hit_count\":0,\"scanned_files\":1}'\n")
    @asset = 'assets/brand/fixture.png'
    @bytes = 'synthetic public artwork fixture'
    write(@asset, @bytes)
    manifest(Digest::SHA256.hexdigest(@bytes), @asset)
    system('git', 'init', '-q', @root, exception: true)
  end

  def teardown
    FileUtils.remove_entry(@root)
    FileUtils.remove_entry(@outside)
  end

  def write(path, data)
    absolute = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.binwrite(absolute, data)
  end

  def manifest(digest, path)
    write('assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256', "#{digest}  #{path}\n")
  end

  def gate
    stdout, stderr, status = Open3.capture3('bash', 'scripts/source_integrity_gate.sh', '--json', chdir: @root)
    assert_empty stderr
    [JSON.parse(stdout), status.exitstatus]
  end

  def test_integrated_manifest_check_passes_only_its_own_fixture
    report, code = gate
    assert_equal 'pass', report.dig('checks', 'approved_product_visual_assets', 'status')
    # Canonical logo bytes are not forged: this fixture must remain globally fail.
    assert_equal 'fail', report.dig('checks', 'official_logo_identity', 'status')
    assert_equal 1, code
    assert_equal %w[approved_product_visual_assets fixture_isolation official_logo_identity product_boundary secret_scan].sort, report['checks'].keys.sort
    assert_equal 'pass', report.dig('checks', 'fixture_isolation', 'status')
    assert_equal 'pass', report.dig('checks', 'secret_scan', 'status')
    assert_equal 'pass', report.dig('checks', 'product_boundary', 'status')
  end

  def test_hash_mismatch_remains_a_failure
    write(@asset, 'modified fixture')
    report, code = gate
    assert_equal 1, code
    assert_equal 1, report.dig('checks', 'approved_product_visual_assets', 'hash_mismatches').length
  end

  def test_unsafe_manifest_does_not_disclose_external_digest
    path = File.join(@outside, 'secret.png')
    private_bytes = 'PRIVATE TEST SENTINEL DO NOT DISCLOSE'
    File.write(path, private_bytes)
    manifest('0' * 64, path)
    report, code = gate
    assert_equal 1, code
    check = report.dig('checks', 'approved_product_visual_assets')
    assert_includes check['manifest_errors'].map { |e| e['reason'] }, 'invalid_relative_path'
    serialized = JSON.generate(report)
    refute_includes serialized, private_bytes
    refute_includes serialized, Digest::SHA256.hexdigest(private_bytes)
    refute_includes serialized, @outside
  end

  def test_symlink_is_rejected_through_existing_gate
    target = File.join(@outside, 'target.png')
    File.write(target, @bytes)
    File.delete(File.join(@root, @asset))
    File.symlink(target, File.join(@root, @asset))
    report, code = gate
    assert_equal 1, code
    assert_includes report.dig('checks', 'approved_product_visual_assets', 'manifest_errors').map { |e| e['reason'] }, 'symlink_not_allowed'
  end

  def test_broken_symlink_is_rejected_through_existing_gate
    File.delete(File.join(@root, @asset))
    File.symlink(File.join(@outside, 'missing.png'), File.join(@root, @asset))
    report, code = gate
    assert_equal 1, code
    assert_includes report.dig('checks', 'approved_product_visual_assets', 'manifest_errors').map { |e| e['reason'] }, 'symlink_not_allowed'
  end

  def test_missing_manifest_does_not_crash_or_pass
    File.delete(File.join(@root, 'assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256'))
    report, code = gate
    assert_equal 1, code
    assert_equal 'fail', report.dig('checks', 'approved_product_visual_assets', 'status')
  end

  def test_manifested_svg_and_source_styling_are_outside_this_gate
    path = 'assets/fixture.svg'
    write(path, 'synthetic non-image fixture')
    write('lib/features/example.dart', "TextStyle(fontFamily: 'Another Family', fontWeight: FontWeight.w900); LinearGradient(); SvgPicture.asset('fixture.svg');")
    write('assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256', "#{Digest::SHA256.hexdigest(@bytes)}  #{@asset}\n#{Digest::SHA256.hexdigest('synthetic non-image fixture')}  #{path}\n")
    report, code = gate
    assert_equal 1, code
    assert_equal 'pass', report.dig('checks', 'approved_product_visual_assets', 'status')
    assert_equal ['official_logo_identity'], report['failures'].map { |failure| failure['check'] }
  end

  def test_no_asset_or_manifest_writes
    paths = [@asset, 'assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256']
    before = paths.to_h { |path| [path, File.binread(File.join(@root, path))] }
    gate
    assert_equal before, paths.to_h { |path| [path, File.binread(File.join(@root, path))] }
  end

  def test_fixture_leak_is_still_blocked
    write('lib/features/unsafe.dart', 'FixtureCollectRepository()')
    report, code = gate
    assert_equal 1, code
    assert_equal 'fail', report.dig('checks', 'fixture_isolation', 'status')
    assert_includes report.dig('checks', 'fixture_isolation', 'hits').map { |hit| hit['check'] }, 'fixture_runtime_leak'
  end

  def test_secret_scan_failure_is_still_blocked
    write('scripts/release_secret_scan.sh', "#!/bin/bash\nexit 1\n")
    report, code = gate
    assert_equal 1, code
    assert_equal 'fail', report.dig('checks', 'secret_scan', 'status')
  end

  def test_product_boundary_failure_is_still_blocked
    write('scripts/collect_product_boundary_scan.sh', "#!/bin/bash\nprintf '%s\\n' '{\"status\":\"fail\",\"hit_count\":1,\"scanned_files\":1}'\nexit 1\n")
    report, code = gate
    assert_equal 1, code
    assert_equal 'fail', report.dig('checks', 'product_boundary', 'status')
  end
end
