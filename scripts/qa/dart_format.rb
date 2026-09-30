# frozen_string_literal: true

require 'open3'
require 'digest'
require 'json'

abort 'Usage: dart_format.rb --check|--write' unless ARGV.length == 1 && %w[--check --write].include?(ARGV.first)
root = File.expand_path('../..', __dir__)
Dir.chdir(root)
inventory, error, status = Open3.capture3('git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', '*.dart')
abort "Dart source inventory failed: #{error.lines.first}" unless status.success?
files = inventory.split("\0").uniq.sort.select { |path| File.file?(path) }
# These partial dated snapshots must remain byte-identical source evidence.
# Runtime, tests, tools and modified vendored source remain in the inventory.
files.reject! { |path| path.start_with?('docs/release/') }
# Preserve hash-identical upstream files; Collect's fork changes are checked.
manifest = 'third_party/gotrue/UPSTREAM-SHA256.json'
if File.file?(manifest)
  upstream = JSON.parse(File.read(manifest))
  files.reject! do |path|
    next false unless path.start_with?('third_party/gotrue/')

    original = upstream[path.delete_prefix('third_party/gotrue/')]
    original && Digest::SHA256.file(path).hexdigest == original
  end
end
abort 'No repository Dart sources found' if files.empty?
outside = files.reject { |path| File.realpath(path).start_with?(root + File::SEPARATOR) }
abort 'Dart source inventory points outside the workspace' unless outside.empty?
arguments = ['format']
arguments += %w[--output=none --set-exit-if-changed] if ARGV.first == '--check'
exec(ENV.fetch('DART', 'dart'), *arguments, *files)
