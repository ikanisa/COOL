#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require_relative 'product_capabilities'

module CollectCapabilityContentGenerator
  ROOT = File.expand_path('..', __dir__)
  DART_PAGES = 'lib/features/landing/public_marketing_page_content.dart'
  DART_CAPABILITIES = 'lib/features/landing/public_capability_content.dart'

  def self.string(value)
    encoded = JSON.generate(value).gsub('$', '\\$')
    return encoded if value.include?("'")
    "'" + encoded[1...-1].gsub('\\"', '"') + "'"
  end

  def self.format_dart(source)
    result, error, status = Open3.capture3(ENV.fetch('DART', 'dart'), 'format', '--output=show', '--summary=none', stdin_data: source)
    raise "Dart formatter failed: #{error}" unless status.success? && !result.empty?
    result
  end

  def self.header(registry)
    "// Generated from #{CollectProductCapabilities::SOURCE}.\n// Registry SHA-256: #{registry.sha256}\n// Source observations only; no publication or provider approval.\npart of 'public_content.dart';\n\n"
  end

  def self.outputs(registry)
    pages = header(registry) + "const _publicMarketingPages = <CollectPublicPageData>[\n"
    registry.data.fetch('flutter_pages').each do |page|
      pages += "  CollectPublicPageData(\n"
      %w[path navLabel title intro].each { |key| pages += "    #{key}: #{string(page.fetch(key))},\n" }
      pages += "    sections: [\n"
      page.fetch('sections').each do |section|
        pages += "      CollectPublicSectionData(\n"
        %w[title body].each { |key| pages += "        #{key}: #{string(section.fetch(key))},\n" }
        pages += "        bullets: [\n"
        section.fetch('bullets').each { |bullet| pages += "          #{string(bullet)},\n" }
        pages += "        ],\n      ),\n"
      end
      pages += "    ],\n  ),\n"
    end
    pages += "];\n"
    capabilities = header(registry) + "const collectPublicCapabilityRegistrySha256 = '#{registry.sha256}';\n"
    capabilities += "const collectPublicHomeCopy = <String, String>{\n"
    registry.data.fetch('flutter_home').each { |key, value| capabilities += "  #{string(key)}: #{string(value)},\n" }
    capabilities += "};\n\nconst collectPublicCapabilities = <String, CollectPublicCapabilityData>{\n"
    registry.data.fetch('capabilities').each do |row|
      capabilities += "  #{string(row.fetch('id'))}: CollectPublicCapabilityData(\n"
      %w[label summary].each { |key| capabilities += "    #{key}: #{string(row.fetch(key))},\n" }
      capabilities += "    region: #{string(registry.data.fetch('region'))},\n    ownerApproved: false,\n    availability: {\n"
      row.fetch('availability').each { |key, value| capabilities += "      #{string(key)}: #{string(value)},\n" }
      capabilities += "    },\n    actionLabel: #{string(row.dig('implemented_action', 'label'))},\n    actionHref: #{string(row.dig('implemented_action', 'href'))},\n    fallbackLabel: #{string(row.dig('fallback_action', 'label'))},\n    fallbackHref: #{string(row.dig('fallback_action', 'href'))},\n  ),\n"
    end
    capabilities += "};\n"
    result = { DART_PAGES => format_dart(pages), DART_CAPABILITIES => format_dart(capabilities) }
    registry.data.fetch('store_metadata').each { |path, copy| result[path] = copy + "\n" }
    result
  end

  def self.verify_outputs!(registry, outputs: self.outputs(registry))
    differences = outputs.keys.select do |path|
      begin
        registry.read_regular(path) != outputs.fetch(path).b
      rescue RuntimeError
        true
      end
    end
    raise "Stale capability consumers: #{differences.join(', ')}" unless differences.empty?
    true
  end

  def self.run(check:)
    registry = CollectProductCapabilities.new(ROOT)
    results = outputs(registry)
    if check
      verify_outputs!(registry, outputs: results)
    else
      results.each do |path, copy|
        destination = File.join(ROOT, path)
        raise 'Aliased generated capability consumer' if File.symlink?(destination)
        parent = File.dirname(path)
        cursor = ROOT
        parent.split('/').each do |part|
          cursor = File.join(cursor, part)
          raise 'Aliased generated capability parent' if File.symlink?(cursor)
        end
        File.binwrite(destination, copy)
      end
    end
    puts JSON.pretty_generate({status: 'pass', check: check, registry_sha256: registry.sha256,
      outputs: results.to_h { |path, bytes| [path, Digest::SHA256.hexdigest(bytes)] },
      owner_approved: false, publication_approved: false, provider_approved: false})
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: generate_product_capability_content.rb [--check]') unless ARGV.empty? || ARGV == ['--check']
  begin
    CollectCapabilityContentGenerator.run(check: ARGV == ['--check'])
  rescue JSON::ParserError, KeyError, TypeError, RuntimeError => error
    warn error.message
    exit 1
  end
end
