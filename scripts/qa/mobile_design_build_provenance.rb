#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require_relative 'mobile_design_gate'

# Called only around the controlled build wrappers. This records build identity,
# never visual approval, and rejects old outputs or source edits during a build.
root = File.expand_path('../..', __dir__)
gate = MobileDesignGate.new(root)
mode, platform, source_before, version, started_epoch = ARGV
abort 'Unknown build platform' unless MobileDesignGate::ARTIFACTS.key?(platform)
if mode == 'begin' && ARGV.length == 2
  puts gate.source_digest
elsif mode == 'finish' && ARGV.length == 5
  abort 'Source changed during native build; rebuild required' unless source_before == gate.source_digest
  abort 'Build version differs from pubspec.yaml' unless version == gate.fingerprints['version']
  started_at = Time.at(Integer(started_epoch))
  abort 'Invalid build start time' if started_at > Time.now
  artifacts = MobileDesignGate::ARTIFACTS.fetch(platform).transform_values do |path|
    file = gate.artifact_file(path) || abort("Missing native artifact: #{path}")
    abort "Artifact predates this build: #{path}" if File.mtime(file) < started_at
    abort "Artifact is unexpectedly small: #{path}" if File.size(file) < 1_000_000
    gate.artifact_digest(path)
  end
  directory = File.join(root, '.cache/mobile-design-build')
  FileUtils.mkdir_p(directory)
  File.write(File.join(directory, "#{platform}.json"), JSON.pretty_generate(
    'schema_version' => 1, 'platform' => platform, 'source_sha256' => source_before,
    'version' => version, 'built_at' => Time.now.utc.iso8601,
    'evidence_mode' => false, 'artifacts' => artifacts
  ) + "\n")
  puts "[mobile-design-build] #{platform} provenance recorded; design approval NOT granted"
else
  abort 'Usage: mobile_design_build_provenance.rb begin PLATFORM | finish PLATFORM SOURCE VERSION START_EPOCH'
end
