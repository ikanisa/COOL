#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'digest'
require 'time'

# Evidence validation, not an aesthetic score generator. There is deliberately
# no approval-writing, baseline-updating, network or skip/waiver operation here.
class MobileDesignGate
  CONTRACT = 'docs/release/mobile-design/mobile-parity-contract.json'
  ACCEPTANCE = 'docs/release/mobile-design/mobile-parity-acceptance.json'
  CRITERIA = %w[reference_fidelity hierarchy_density typography colour_elevation spacing_shape icons_assets copy_annotations interaction_states responsive_keyboard accessibility_native].freeze
  ARTIFACTS = {
    'android' => {
      'apk' => 'build/app/outputs/flutter-apk/app-production-release.apk',
      'aab' => 'build/app/outputs/bundle/productionRelease/app-production-release.aab'
    },
    'ios' => { 'ipa' => 'build/ios/ipa/Collect.ipa' }
  }.freeze
  SOURCE_PATTERNS = %w[lib/app/**/*.dart lib/core/**/*.dart lib/features/**/*.dart lib/shared/**/*.dart lib/l10n/**/*.dart lib/main.dart lib/bootstrap.dart assets/**/* android/app/src/**/* android/app/build.gradle.kts ios/Runner/**/* pubspec.yaml pubspec.lock DESIGN.md AGENTS.md integration_test/mobile_route_matrix_device_uat_test.dart integration_test/mobile_material_state_matrix_device_uat_test.dart scripts/qa/*.rb scripts/android_play_store_build.sh scripts/ios_app_store_build.sh].freeze

  def initialize(root)
    @root = File.realpath(root)
  end

  def local_file(path)
    return nil unless path.is_a?(String) && !path.empty?
    expanded = File.expand_path(path, @root)
    return nil unless expanded.start_with?("#{@root}/") && File.file?(expanded)
    real = File.realpath(expanded)
    real.start_with?("#{@root}/") ? real : nil
  end

  def digest(path)
    file = local_file(path)
    file && Digest::SHA256.file(file).hexdigest
  end

  # The controlled Android wrapper can place Gradle intermediates on an
  # internal APFS volume and symlink its output directories into build/.
  # Only the fixed release artifact names may resolve through that layout;
  # screenshots, references and all other evidence stay repository-local.
  def artifact_file(path)
    return nil unless ARTIFACTS.values.any? { |artifacts| artifacts.value?(path) }
    expanded = File.join(@root, path)
    return nil unless File.file?(expanded) && !File.symlink?(expanded)
    File.realpath(expanded)
  end

  def artifact_digest(path)
    file = artifact_file(path)
    file && Digest::SHA256.file(file).hexdigest
  end

  def read_json(path)
    JSON.parse(File.read(local_file(path) || raise("Missing #{path}")))
  end

  def contract
    @contract ||= read_json(CONTRACT)
  end

  def source_digest
    paths = SOURCE_PATTERNS.flat_map { |p| Dir.glob(File.join(@root, p)) }
      .select { |p| File.file?(p) }.map { |p| p.delete_prefix("#{@root}/") }
      .reject { |p| p.include?('/GeneratedPluginRegistrant.') }.uniq.sort
    raise 'Mobile source inventory is empty' unless paths.include?('lib/main.dart')
    Digest::SHA256.hexdigest(paths.map { |p| "#{p}\0#{digest(p)}\n" }.join)
  end

  def fingerprints
    refs = contract.fetch('reference_paths')
    raise 'A required reference image is missing' unless refs.all? { |p| digest(p) }
    original_manifest = contract.fetch('original_reference_manifest')
    raise 'Original reference manifest is missing' unless digest(original_manifest)
    reference_inputs = (refs + [original_manifest]).sort
    {
      'source_sha256' => source_digest,
      'contract_sha256' => digest(CONTRACT),
      'references_sha256' => Digest::SHA256.hexdigest(reference_inputs.map { |p| "#{p}\0#{digest(p)}\n" }.join),
      'version' => File.read(File.join(@root, 'pubspec.yaml'))[/^version:\s*(\S+)/, 1]
    }
  end

  def original_references
    manifest = read_json(contract.fetch('original_reference_manifest'))
    raise 'Invalid original reference manifest' unless manifest['schema_version'] == 1 && manifest['capture_kind'] == 'original_mobile_screenshot'
    images = manifest['images']
    raise 'Original reference inventory is empty' unless images.is_a?(Array) && !images.empty?
    images.each do |entry|
      raise 'Invalid original reference entry' unless entry.is_a?(Hash) &&
        entry['id'].is_a?(String) && !entry['id'].strip.empty? &&
        entry['path'].is_a?(String) && entry['path'].start_with?('.cache/') &&
        entry['sha256'].to_s.match?(/\A[0-9a-f]{64}\z/) &&
        entry['width'].is_a?(Integer) && entry['width'] >= 300 &&
        entry['height'].is_a?(Integer) && entry['height'] >= 300 &&
        entry['source_url'].to_s.start_with?('https://drive.google.com/file/d/')
    end
    ids = images.map { |entry| entry['id'] }
    paths = images.map { |entry| entry['path'] }
    raise 'Duplicate original references' unless ids.uniq == ids && paths.uniq == paths
    images
  end

  def required_cases
    route_file = local_file(contract.fetch('route_inventory')) || raise('Missing route inventory')
    routes = File.read(route_file).scan(/_RouteSpec\(\s*'([^']+)'/).flatten
    raise 'Route inventory is empty' if routes.empty?
    base = (routes + contract.fetch('additional_states')).uniq.map { |id| "#{id}@default" }
    variants = contract.fetch('variant_cases').product(contract.fetch('variants')).map { |id, variant| "#{id}@#{variant}" }
    (base + variants + contract.fetch('keyboard_cases').map { |id| "#{id}@keyboard" }).uniq.sort
  end

  def validate_contract
    failures = []
    failures << 'Wrong rule or schema' unless contract['schema_version'] == 1 && contract['rule'] == 'MOBILE-DESIGN-100'
    failures << 'DESIGN.md must be the sole authority' unless contract['authority'] == 'DESIGN.md'
    failures << 'All ten fixed criteria are mandatory' unless contract['criteria'] == CRITERIA
    %w[reference_paths additional_states variant_cases variants keyboard_cases annotations].each do |key|
      values = contract[key]
      failures << "Invalid or duplicate #{key}" unless values.is_a?(Array) && !values.empty? && values.all? { |v| v.is_a?(String) && !v.strip.empty? } && values.uniq == values
    end
    failures << 'Mobile rule is missing from design authority' unless File.read(File.join(@root, 'DESIGN.md')).include?('MOBILE-DESIGN-100')
    # CI can inspect the manifest without exposing private reference pixels.
    # Distribution additionally requires the actual originals below.
    original_references
    required_cases
    fingerprints
    failures
  rescue StandardError => e
    failures + [e.message]
  end

  def image_valid?(entry)
    return false unless entry.is_a?(Hash)
    file = local_file(entry['path'])
    return false unless file && digest(entry['path']) == entry['sha256']
    header = File.binread(file, 24)
    return false unless header.start_with?("\x89PNG\r\n\x1a\n".b) && header.bytesize == 24
    width, height = header.byteslice(16, 8).unpack('NN')
    width >= 300 && height >= 300 && File.size(file) > 8000
  end

  def release_result(platform = 'android')
    failures = validate_contract
    return result(platform, failures) unless failures.empty?
    evidence = read_json(ACCEPTANCE)
    originals = original_references
    originals.each do |entry|
      if image_valid?(entry)
        size = File.binread(local_file(entry['path']), 24).byteslice(16, 8).unpack('NN')
        failures << "Original reference dimensions changed: #{entry['id']}" unless size == [entry['width'], entry['height']]
      else
        failures << "Missing or changed original reference: #{entry['id']}"
      end
    end
    failures << 'Acceptance must be mobile-only and approved' unless evidence['schema_version'] == 1 && evidence['scope'] == 'mobile' && evidence['status'] == 'approved'
    fingerprints.each { |key, expected| failures << "Stale or absent #{key}" unless expected && evidence[key] == expected }
    failures << 'Open findings remain' unless evidence['open_findings'] == []
    artifacts = ARTIFACTS.fetch(platform)
    artifact_digests = {}
    artifacts.each do |kind, path|
      sha = artifact_digest(path)
      artifact_digests[kind] = sha
      failures << "Missing or mismatched #{platform} #{kind}" unless sha && evidence.dig('artifacts', platform, kind) == sha
    end
    provenance = read_json(".cache/mobile-design-build/#{platform}.json")
    failures << 'Release build provenance does not match current source' unless
      provenance['schema_version'] == 1 && provenance['platform'] == platform &&
      provenance['source_sha256'] == source_digest &&
      provenance['version'] == fingerprints['version'] &&
      provenance['artifacts'] == artifact_digests &&
      provenance['evidence_mode'] == false
    built_at = Time.iso8601(provenance['built_at'].to_s) rescue nil
    failures << 'Invalid release build timestamp' unless built_at && built_at <= Time.now.utc
    installed_sha = artifact_digests[platform == 'android' ? 'apk' : 'ipa']
    rows = Array(evidence['cases']).select { |row| row.is_a?(Hash) && row['platform'] == platform }
    keys = rows.map { |row| row['id'] }
    failures << 'Duplicate native cases' unless keys.uniq == keys
    (required_cases - keys).each { |id| failures << "Missing #{platform} case #{id}" }
    rows.each do |row|
      id = row['id']
      failures << "Unexpected case #{id}" unless required_cases.include?(id)
      scores = row['scores']
      full_score = scores.is_a?(Hash) && scores.keys.sort == CRITERIA.sort && scores.values.all? { |v| v == 10 }
      failures << "#{id}: not 100/100" unless full_score
      failures << "#{id}: native installed artifact not verified" unless row['capture_kind'] == 'native' && installed_sha && row['installed_artifact_sha256'] == installed_sha
      failures << "#{id}: missing or changed screenshot" unless image_valid?(row['screenshot'])
      failures << "#{id}: missing or changed comparison" unless image_valid?(row['comparison'])
      reference_ids = row['reference_ids']
      failures << "#{id}: comparison is not linked to original references" unless
        reference_ids.is_a?(Array) && !reference_ids.empty? &&
        reference_ids.uniq == reference_ids &&
        (reference_ids - originals.map { |entry| entry['id'] }).empty?
      review = row['review'] || {}
      timestamp = Time.iso8601(review['at'].to_s) rescue nil
      failures << "#{id}: missing actual review" unless !review['reviewer'].to_s.strip.empty? && timestamp && timestamp <= Time.now.utc && review['notes'].to_s.strip.length >= 20
      failures << "#{id}: interaction/accessibility checks incomplete" unless row['interaction_checks'] == 'pass' && row['accessibility_checks'] == 'pass'
    end
    annotations = Array(evidence['annotations'])
    contract.fetch('annotations').each do |id|
      matches = annotations.select { |entry| entry.is_a?(Hash) && entry['id'] == id }
      entry = matches.first || {}
      failures << "Unclosed annotation #{id}" unless matches.length == 1 && entry['status'] == 'verified' && digest(entry['test_path']) && entry['test_sha256'] == digest(entry['test_path']) && Array(entry['cases']).any? && (Array(entry['cases']) - keys).empty?
    end
    result(platform, failures)
  rescue StandardError => e
    result(platform, failures.to_a + [e.message])
  end

  def result(platform, failures)
    { 'rule' => 'MOBILE-DESIGN-100', 'platform' => platform,
      'status' => failures.empty? ? 'pass' : 'blocked',
      'score' => failures.empty? ? 100 : nil, 'failures' => failures }
  end
end

if $PROGRAM_NAME == __FILE__
  args = ARGV.dup
  platform = args.delete('--ios') ? 'ios' : 'android'
  mode = args.delete('--check-contract') ? 'contract' : args.delete('--fingerprint') ? 'fingerprint' : 'release'
  json = args.delete('--json')
  abort 'Unknown option; no bypass flags are supported' unless args.empty?
  gate = MobileDesignGate.new(File.expand_path('../..', __dir__))
  if mode == 'contract'
    failures = gate.validate_contract
    payload = { status: failures.empty? ? 'contract_valid' : 'blocked', release_status: 'not_assessed', failures: failures }
  elsif mode == 'fingerprint'
    payload = gate.fingerprints.merge('release_status' => 'not_assessed')
    failures = []
  else
    payload = gate.release_result(platform)
    failures = payload.fetch('failures')
  end
  if json || mode != 'release'
    puts JSON.pretty_generate(payload)
  else
    puts "[MOBILE-DESIGN-100] #{payload['status'].upcase}"
    failures.each { |failure| puts "- #{failure}" }
  end
  exit(failures.empty? ? 0 : 1)
end
