# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module CollectPublicSite
  def public_build_destination_mode(destination, source_root:, allowed_roots:, explicit_path:)
    internal = allowed_roots.any? { |root| destination.start_with?(root + File::SEPARATOR) }
    if !internal && (destination == source_root || destination.start_with?(source_root + File::SEPARATOR))
      raise ArgumentError, "Repository PUBLIC_BUILD_DIR must be inside build or .cache"
    end
    unless internal || (explicit_path && explicit_path.start_with?(File::SEPARATOR) &&
                        explicit_path == destination && explicit_path == File.expand_path(explicit_path))
      raise ArgumentError, "External PUBLIC_BUILD_DIR must be an explicit absolute path"
    end

    cursor = File::SEPARATOR
    destination.split(File::SEPARATOR).reject(&:empty?).each do |part|
      cursor = File.join(cursor, part)
      raise ArgumentError, "PUBLIC_BUILD_DIR contains a symlink" if File.symlink?(cursor)
      if File.exist?(cursor) && !File.directory?(cursor)
        raise ArgumentError, "PUBLIC_BUILD_DIR contains a non-directory"
      end
    end
    return :replace_internal if internal

    if File.exist?(destination)
      raise ArgumentError, "External PUBLIC_BUILD_DIR already exists; choose a new release directory"
    end
    unless File.directory?(File.dirname(destination))
      raise ArgumentError, "External PUBLIC_BUILD_DIR requires an existing parent directory"
    end
    :create_external
  end

  def publish_public_build(destination, **destination_rules)
    mode = public_build_destination_mode(destination, **destination_rules)
    parent = File.dirname(destination)
    FileUtils.mkdir_p(parent) if mode == :replace_internal
    public_build_destination_mode(destination, **destination_rules)

    staging = Dir.mktmpdir(".collect-public-", parent)
    candidate = File.join(staging, "site")
    previous = File.join(staging, "previous")
    begin
      Dir.mkdir(candidate)
      yield candidate

      # Builders can render concurrently. Serialize the short publication step
      # without leaving a lock file in the output tree.
      File.open(parent, File::RDONLY) do |lock|
        raise IOError, "Could not lock public build directory" unless lock.flock(File::LOCK_EX)

        public_build_destination_mode(destination, **destination_rules)
        promote_public_build(candidate, destination, previous, mode)
      end
    ensure
      # Keep the previous build only if restoring it also failed.
      FileUtils.remove_entry(staging) unless Dir.exist?(previous) && Dir.exist?(candidate)
    end
  end

  private

  def promote_public_build(candidate, destination, previous, mode)
    if mode == :create_external
      Dir.mkdir(destination)
      begin
        File.rename(candidate, destination)
      ensure
        Dir.rmdir(destination) if Dir.exist?(candidate)
      end
    elsif Dir.exist?(destination)
      File.rename(destination, previous)
      begin
        File.rename(candidate, destination)
      ensure
        if Dir.exist?(candidate)
          if File.exist?(destination) || File.symlink?(destination)
            raise IOError, "The previous public build is available at #{previous}"
          end
          File.rename(previous, destination)
        end
      end
    else
      File.rename(candidate, destination)
    end
  end
end
