# frozen_string_literal: true

require 'open3'

abort 'Usage: dart_format.rb --check|--write' unless ARGV.length == 1 && %w[--check --write].include?(ARGV.first)
root = File.expand_path('../..', __dir__)
Dir.chdir(root)
inventory, error, status = Open3.capture3('git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', '*.dart')
abort "Dart source inventory failed: #{error.lines.first}" unless status.success?
files = inventory.split("\0").uniq.sort.select { |path| File.file?(path) }
abort 'No repository Dart sources found' if files.empty?
outside = files.reject { |path| File.realpath(path).start_with?(root + File::SEPARATOR) }
abort 'Dart source inventory points outside the workspace' unless outside.empty?
arguments = ['format']
arguments += %w[--output=none --set-exit-if-changed] if ARGV.first == '--check'
exec(ENV.fetch('DART', 'dart'), *arguments, *files)
