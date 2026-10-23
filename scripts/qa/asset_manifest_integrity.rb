# frozen_string_literal: true

require 'digest'
require 'json'
require 'open3'
require 'optparse'

# Integrity evidence only. Design choices remain governed by revolut-design.
# Never regenerates a baseline or writes/deletes an asset. Use a quiescent checkout;
# this is not a sandbox against another process changing parent directories.
module AssetManifestIntegrity
  ASSET_ROOTS = %w[assets android/app/src/main/res ios/Runner/Assets.xcassets web].freeze
  VISUAL_EXTENSIONS = %w[.png .jpg .jpeg .webp .svg .svgz .ico].freeze
  DEFAULT_MANIFEST = 'assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256'
  MAX_MANIFEST_BYTES = 8 * 1024 * 1024

  class InvalidPath < StandardError; end
  class IncompleteInventory < StandardError; end

  module_function

  # Validate before expansion: expanding first would erase '..' evidence.
  def validate_relative!(path)
    unless path.is_a?(String) && path.valid_encoding? && !path.empty?
      raise InvalidPath, 'invalid_relative_path'
    end
    if path.start_with?('/') || path.match?(/\A[A-Za-z]:/) ||
       path.include?('\\') || path.match?(/[[:cntrl:]]/)
      raise InvalidPath, 'invalid_relative_path'
    end
    if path.split('/', -1).any? { |part| part.empty? || %w[. ..].include?(part) }
      raise InvalidPath, 'invalid_relative_path'
    end
    path
  end

  def validate_asset!(path)
    validate_relative!(path)
    unless ASSET_ROOTS.any? { |root| path.start_with?("#{root}/") }
      raise InvalidPath, 'outside_asset_roots'
    end
    unless VISUAL_EXTENSIONS.include?(File.extname(path).downcase)
      raise InvalidPath, 'not_visual_asset'
    end
    path
  end

  # lstat checks the link itself instead of following its target. Check every
  # component, not only the leaf. Reject sockets, FIFOs, devices and directories.
  def regular_path!(root, relative)
    validate_relative!(relative)
    current = File.realpath(root)
    parts = relative.split('/')
    parts.each_with_index do |part, index|
      current = File.join(current, part)
      stat = File.lstat(current)
      raise InvalidPath, 'symlink_not_allowed' if stat.symlink?
      expected = index == parts.length - 1 ? stat.file? : stat.directory?
      raise InvalidPath, 'not_regular_file_path' unless expected
    end
    current
  rescue Errno::ENOENT, Errno::ENOTDIR
    raise InvalidPath, 'missing_file'
  end

  # Open only after checking each component and refuse a leaf symlink at open.
  # A before/after stat catches ordinary file changes while reading. Parent-path
  # races still require a trusted checkout with other writers stopped.
  def read_regular(root, relative, max_bytes: nil)
    path = regular_path!(root, relative)
    flags = File::RDONLY
    flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
    File.open(path, flags) do |io|
      io.binmode
      before = io.stat
      raise InvalidPath, 'not_regular_file_path' unless before.file?
      raise InvalidPath, 'file_too_large' if max_bytes && before.size > max_bytes
      result = yield(io)
      after = io.stat
      signature = ->(s) { [s.dev, s.ino, s.size, s.mtime, s.ctime] }
      unless signature.call(before) == signature.call(after) &&
             signature.call(after) == signature.call(File.lstat(regular_path!(root, relative)))
        raise InvalidPath, 'file_changed_during_read'
      end
      result
    end
  rescue Errno::ENOENT, Errno::ENOTDIR
    raise InvalidPath, 'missing_file'
  rescue Errno::ELOOP
    raise InvalidPath, 'symlink_not_allowed'
  rescue Errno::EACCES, Errno::EPERM, IOError
    raise InvalidPath, 'unreadable_file'
  end

  def sha256(root, relative)
    read_regular(root, relative) do |io|
      digest = Digest::SHA256.new
      buffer = +''
      digest.update(buffer) while io.read(64 * 1024, buffer)
      digest.hexdigest
    end
  end

  def verify(root:, manifest: DEFAULT_MANIFEST, observed_paths:)
    errors = []
    approved = {}
    observed = []
    begin
      text = read_regular(root, manifest, max_bytes: MAX_MANIFEST_BYTES) { |io| io.read(MAX_MANIFEST_BYTES + 1) }
      raise InvalidPath, 'file_too_large' if text.bytesize > MAX_MANIFEST_BYTES
      text.force_encoding(Encoding::UTF_8)
      raise InvalidPath, 'invalid_manifest_encoding' unless text.valid_encoding?
      text.each_line.with_index(1) do |raw, line_number|
        line = raw.chomp
        next if line.empty?
        match = line.match(/\A([0-9a-f]{64})  (.+)\z/)
        unless match
          errors << { 'line' => line_number, 'reason' => 'invalid_manifest_entry' }
          next
        end
        digest, relative = match.captures
        begin
          validate_asset!(relative)
          raise InvalidPath, 'duplicate_asset_path' if approved.key?(relative)
          approved[relative] = digest
        rescue InvalidPath => e
          # Do not echo untrusted lines, credentials or unsafe path content.
          errors << { 'line' => line_number, 'reason' => e.message }
        end
      end
      errors << { 'reason' => 'empty_manifest' } if approved.empty?
    rescue InvalidPath => e
      errors << { 'reason' => e.message }
    end

    Array(observed_paths).uniq.sort.each do |relative|
      next unless VISUAL_EXTENSIONS.include?(File.extname(relative).downcase)
      begin
        validate_asset!(relative)
        observed << relative
      rescue InvalidPath => e
        errors << { 'reason' => "observed_#{e.message}" }
      end
    end
    missing = approved.keys - observed
    unexpected = observed - approved.keys
    mismatches = []
    # Validate every observed asset, even if it is not in the manifest. Unsafe
    # observed assets must not be silently excluded from the inventory.
    observed.each do |relative|
      begin
        regular_path!(root, relative)
      rescue InvalidPath => e
        errors << { 'path' => relative, 'reason' => e.message }
      end
    end
    approved.each do |relative, expected|
      begin
        actual = sha256(root, relative)
        if actual != expected
          mismatches << { 'path' => relative, 'expected_sha256' => expected,
                          'actual_sha256' => actual }
        end
      rescue InvalidPath => e
        errors << { 'path' => relative, 'reason' => e.message }
      end
    end
    errors.uniq!
    passed = errors.empty? && missing.empty? && unexpected.empty? && mismatches.empty?
    {
      'status' => passed ? 'pass' : 'fail', 'manifest' => manifest,
      'approved_count' => approved.length, 'observed_count' => observed.length,
      'missing' => missing.sort, 'unexpected' => unexpected.sort,
      'hash_mismatches' => mismatches, 'manifest_errors' => errors,
      'scope' => 'supplied observed asset inventory; integrity only',
      'asset_mutations' => false
    }
  end

  def git_asset_paths(root)
    expected_root = File.realpath(root)
    top, _, status = Open3.capture3('git', 'rev-parse', '--show-toplevel', chdir: expected_root)
    unless status.success? && File.realpath(top.strip) == expected_root
      raise IncompleteInventory, 'root_is_not_git_checkout'
    end
    output, _, status = Open3.capture3(
      'git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard',
      '--', *ASSET_ROOTS, chdir: expected_root
    )
    raise IncompleteInventory, 'git_inventory_failed' unless status.success?
    # Return the full index separately from the current artifact inventory.
    # A removed, unapproved indexed file is a Git deletion, not an unexpected
    # asset in the build. Approved missing files still fail verify(): each
    # approved path is independently opened and hashed, including absent ones.
    output.split("\0").reject(&:empty?).uniq.sort
  rescue Errno::ENOENT, Errno::ENOTDIR
    raise IncompleteInventory, 'git_or_root_unavailable'
  end

  def main(argv)
    options = { root: Dir.pwd, json: false }
    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: ruby asset_manifest_integrity.rb [--root CHECKOUT] [--json]'
      opts.on('--root PATH') { |value| options[:root] = value }
      opts.on('--json') { options[:json] = true }
    end
    parser.parse!(argv)
    raise OptionParser::InvalidArgument, 'unexpected argument' unless argv.empty?
    indexed = git_asset_paths(options[:root])
    observed, absent = indexed.partition do |relative|
      absolute = File.join(options[:root], relative)
      File.exist?(absolute) || File.symlink?(absolute)
    end
    result = verify(root: options[:root], observed_paths: observed)
    result['indexed_absent_visual_paths'] = absent.select do |relative|
      VISUAL_EXTENSIONS.include?(File.extname(relative).downcase)
    end
    result['scope'] = 'Current Git tracked and non-ignored untracked visual assets, with absent indexed paths reported separately; no Git history or submodule traversal'
    puts(options[:json] ? JSON.pretty_generate(result) : "[asset-manifest-integrity] #{result['status']}")
    result['status'] == 'pass' ? 0 : 1
  rescue IncompleteInventory, InvalidPath, OptionParser::ParseError, SystemCallError => e
    # Never dump provider output or full exception details into a CI log.
    reason = e.is_a?(IncompleteInventory) || e.is_a?(InvalidPath) ? e.message : 'invalid_input_or_environment'
    puts JSON.generate('status' => 'blocked', 'reason' => reason, 'asset_mutations' => false)
    2
  end
end

exit AssetManifestIntegrity.main(ARGV) if $PROGRAM_NAME == __FILE__
