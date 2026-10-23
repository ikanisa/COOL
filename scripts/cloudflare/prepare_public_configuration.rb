#!/usr/bin/env ruby
# frozen_string_literal: true

require 'date'
require 'digest'
require 'json'
require 'optparse'
require 'psych'

# Generates insert-only public configuration from the actual qualified mobile
# defaults export and existing public legal sources. It grants no legal,
# provider, financial or retention authority and performs no network writes.
class CollectPublicConfigurationPayload
  MOBILE_KEYS = %w[get_public_runtime_config get_collection_type_catalog list_account_request_reasons].freeze
  MOBILE_SOURCES = %w[
    lib/core/data/exact_json_values.dart lib/shared/models/collect_model_json_helpers.dart
    lib/shared/models/collect_models.dart lib/shared/models/collect_payment_json.dart
    lib/shared/models/collect_payment_models.dart lib/shared/models/collect_profile_country_rules.dart
    lib/shared/models/collect_summary_json.dart lib/shared/repositories/collect_repository_providers.dart
    pubspec.lock pubspec.yaml
  ].freeze
  LEGAL_SOURCES = {
    'privacy' => 'content/legal/collect_privacy_policy.yaml',
    'terms' => 'content/legal/collect_terms_of_use.yaml'
  }.freeze
  BUNDLE = 'content/legal/collect_legal_pages_bundle.yaml'
  GENERATOR = 'scripts/cloudflare/prepare_public_configuration.rb'
  SHA = /\A[0-9a-f]{64}\z/
  PROSE_KEYS = %w[body intro closing copy supporting_copy trust_statement risk_statement priority_rule zero_fee_clarification non_exclusion].freeze

  class UniqueObject < Hash
    def []=(key, value)
      raise 'Duplicate JSON key' if key?(key)
      super
    end
  end

  attr_reader :source_inputs, :coverage, :mobile_export_sha256

  def initialize(root:, mobile_export_bytes:, mobile_export_sha256:, api_source_id:)
    @root = File.expand_path(root)
    raise 'Physical source root required' unless File.realpath(@root) == @root && File.directory?(@root)
    raise 'Invalid source/export identity' unless [mobile_export_sha256, api_source_id].all? { |x| x.is_a?(String) && x.match?(SHA) }
    raise 'Mobile export exceeds bound' unless mobile_export_bytes.bytesize.between?(1, 131_072)
    raise 'Mobile export differs from qualified role' unless Digest::SHA256.hexdigest(mobile_export_bytes) == mobile_export_sha256
    @mobile_export_sha256 = mobile_export_sha256
    @api_source_id = api_source_id
    @source_inputs = {}; @coverage = {}
    @mobile = JSON.parse(utf8!(mobile_export_bytes), object_class: UniqueObject, create_additions: false)
    unless @mobile.keys.sort == %w[kind schema_version source_inputs values] && @mobile['schema_version'] == 1 &&
           @mobile['kind'] == 'collect_mobile_public_configuration_defaults' && @mobile.fetch('source_inputs').keys.sort == MOBILE_SOURCES.sort &&
           @mobile.fetch('values').keys.sort == MOBILE_KEYS.sort
      raise 'Unexpected mobile defaults export shape or scope'
    end
    @mobile.fetch('source_inputs').each do |name, expected|
      raise 'Unexpected source digest shape' unless expected.is_a?(Hash) && expected.keys.sort == %w[bytes sha256] &&
        expected['bytes'].is_a?(Integer) && expected['bytes'].positive? && expected['sha256'].is_a?(String) && expected['sha256'].match?(SHA)
      bytes = read_source(name)
      raise 'Changed mobile source input' unless expected == describe(bytes)
    end
  end

  def utf8!(raw)
    value = raw.dup.force_encoding(Encoding::UTF_8)
    raise 'Invalid UTF-8 or control character' unless value.valid_encoding? && !value.match?(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/)
    value
  end

  def describe(bytes)
    { 'sha256' => Digest::SHA256.hexdigest(bytes), 'bytes' => bytes.bytesize }
  end

  def read_source(name)
    raise 'Unsafe source path' unless name.is_a?(String) && name.match?(%r{\A[a-zA-Z0-9_. /-]+\z}) && !name.start_with?('/') &&
      name.split('/').none? { |p| ['', '.', '..'].include?(p) }
    path = @root
    name.split('/').each { |part| path = File.join(path, part); raise 'Aliased source path' if File.symlink?(path) }
    info = File.lstat(path)
    raise 'Bounded regular source required' unless info.file? && info.size.between?(1, 1_048_576)
    raw = File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      raise 'Source identity changed before reading' unless [file.stat.dev, file.stat.ino] == [info.dev, info.ino]
      file.read
    end
    after = File.lstat(path)
    signature = ->(s) { [s.dev, s.ino, s.mode, s.nlink, s.size, s.mtime.to_r, s.ctime.to_r] }
    raise 'Source changed during reading' unless signature.call(info) == signature.call(after)
    utf8!(raw)
    @source_inputs[name] = describe(raw)
    raw
  end

  def yaml(name)
    raw = read_source(name)
    nodes = 0
    visit = lambda do |node, depth|
      nodes += 1
      raise 'Unbounded YAML source' if depth > 32 || nodes > 20_000
      if node.is_a?(Psych::Nodes::Mapping)
        keys = node.children.each_slice(2).map do |key, _|
          raise 'Complex YAML key' unless key.is_a?(Psych::Nodes::Scalar)
          key.value
        end
        raise 'Duplicate YAML key' unless keys.uniq.length == keys.length
      end
      raise 'YAML aliases are not source authority' if node.is_a?(Psych::Nodes::Alias)
      (node.respond_to?(:children) && node.children || []).each { |child| visit.call(child, depth + 1) }
    end
    visit.call(Psych.parse_stream(raw), 0)
    Psych.safe_load(raw, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def text(value)
    raise 'Nonempty literal content required' unless value.is_a?(String) && !value.strip.empty?
    utf8!(value)
    value.start_with?('/') ? 'https://collect.ikanisa.com' + value : value
  end

  def label(key)
    raise 'Unknown content key type' unless key.is_a?(String) && key.match?(/\A[a-z][a-z0-9_]*\z/)
    key.tr('_', ' ').sub(/\A./, &:upcase)
  end

  def paragraphs(node, key = nil)
    case node
    when String
      value = text(node)
      key && !PROSE_KEYS.include?(key) ? [label(key) + ': ' + value] : [value]
    when Array
      raise 'Empty content sequence' if node.empty?
      node.flat_map do |value|
        value.is_a?(String) ? ['• ' + text(value)] : paragraphs(value)
      end
    when Hash
      raise 'Empty content object' if node.empty?
      node.flat_map do |name, value|
        next [] if name == 'id'
        if %w[heading title].include?(name)
          [text(value)]
        elsif value.is_a?(Array) && !%w[body bullets steps subsections trust_commitments].include?(name)
          [label(name) + ':'] + paragraphs(value)
        elsif value.is_a?(Hash)
          [label(name) + ':'] + paragraphs(value)
        else
          paragraphs(value, name)
        end
      end
    else
      raise 'Unsupported or unresolved public content value'
    end
  end

  def policy(kind)
    path = LEGAL_SOURCES.fetch(kind)
    page = yaml(path).fetch('page')
    raise 'Bundle and individual policy differ' unless @bundle_pages.fetch(kind) == page
    expected = %w[id title slug seo hero sections] + (kind == 'privacy' ? %w[last_updated privacy_at_a_glance] : %w[effective_date important_summary])
    raise 'Unreviewed policy page structure' unless page.is_a?(Hash) && page.keys.sort == expected.sort && page['sections'].is_a?(Array) && !page['sections'].empty?
    date = page.fetch(kind == 'privacy' ? 'last_updated' : 'effective_date')
    Date.strptime(date, '%e %B %Y')
    ids = page.fetch('sections').map { |s| s.fetch('id') }
    raise 'Duplicate policy section ID' unless ids.uniq.length == ids.length
    sections = [{ 'title' => text(page.fetch('hero').fetch('headline')), 'body' => paragraphs(page.fetch('hero')).join("\n\n") }]
    summary = kind == 'privacy' ? 'privacy_at_a_glance' : 'important_summary'
    sections << { 'title' => kind == 'privacy' ? 'Privacy at a glance' : 'Important summary', 'body' => paragraphs(page.fetch(summary)).join("\n\n") }
    page.fetch('sections').each do |section|
      title = text(section.fetch('heading'))
      body = section.reject { |k, _| %w[id heading].include?(k) }
      sections << { 'title' => title, 'body' => paragraphs(body).join("\n\n") }
    end
    @coverage[kind] = { 'source_section_ids' => ids, 'source_sections' => ids.length, 'served_sections' => sections.length,
      'hero_summary_and_all_section_values_retained' => true, 'excluded_nonbody_metadata' => %w[id slug seo] }
    { 'kind' => kind, 'title' => text(page.fetch('title')), 'locale' => 'en', 'version' => text(date) + ' (draft)',
      'content_status' => 'draft_for_legal_review', 'legal_release_approved' => false,
      'source_document_sha256' => @source_inputs.fetch(path).fetch('sha256'),
      'source_url' => 'https://collect.ikanisa.com' + page.fetch('slug'), 'sections' => sections }
  end

  def payload
    bundle = yaml(BUNDLE)
    raise 'Legal source review status changed' unless bundle.dig('site', 'content_status') == 'draft_for_legal_review'
    @bundle_pages = bundle.fetch('pages')
    values = @mobile.fetch('values').dup
    LEGAL_SOURCES.each_key { |kind| values['policy:' + kind] = policy(kind) }
    read_source(GENERATOR)
    records = values.keys.sort.map { |key| { 'key' => key, 'value_json' => JSON.generate(values.fetch(key)) } }
    raise 'Public configuration size exceeds bound' if records.sum { |r| r.fetch('value_json').bytesize } > 131_072
    { 'schema_version' => 1, 'kind' => 'collect_public_configuration_seed', 'api_source_id' => @api_source_id,
      'legal_release_approved' => false, 'provider_approved' => false, 'retention_policy_activation' => false,
      'source_inputs' => @source_inputs.sort.to_h, 'records' => records }
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |p|
    %w[root mobile-export mobile-export-sha256 api-source-id out].each { |name| p.on('--' + name + ' VALUE') { |value| options[name] = value } }
  end.parse!
  raise 'Exactly five explicit preparation arguments required' unless ARGV.empty? && options.keys.sort == %w[api-source-id mobile-export mobile-export-sha256 out root]
  export = options.fetch('mobile-export')
  raise 'Physical mobile export required' unless File.file?(export) && !File.symlink?(export)
  generator = CollectPublicConfigurationPayload.new(root: options.fetch('root'), mobile_export_bytes: File.binread(export),
    mobile_export_sha256: options.fetch('mobile-export-sha256'), api_source_id: options.fetch('api-source-id'))
  payload = generator.payload
  out = File.expand_path(options.fetch('out'))
  Dir.mkdir(out, 0o700)
  raw = JSON.pretty_generate(payload) + "\n"
  File.open(File.join(out, 'payload.json'), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(raw) }
  receipt = { 'status' => 'prepared_only_no_database_effect', 'payload_sha256' => Digest::SHA256.hexdigest(raw),
    'mobile_export_sha256' => generator.mobile_export_sha256, 'source_inputs' => generator.source_inputs,
    'coverage' => generator.coverage, 'legal_release_approved' => false, 'provider_approved' => false,
    'retention_policy_activation' => false, 'existing_mobile_admin_url_retained_without_conversion_or_domain_ownership_claim' => true }
  File.open(File.join(out, 'preparation.json'), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(JSON.pretty_generate(receipt) + "\n") }
  puts JSON.generate({ 'status' => receipt['status'], 'payload_sha256' => receipt['payload_sha256'], 'keys' => payload.fetch('records').map { |r| r.fetch('key') } })
end
