# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'
require_relative '../qa/asset_manifest_integrity'

class AssetManifestIntegrityTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('collect-assets-')
    @outside = Dir.mktmpdir('collect-outside-')
    @asset = 'assets/brand/test.png'
    @bytes = "synthetic asset fixture\x00".b
    write(@asset, @bytes)
    write_manifest([entry(@asset)])
  end

  def teardown
    FileUtils.remove_entry(@root)
    FileUtils.remove_entry(@outside)
  end

  def write(path, bytes)
    absolute = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.binwrite(absolute, bytes)
  end

  def entry(path, digest = Digest::SHA256.hexdigest(@bytes))
    "#{digest}  #{path}"
  end

  def write_manifest(lines)
    write(AssetManifestIntegrity::DEFAULT_MANIFEST, lines.join("\n") + "\n")
  end

  def verify(paths = [@asset])
    AssetManifestIntegrity.verify(root: @root, observed_paths: paths)
  end

  def reasons(result)
    result['manifest_errors'].map { |e| e['reason'] }
  end

  def test_matching_manifest_passes_without_modification
    before = Dir.glob(File.join(@root, '**', '*')).select { |p| File.file?(p) }.to_h { |p| [p, File.binread(p)] }
    result = verify
    assert_equal 'pass', result['status']
    refute result['asset_mutations']
    assert_equal before, before.keys.to_h { |p| [p, File.binread(p)] }
  end

  def test_empty_manifest_fails
    write_manifest([])
    assert_includes reasons(verify), 'empty_manifest'
  end

  def test_missing_manifest_fails
    File.delete(File.join(@root, AssetManifestIntegrity::DEFAULT_MANIFEST))
    assert_equal 'fail', verify['status']
    assert_includes reasons(verify), 'missing_file'
  end

  def test_digest_mismatch_fails_and_retains_actual_digest
    write(@asset, 'changed fixture')
    result = verify
    assert_equal 'fail', result['status']
    assert_equal 1, result['hash_mismatches'].size
    assert_equal Digest::SHA256.hexdigest('changed fixture'), result['hash_mismatches'][0]['actual_sha256']
  end

  def test_missing_asset_fails
    File.delete(File.join(@root, @asset))
    assert_includes reasons(verify), 'missing_file'
  end

  def test_unexpected_asset_fails
    write('web/new.png', @bytes)
    assert_equal ['web/new.png'], verify([@asset, 'web/new.png'])['unexpected']
  end

  def test_manifest_entry_missing_from_inventory_fails_even_when_file_exists
    assert_equal [@asset], verify([])['missing']
  end

  def test_duplicate_manifest_entries_fail
    write_manifest([entry(@asset), entry(@asset)])
    assert_includes reasons(verify), 'duplicate_asset_path'
  end

  def test_duplicate_observed_paths_are_deduplicated
    result = verify([@asset, @asset])
    assert_equal 'pass', result['status']
    assert_equal 1, result['observed_count']
  end

  def test_invalid_digest_fails_without_echoing_line
    secret = 'not-a-digest-SENSITIVE-EXAMPLE'
    write_manifest(["#{secret}  #{@asset}"])
    result = verify
    assert_includes reasons(result), 'invalid_manifest_entry'
    refute_includes JSON.generate(result), secret
  end

  def test_absolute_path_is_rejected_before_read
    outside_path = File.join(@outside, 'private.png')
    File.binwrite(outside_path, 'do-not-read')
    write_manifest([entry(outside_path)])
    result = verify
    assert_includes reasons(result), 'invalid_relative_path'
    assert_empty result['hash_mismatches']
    refute_includes JSON.generate(result), @outside
  end

  def test_traversal_is_rejected_before_read
    write_manifest([entry('assets/../../private.png')])
    result = verify
    assert_includes reasons(result), 'invalid_relative_path'
    assert_empty result['hash_mismatches']
  end

  def test_wrong_asset_root_fails
    write_manifest([entry('lib/private.png')])
    assert_includes reasons(verify), 'outside_asset_roots'
  end

  def test_prefix_lookalike_does_not_match_root
    write_manifest([entry('assets-backup/test.png')])
    assert_includes reasons(verify), 'outside_asset_roots'
  end

  def test_non_visual_files_are_not_hashed
    write_manifest([entry('assets/brand/private.txt')])
    result = verify
    assert_includes reasons(result), 'not_visual_asset'
    assert_empty result['hash_mismatches']
  end

  def test_noncanonical_and_windows_paths_are_rejected
    ['assets//test.png', 'assets/./test.png', 'assets/test.png/',
     'C:/secret.png', 'assets\\brand\\test.png', '//server/test.png',
     "assets/brand/bad\tname.png"].each do |path|
      assert_raises(AssetManifestIntegrity::InvalidPath) { AssetManifestIntegrity.validate_asset!(path) }
    end
  end

  def test_spaces_and_unicode_filenames_are_supported
    path = 'assets/brand/Umutungo wacu é.png'
    write(path, @bytes)
    write_manifest([entry(path)])
    assert_equal 'pass', verify([path])['status']
  end

  def test_crlf_and_blank_lines_supported
    write(AssetManifestIntegrity::DEFAULT_MANIFEST, "\r\n#{entry(@asset)}\r\n")
    assert_equal 'pass', verify['status']
  end

  def test_leaf_symlink_is_rejected
    target = File.join(@outside, 'private.png')
    File.binwrite(target, @bytes)
    File.delete(File.join(@root, @asset))
    File.symlink(target, File.join(@root, @asset))
    result = verify
    assert_includes reasons(result), 'symlink_not_allowed'
    assert_empty result['hash_mismatches']
  end

  def test_directory_symlink_is_rejected
    File.binwrite(File.join(@outside, 'private.png'), @bytes)
    File.symlink(@outside, File.join(@root, 'assets/linked'))
    write_manifest([entry('assets/linked/private.png')])
    assert_includes reasons(verify(['assets/linked/private.png'])), 'symlink_not_allowed'
  end

  def test_internal_symlink_is_also_rejected
    File.symlink(File.join(@root, @asset), File.join(@root, 'assets/alias.png'))
    write_manifest([entry('assets/alias.png')])
    assert_includes reasons(verify(['assets/alias.png'])), 'symlink_not_allowed'
  end

  def test_manifest_symlink_is_rejected
    outside_path = File.join(@outside, 'manifest')
    File.write(outside_path, entry(@asset))
    manifest = File.join(@root, AssetManifestIntegrity::DEFAULT_MANIFEST)
    File.delete(manifest)
    File.symlink(outside_path, manifest)
    assert_includes reasons(verify), 'symlink_not_allowed'
  end

  def test_unexpected_symlink_is_not_silently_ignored
    File.symlink(File.join(@root, @asset), File.join(@root, 'assets/alias.png'))
    result = verify([@asset, 'assets/alias.png'])
    assert_includes result['unexpected'], 'assets/alias.png'
    assert_includes reasons(result), 'symlink_not_allowed'
  end

  def test_directory_as_asset_fails
    File.delete(File.join(@root, @asset))
    FileUtils.mkdir_p(File.join(@root, @asset))
    assert_includes reasons(verify), 'not_regular_file_path'
  end

  def test_fifo_as_asset_is_rejected_without_opening
    File.delete(File.join(@root, @asset))
    File.mkfifo(File.join(@root, @asset))
    assert_includes reasons(verify), 'not_regular_file_path'
  end

  def test_invalid_utf8_manifest_fails
    write(AssetManifestIntegrity::DEFAULT_MANIFEST, "\xff\xfe".b)
    assert_includes reasons(verify), 'invalid_manifest_encoding'
  end

  def test_oversized_manifest_fails
    write(AssetManifestIntegrity::DEFAULT_MANIFEST, 'x' * (AssetManifestIntegrity::MAX_MANIFEST_BYTES + 1))
    assert_includes reasons(verify), 'file_too_large'
  end

  def test_hash_supports_multiple_chunks
    bytes = 'x' * 200_000
    write(@asset, bytes)
    write_manifest([entry(@asset, Digest::SHA256.hexdigest(bytes))])
    assert_equal 'pass', verify['status']
  end

  def test_file_modified_while_reading_is_rejected
    error = assert_raises(AssetManifestIntegrity::InvalidPath) do
      AssetManifestIntegrity.read_regular(@root, @asset) do |io|
        io.read
        write(@asset, 'different length content')
      end
    end
    assert_equal 'file_changed_during_read', error.message
  end

  def test_file_replaced_while_reading_is_rejected
    error = assert_raises(AssetManifestIntegrity::InvalidPath) do
      AssetManifestIntegrity.read_regular(@root, @asset) do |io|
        io.read
        write('assets/replacement.png', @bytes)
        File.rename(File.join(@root, 'assets/replacement.png'), File.join(@root, @asset))
      end
    end
    assert_equal 'file_changed_during_read', error.message
  end

  def test_all_supported_asset_roots
    paths = AssetManifestIntegrity::ASSET_ROOTS.map { |root| "#{root}/fixture.png" }
    paths.each { |path| write(path, @bytes) }
    write_manifest(paths.map { |path| entry(path) })
    assert_equal 'pass', verify(paths)['status']
  end

  def test_reject_observed_paths_outside_roots
    result = verify([@asset, 'private/extra.png'])
    assert_includes reasons(result), 'observed_outside_asset_roots'
    assert_equal 'fail', result['status']
  end

  def init_git
    system('git', 'init', '-q', @root, exception: true)
  end

  def run_cli(*args)
    script = File.expand_path('../qa/asset_manifest_integrity.rb', __dir__)
    out, err, status = Open3.capture3('ruby', script, '--root', @root, '--json', *args)
    [JSON.parse(out), err, status.exitstatus]
  end

  def test_cli_blocks_non_git_partial_snapshot
    result, err, status = run_cli
    assert_equal 2, status
    assert_equal 'blocked', result['status']
    assert_empty err
  end

  def test_cli_passes_exact_git_fixture
    init_git
    result, _, status = run_cli
    assert_equal 0, status
    assert_equal 'pass', result['status']
  end

  def test_cli_detects_untracked_assets
    init_git
    write('web/extra.png', @bytes)
    result, _, status = run_cli
    assert_equal 1, status
    assert_includes result['unexpected'], 'web/extra.png'
  end

  def test_cli_keeps_deleted_indexed_assets
    init_git
    system('git', '-C', @root, 'add', '--', @asset, exception: true)
    File.delete(File.join(@root, @asset))
    result, _, status = run_cli
    assert_equal 1, status
    assert_includes reasons(result), 'missing_file'
    assert_includes result['missing'], @asset
    assert_equal [@asset], result['indexed_absent_visual_paths']
  end

  def test_cli_reports_removed_unapproved_indexed_assets_without_treating_them_as_present
    init_git
    retired = 'assets/brand/retired.png'
    write(retired, @bytes)
    system('git', '-C', @root, 'add', '--', retired, exception: true)
    File.delete(File.join(@root, retired))
    result, _, status = run_cli
    assert_equal 0, status
    assert_equal 'pass', result['status']
    assert_equal [retired], result['indexed_absent_visual_paths']
    assert_equal 1, result['observed_count']
    assert_empty result['unexpected']
  end

  def test_cli_uses_git_ignore_rules_for_untracked_files
    init_git
    write('.gitignore', "assets/ignored.png\n")
    write('assets/ignored.png', @bytes)
    result, _, status = run_cli
    assert_equal 0, status
    assert_equal 1, result['observed_count']
  end

  def test_cli_rejects_unknown_arguments
    result, _, status = run_cli('--apply')
    assert_equal 2, status
    assert_equal 'blocked', result['status']
  end

  def test_cli_rejects_nested_checkout_root
    init_git
    nested = File.join(@root, 'nested')
    FileUtils.mkdir_p(nested)
    assert_raises(AssetManifestIntegrity::IncompleteInventory) { AssetManifestIntegrity.git_asset_paths(nested) }
  end
end
