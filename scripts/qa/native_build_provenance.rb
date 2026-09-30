#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'time'

# Records the source and native artifact hashes for the controlled build wrappers.
# This is provenance evidence only and grants no visual or release approval.
root = File.expand_path('../..', __dir__)
artifacts = {
  'android' => {
    'apk' => 'build/app/outputs/flutter-apk/app-production-release.apk',
    'aab' => 'build/app/outputs/bundle/productionRelease/app-production-release.aab'
  },
  'ios' => { 'ipa' => 'build/ios/ipa/Collect.ipa' }
}
patterns = %w[
  lib/app/**/*.dart lib/core/**/*.dart lib/features/**/*.dart lib/shared/**/*.dart
  lib/l10n/**/*.dart lib/main.dart lib/bootstrap.dart assets/**/* android/app/src/**/*
  android/app/build.gradle.kts ios/Runner/**/* pubspec.yaml pubspec.lock AGENTS.md
  integration_test/mobile_route_matrix_device_uat_test.dart
  integration_test/mobile_material_state_matrix_device_uat_test.dart
  test/fixtures/collect_repository_fixture.dart test/fixtures/mobile_matrix_capture.dart
  scripts/qa/*.rb scripts/android_play_store_build.sh scripts/ios_app_store_build.sh
]
source_paths = patterns.flat_map { |pattern| Dir.glob(File.join(root, pattern)) }
  .select { |path| File.file?(path) }
  .map { |path| path.delete_prefix("#{root}/") }
  .reject { |path| path.include?('/GeneratedPluginRegistrant.') }
  .uniq.sort
abort 'Native source inventory is empty' unless source_paths.include?('lib/main.dart')
source_digest = Digest::SHA256.hexdigest(source_paths.map do |path|
  "#{path}\0#{Digest::SHA256.file(File.join(root, path)).hexdigest}\n"
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
    'schema_version' => 1, 'platform' => platform, 'source_sha256' => source_before,
    'version' => version, 'built_at' => Time.now.utc.iso8601,
    'release_approval' => false, 'artifacts' => hashes
  ) + "\n")
  puts "[native-build] #{platform} provenance recorded; release approval not granted"
else
  abort 'Usage: native_build_provenance.rb begin PLATFORM | finish PLATFORM SOURCE VERSION START_EPOCH'
end
