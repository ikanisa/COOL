#!/usr/bin/env ruby
# Real tiny ZIP extraction regressions; no signing, stores or provider requests.
require 'digest'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'zip'

expected_version = ENV.fetch('COLLECT_RUBYZIP_EXPECTED_VERSION', '3.4.0')
raise 'Unsupported test version' unless %w[3.4.0 2.4.1].include?(expected_version)
raise 'Unexpected rubyzip version' unless Gem.loaded_specs.fetch('rubyzip').version.to_s == expected_version

cases = []
Dir.mktmpdir('collect-rubyzip-security-') do |temporary|
  destination = File.join(temporary, 'upload')
  FileUtils.mkdir_p(destination)
  # Existing sibling upload directories expose the affected prefix check.
  %w[upload_backup upload2].each { |name| FileUtils.mkdir_p(File.join(temporary, name)) }
  entries = {
    'inside.txt' => 'Collect synthetic benign payload',
    '../upload_backup/owned.txt' => 'Collect synthetic forbidden payload',
    '../upload2/owned.txt' => 'Collect synthetic forbidden payload'
  }
  archive = File.join(temporary, 'tiny.zip')
  Zip::OutputStream.open(archive) do |stream|
    entries.each do |name, payload|
      stream.put_next_entry(name)
      stream.write(payload)
    end
  end
  raise 'Security fixture grew unexpectedly' unless File.size(archive) < 4096
  archive_sha256 = Digest::SHA256.file(archive).hexdigest
  Zip::File.open(archive) do |zip|
    zip.each do |entry|
      if expected_version == '2.4.1'
        # Compare its real optional V3 bridge, not the distinct legacy API.
        entry.extract_v3(destination_directory: destination)
      else
        entry.extract(destination_directory: destination)
      end
    end
  end
  benign = File.join(destination, 'inside.txt')
  raise 'Benign ZIP extraction changed' unless File.binread(benign) == entries.fetch('inside.txt')
  cases << { id: 'benign-default-extraction', passed: true }
  %w[upload_backup upload2].each do |name|
    escaped = File.join(temporary, name, 'owned.txt')
    cases << { id: "sibling-prefix-#{name}-denied", passed: !File.exist?(escaped) }
  end
  raise 'ZIP entry names changed while parsing' unless Zip::File.open(archive, &:entries).map(&:name).sort == entries.keys.sort
  raise 'ZIP bytes changed while parsing' unless Digest::SHA256.file(archive).hexdigest == archive_sha256
end
passed = cases.all? { |item| item.fetch(:passed) }
puts JSON.generate(status: passed ? 'pass' : 'fail', ruby_version: RUBY_VERSION, rubyzip_version: expected_version,
                   api: expected_version == '2.4.1' ? 'extract_v3' : 'extract',
                   cases: cases, provider_calls: 0, real_customer_data: false)
raise 'Sibling prefix ZIP traversal permitted' unless passed
