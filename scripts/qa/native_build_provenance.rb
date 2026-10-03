#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'time'

# Records the source and native artifact hashes for the controlled build wrappers.
# This is provenance evidence only and grants no visual or release approval.
root = File.realpath(File.expand_path('../..', __dir__))
artifacts = {
  'android' => {
    'apk' => 'build/app/outputs/flutter-apk/app-production-release.apk',
    'aab' => 'build/app/outputs/bundle/productionRelease/app-production-release.aab'
  },
  'ios' => { 'ipa' => 'build/ios/ipa/Collect.ipa' }
}
source_roots = %w[lib/ assets/ licenses/ android/ ios/ third_party/ integration_test/ test/fixtures/ tool/]
source_files = %w[
  pubspec.yaml pubspec.lock analysis_options.yaml .metadata .fvmrc .dvmrc AGENTS.md
  scripts/qa/native_build_provenance.rb scripts/qa/native_source_export.py
  scripts/android_play_store_build.sh scripts/android_release_signing_preflight.sh
  scripts/ios_app_store_build.sh
]
# Use the actual public checkout inventory rather than a hand-picked application
# list: Admin code, vendored runtime/native code, licenses and native lockfiles
# all participate in the compiled artifact. Ignored keys and generated caches
# are not source inputs and must not enter this public provenance packet.
listed, error, status = Open3.capture3('git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z', chdir: root)
abort 'Cannot enumerate native checkout sources' unless status.success?
private_names = %w[key.properties google-services.json GoogleService-Info.plist local.properties Generated.xcconfig flutter_export_environment.sh]
source_paths = listed.split("\0").select do |path|
  next false unless source_files.include?(path) || source_roots.any? { |prefix| path.start_with?(prefix) }
  next false if private_names.include?(File.basename(path)) || File.basename(path).start_with?('.env')
  next false if path.match?(%r{\.(?:jks|keystore|p12|pfx|p8|pem|key|mobileprovision)\z}i)
  next false if path.include?('/GeneratedPluginRegistrant.')
  absolute = File.join(root, path)
  next false unless File.exist?(absolute)
  # Resolve every path segment, so an indexed directory link cannot silently
  # import source bytes from outside this checkout.
  resolved = File.realpath(absolute)
  abort "Native source escapes checkout: #{path}" unless resolved.start_with?(root + File::SEPARATOR)
  abort "Native source is not a regular file: #{path}" unless File.file?(absolute) && !File.symlink?(absolute)
  true
end.uniq.sort
abort 'Native source inventory is empty' unless source_paths.include?('lib/main.dart')
source_hashes = source_paths.to_h { |path| [path, Digest::SHA256.file(File.join(root, path)).hexdigest] }
source_digest = Digest::SHA256.hexdigest(source_hashes.map do |path, digest|
  "#{path}\0#{digest}\n"
end.join)
mode, platform, source_before, version, started_epoch = ARGV
abort 'Unknown build platform' unless artifacts.key?(platform)
case [mode, ARGV.length]
when ['begin', 2]
  puts source_digest
when ['finish', 5]
  abort 'Source changed during native build; rebuild required' unless source_before == source_digest
  current_version = File.read(File.join(root, 'pubspec.yaml'))[/^version:\s*(\S+)/, 1]
  abort 'Build version differs from pubspec.yaml' unless version == current_version
  started_at = Time.at(Integer(started_epoch))
  abort 'Invalid build start time' if started_at > Time.now
  hashes = artifacts.fetch(platform).transform_values do |path|
    file = File.join(root, path)
    abort "Missing native artifact: #{path}" unless File.file?(file) && !File.symlink?(file)
    abort "Artifact predates this build: #{path}" if File.mtime(file) < started_at
    abort "Artifact is unexpectedly small: #{path}" if File.size(file) < 1_000_000
    Digest::SHA256.file(file).hexdigest
  end
  directory = File.join(root, '.cache/native-build')
  FileUtils.mkdir_p(directory)
  File.write(File.join(directory, "#{platform}.json"), JSON.pretty_generate(
    'schema_version' => 2, 'platform' => platform, 'source_sha256' => source_before,
    'source_file_count' => source_hashes.length, 'source_files' => source_hashes,
    'source_scope' => 'Declared public checkout native build inputs and all local forks; ignored private signing/provider inputs and complete installed SDK are separate evidence',
    'version' => version, 'built_at' => Time.now.utc.iso8601,
    'release_approval' => false, 'artifacts' => hashes
  ) + "\n")
  puts "[native-build] #{platform} provenance recorded; release approval not granted"
else
  abort 'Usage: native_build_provenance.rb begin PLATFORM | finish PLATFORM SOURCE VERSION START_EPOCH'
end
