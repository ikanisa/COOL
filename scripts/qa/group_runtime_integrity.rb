# frozen_string_literal: true
require 'json'
require 'optparse'
require_relative 'asset_manifest_integrity'

# Scoped consistency evidence only. No writes, network calls or visual approval.
module GroupRuntimeIntegrity
  BANK = 'assets/group_covers/rwanda'
  CATALOG = "#{BANK}/catalog.v1.json"
  RUNTIME = "#{BANK}/runtime-manifest.json"
  MAX_JSON_BYTES = 2 * 1024 * 1024
  MAX_ASSET_BYTES = 64 * 1024 * 1024
  ID = /\Arw-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*\z/
  SHA = /\A[0-9a-f]{64}\z/
  ROLES = { 'cover' => 'covers', 'thumbnail' => 'thumbs' }.freeze
  class InvalidData < StandardError; end
  class UniqueObject < Hash
    def []=(key, value)
      raise InvalidData, 'duplicate_json_key' if key?(key)
      super
    end
  end
  module_function
  def check(value, code)
    raise InvalidData, code unless value
  end
  def json_file(root, path)
    text = AssetManifestIntegrity.read_regular(root, path, max_bytes: MAX_JSON_BYTES) { |io| io.read(MAX_JSON_BYTES + 1) || +'' }
    check(text.bytesize <= MAX_JSON_BYTES, 'json_too_large')
    text.force_encoding(Encoding::UTF_8)
    check(text.valid_encoding?, 'invalid_json_encoding')
    JSON.parse(text, create_additions: false, allow_nan: false,
               max_nesting: 64, object_class: UniqueObject)
  rescue JSON::ParserError
    raise InvalidData, 'invalid_json'
  end
  def approved_hashes(root)
    max = AssetManifestIntegrity::MAX_MANIFEST_BYTES
    text = AssetManifestIntegrity.read_regular(root, AssetManifestIntegrity::DEFAULT_MANIFEST,
                                               max_bytes: max) { |io| io.read(max + 1) || +'' }
    check(text.bytesize <= max, 'approval_too_large')
    text.force_encoding(Encoding::UTF_8)
    check(text.valid_encoding?, 'invalid_approval_encoding')
    text.each_line.each_with_object({}) do |raw, hashes|
      line = raw.chomp
      next if line.empty?
      match = /\A([0-9a-f]{64})  (.+)\z/.match(line)
      check(match, 'invalid_approval_entry')
      hash, path = match.captures
      AssetManifestIntegrity.validate_asset!(path)
      check(!hashes.key?(path), 'duplicate_approval_path')
      hashes[path] = hash
    end
  end
  def index_records(records)
    check(records.is_a?(Array) && !records.empty? && records.length <= 2000, 'invalid_records')
    records.each_with_object({}) do |record, index|
      check(record.is_a?(Hash), 'invalid_record')
      id = record['id']
      check(id.is_a?(String) && ID.match?(id), 'invalid_record_id')
      check(!index.key?(id), 'duplicate_record_id')
      check(record['version'].is_a?(Integer) && record['version'].positive?, 'invalid_version')
      index[id] = record
    end
  end
  def observed_runtime_paths(root)
    ROLES.values.flat_map do |directory|
      relative = "#{BANK}/#{directory}"
      absolute = File.realpath(root)
      relative.split('/').each do |component|
        absolute = File.join(absolute, component)
        stat = File.lstat(absolute)
        check(!stat.symlink? && stat.directory?, 'unsafe_runtime_directory')
      end
      Dir.children(absolute).sort.map do |name|
        path = "#{relative}/#{name}"
        AssetManifestIntegrity.validate_relative!(path)
        stat = File.lstat(File.join(absolute, name))
        check(stat.file? && !stat.symlink?, 'unexpected_nonregular_runtime_entry')
        path if (AssetManifestIntegrity::VISUAL_EXTENSIONS + %w[.gif .avif]).include?(File.extname(name).downcase)
      end.compact
    end.sort
  end
  def verify(root:)
    runtime, catalog = json_file(root, RUNTIME), json_file(root, CATALOG)
    check(runtime.is_a?(Hash) && catalog.is_a?(Hash), 'invalid_document')
    check([runtime, catalog].all? { |d| d['schema_version'].is_a?(Integer) && d['schema_version'] == 1 }, 'unsupported_schema')
    records, concepts = index_records(runtime['records']), index_records(catalog['assets'])
    check(records.keys.sort == concepts.keys.sort, 'catalog_runtime_ids_mismatch')
    check(runtime['concepts'].is_a?(Integer) && runtime['concepts'] == records.length, 'runtime_concepts_mismatch')
    %w[planned_asset_count generated_count].each do |field|
      check(catalog[field].is_a?(Integer) && catalog[field] == concepts.length, "catalog_#{field}_mismatch")
    end
    approvals = approved_hashes(root)
    check(!approvals.empty?, 'empty_approval_manifest')
    entries = []
    records.each do |id, record|
      concept = concepts.fetch(id)
      check(record['version'] == concept['version'], 'catalog_runtime_version_mismatch')
      files = concept['planned_files']
      check(files.is_a?(Hash), 'missing_catalog_paths')
      source = "#{BANK}/source/#{id}-v#{record['version']}.png"
      check(record['source'] == source && files['source'] == source, 'source_path_mismatch')
      source_hash = record['source_sha256']
      check(source_hash.is_a?(String) && SHA.match?(source_hash) && approvals[source] == source_hash, 'source_approval_mismatch')
      derivatives = record['derivatives']
      check(derivatives.is_a?(Array) && derivatives.length == ROLES.length && derivatives.all? { |d| d.is_a?(Hash) }, 'invalid_derivatives')
      check(derivatives.map { |d| d['role'] }.sort_by(&:to_s) == ROLES.keys.sort, 'derivative_roles_mismatch')
      derivatives.each do |entry|
        role = entry['role']
        path = "#{BANK}/#{ROLES.fetch(role)}/#{id}-v#{record['version']}.webp"
        check(entry['path'] == path && files[role] == path, 'derivative_path_mismatch')
        check(entry['sha256'].is_a?(String) && SHA.match?(entry['sha256']) && approvals[path] == entry['sha256'], 'derivative_approval_mismatch')
        %w[bytes width height].each do |field|
          check(entry[field].is_a?(Integer) && entry[field].positive?, "invalid_#{field}")
        end
        check(entry['bytes'] <= MAX_ASSET_BYTES, 'asset_too_large')
        entries << entry
      end
    end
    total = entries.sum { |entry| entry['bytes'] }
    check(runtime['total_bytes'].is_a?(Integer) && runtime['total_bytes'] == total, 'runtime_total_bytes_mismatch')
    check(catalog['runtime_derivative_total_bytes'].is_a?(Integer) && catalog['runtime_derivative_total_bytes'] == total, 'catalog_total_bytes_mismatch')
    check(observed_runtime_paths(root) == entries.map { |entry| entry['path'] }.sort, 'runtime_directory_inventory_mismatch')
    entries.each do |entry|
      actual_hash, actual_bytes = AssetManifestIntegrity.read_regular(root, entry['path'], max_bytes: MAX_ASSET_BYTES) do |io|
        digest, size = Digest::SHA256.new, 0
        while (block = io.read(64 * 1024))
          size += block.bytesize
          check(size <= MAX_ASSET_BYTES, 'asset_too_large')
          digest.update(block)
        end
        [digest.hexdigest, size]
      end
      check(actual_bytes == entry['bytes'], 'asset_byte_size_mismatch')
      check(actual_hash == entry['sha256'], 'asset_hash_mismatch')
    end
    {
      'status' => 'pass', 'concepts' => records.length, 'runtime_files_verified' => entries.length,
      'runtime_bytes_verified' => total, 'source_approval_references_checked' => records.length,
      'source_png_bytes_verified' => false, 'image_decode_performed' => false,
      'dimensions_checked' => 'positive metadata values only; use image decoder separately',
      'scope' => 'Rwanda group-cover runtime files, catalog and approval references only',
      'asset_mutations' => false, 'visual_approval' => false
    }
  rescue InvalidData, AssetManifestIntegrity::InvalidPath => e
    { 'status' => 'fail', 'reason' => e.message, 'asset_mutations' => false, 'visual_approval' => false }
  rescue SystemCallError, IOError
    { 'status' => 'blocked', 'reason' => 'unreadable_input', 'asset_mutations' => false }
  end
  def main(argv)
    options = { root: Dir.pwd, json: false }
    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: ruby group_runtime_integrity.rb [--root CHECKOUT] [--json]'
      opts.on('--root PATH') { |value| options[:root] = value }
      opts.on('--json') { options[:json] = true }
    end
    parser.parse!(argv)
    raise OptionParser::InvalidArgument unless argv.empty?
    result = verify(root: options[:root])
    puts(options[:json] ? JSON.pretty_generate(result) : "[group-runtime-integrity] #{result['status']} #{result['reason']}")
    { 'pass' => 0, 'fail' => 1, 'blocked' => 2 }.fetch(result['status'])
  rescue OptionParser::ParseError
    puts JSON.generate('status' => 'blocked', 'reason' => 'invalid_arguments', 'asset_mutations' => false)
    2
  end
end
exit GroupRuntimeIntegrity.main(ARGV) if $PROGRAM_NAME == __FILE__
