# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require_relative '../qa/group_runtime_integrity'

# Deliberately synthetic byte fixtures: these test consistency, not image decode.
class GroupRuntimeIntegrityTest < Minitest::Test
  BANK = GroupRuntimeIntegrity::BANK
  def setup
    @root = Dir.mktmpdir('collect-runtime-test-')
    id = 'rw-01-test-group'
    source = "#{BANK}/source/#{id}-v1.png"
    @record = { 'id' => id, 'version' => 1, 'source' => source,
                'source_sha256' => Digest::SHA256.hexdigest('synthetic source'),
                'derivatives' => [] }
    @planned = { 'source' => source }
    @hashes = { source => @record['source_sha256'] }
    GroupRuntimeIntegrity::ROLES.each do |role, dir|
      path = "#{BANK}/#{dir}/#{id}-v1.webp"
      bytes = "synthetic #{role} bytes"
      write(path, bytes)
      sha = Digest::SHA256.hexdigest(bytes)
      @planned[role], @hashes[path] = path, sha
      @record['derivatives'] << { 'role' => role, 'path' => path, 'bytes' => bytes.bytesize,
                                 'sha256' => sha, 'width' => 32, 'height' => 48 }
    end
    total = @record['derivatives'].sum { |d| d['bytes'] }
    @runtime = { 'schema_version' => 1, 'concepts' => 1, 'total_bytes' => total, 'records' => [@record] }
    @catalog = { 'schema_version' => 1, 'planned_asset_count' => 1, 'generated_count' => 1,
                 'runtime_derivative_total_bytes' => total,
                 'assets' => [{ 'id' => id, 'version' => 1, 'planned_files' => @planned }] }
    save
  end
  def teardown
    FileUtils.remove_entry(@root)
  end
  def write(path, bytes)
    absolute = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.binwrite(absolute, bytes)
  end
  def save
    write(GroupRuntimeIntegrity::RUNTIME, JSON.generate(@runtime))
    write(GroupRuntimeIntegrity::CATALOG, JSON.generate(@catalog))
    write(AssetManifestIntegrity::DEFAULT_MANIFEST, @hashes.map { |p, h| "#{h}  #{p}\n" }.join)
  end
  def verify
    GroupRuntimeIntegrity.verify(root: @root)
  end
  def fails(reason)
    result = verify
    assert_equal 'fail', result['status'], result.inspect
    assert_equal reason, result['reason']
    assert_equal false, result['asset_mutations']
  end
  def test_valid_fixture_is_read_only_and_scoped
    before = Dir.glob("#{@root}/**/*").select { |p| File.file?(p) }.to_h { |p| [p, Digest::SHA256.file(p).hexdigest] }
    result = verify
    assert_equal 'pass', result['status']
    assert_equal 2, result['runtime_files_verified']
    assert_equal false, result['source_png_bytes_verified']
    assert_equal false, result['image_decode_performed']
    assert_equal false, result['visual_approval']
    assert_equal before, before.keys.to_h { |p| [p, Digest::SHA256.file(p).hexdigest] }
  end
  def test_stale_concept_count
    @runtime['concepts'] = 3; save; fails('runtime_concepts_mismatch')
  end
  def test_stale_total
    @runtime['total_bytes'] += 1; save; fails('runtime_total_bytes_mismatch')
  end
  %w[planned_asset_count generated_count].each do |field|
    define_method("test_catalog_#{field}") do
      @catalog[field] += 1; save; fails("catalog_#{field}_mismatch")
    end
  end
  def test_catalog_byte_total
    @catalog['runtime_derivative_total_bytes'] += 1; save; fails('catalog_total_bytes_mismatch')
  end
  def test_catalog_ids_differ
    @catalog['assets'][0]['id'] = 'rw-02-another-group'; save; fails('catalog_runtime_ids_mismatch')
  end
  def test_duplicate_runtime_id
    @runtime['records'] << @record.dup; save; fails('duplicate_record_id')
  end
  def test_duplicate_catalog_id
    @catalog['assets'] << @catalog['assets'][0].dup; save; fails('duplicate_record_id')
  end
  def test_version_mismatch
    @catalog['assets'][0]['version'] = 2; save; fails('catalog_runtime_version_mismatch')
  end
  def test_float_schema_not_integer
    @runtime['schema_version'] = 1.0; save; fails('unsupported_schema')
  end
  def test_bad_version
    @record['version'] = 0; save; fails('invalid_version')
  end
  def test_empty_records
    @runtime['records'] = []; save; fails('invalid_records')
  end
  def test_wrong_top_level_type
    write(GroupRuntimeIntegrity::RUNTIME, '[]'); fails('invalid_document')
  end
  def test_empty_json
    write(GroupRuntimeIntegrity::RUNTIME, ''); fails('invalid_json')
  end
  def test_duplicate_json_key
    write(GroupRuntimeIntegrity::RUNTIME, '{"schema_version":1,"schema_version":1}'); fails('duplicate_json_key')
  end
  def test_invalid_json_does_not_echo_content
    write(GroupRuntimeIntegrity::RUNTIME, '{"SENSITIVE_SENTINEL":'); fails('invalid_json')
    refute_includes JSON.generate(verify), 'SENSITIVE_SENTINEL'
  end
  def test_missing_role
    @record['derivatives'].pop; save; fails('invalid_derivatives')
  end
  def test_duplicate_role
    @record['derivatives'][1]['role'] = 'cover'; save; fails('derivative_roles_mismatch')
  end
  def test_non_string_role
    @record['derivatives'][1]['role'] = nil; save; fails('derivative_roles_mismatch')
  end
  def test_traversal_path
    @record['derivatives'][0]['path'] = '../../SENSITIVE_SENTINEL'; save
    fails('derivative_path_mismatch'); refute_includes JSON.generate(verify), 'SENSITIVE_SENTINEL'
  end
  def test_catalog_path_mismatch
    @planned['cover'] = 'assets/wrong.webp'; save; fails('derivative_path_mismatch')
  end
  def test_source_path_mismatch
    @record['source'] = 'assets/source/wrong.png'; save; fails('source_path_mismatch')
  end
  def test_unapproved_source_hash
    @record['source_sha256'] = '0' * 64; save; fails('source_approval_mismatch')
  end
  def test_unapproved_derivative_hash
    @record['derivatives'][0]['sha256'] = '0' * 64; save; fails('derivative_approval_mismatch')
  end
  %w[bytes width height].each do |field|
    define_method("test_invalid_#{field}") do
      @record['derivatives'][0][field] = 0; save; fails("invalid_#{field}")
    end
  end
  def test_changed_file_bytes_same_size
    d = @record['derivatives'][0]; write(d['path'], 'x' * d['bytes']); fails('asset_hash_mismatch')
  end
  def test_changed_file_size
    write(@record['derivatives'][0]['path'], 'different'); fails('asset_byte_size_mismatch')
  end
  def test_missing_asset
    File.unlink(File.join(@root, @record['derivatives'][0]['path'])); fails('runtime_directory_inventory_mismatch')
  end
  def test_unlisted_visual_asset
    write("#{BANK}/covers/other.webp", 'other'); fails('runtime_directory_inventory_mismatch')
  end
  def test_regular_nonvisual_metadata_is_ignored
    write("#{BANK}/covers/.DS_Store", 'metadata'); assert_equal 'pass', verify['status']
  end
  def test_nested_directory_blocks
    FileUtils.mkdir_p(File.join(@root, BANK, 'covers', 'nested')); fails('unexpected_nonregular_runtime_entry')
  end
  def test_symlink_asset_blocks
    path = File.join(@root, @record['derivatives'][0]['path']); File.rename(path, "#{path}.target")
    File.symlink("#{path}.target", path); fails('unexpected_nonregular_runtime_entry')
  end
  def test_symlink_directory_blocks
    path = File.join(@root, BANK, 'covers'); File.rename(path, "#{path}.target")
    File.symlink("#{path}.target", path); fails('unsafe_runtime_directory')
  end
  def test_symlink_json_blocks
    path = File.join(@root, GroupRuntimeIntegrity::CATALOG); File.rename(path, "#{path}.target")
    File.symlink("#{path}.target", path); fails('symlink_not_allowed')
  end
  def test_duplicate_approval
    path = File.join(@root, AssetManifestIntegrity::DEFAULT_MANIFEST)
    File.open(path, 'a') { |io| io.write(File.readlines(path).first) }; fails('duplicate_approval_path')
  end
  def test_unsafe_approval_path
    @hashes['../outside.png'] = 'a' * 64; save; fails('invalid_relative_path')
  end
  def test_empty_approval
    @hashes.clear; save; fails('empty_approval_manifest')
  end
  def test_oversized_metadata_blocks_before_parsing
    path = GroupRuntimeIntegrity::CATALOG
    write(path, ' ' * (GroupRuntimeIntegrity::MAX_JSON_BYTES + 1)); fails('file_too_large')
  end
  def test_cli_pass_and_failure_status
    script = File.expand_path('../qa/group_runtime_integrity.rb', __dir__)
    out, err, status = Open3.capture3('ruby', script, '--root', @root, '--json')
    assert status.success?, err
    assert_equal 'pass', JSON.parse(out)['status']
    @runtime['concepts'] = 44; save
    out, _, status = Open3.capture3('ruby', script, '--root', @root, '--json')
    assert_equal 1, status.exitstatus
    assert_equal 'runtime_concepts_mismatch', JSON.parse(out)['reason']
  end
  def test_cli_bad_arguments_blocks
    script = File.expand_path('../qa/group_runtime_integrity.rb', __dir__)
    out, _, status = Open3.capture3('ruby', script, '--unknown')
    assert_equal 2, status.exitstatus
    assert_equal 'invalid_arguments', JSON.parse(out)['reason']
  end
end
