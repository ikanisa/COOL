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
  AUTHORITY = 'revolut-design'
  AUTHORITY_RULE = 'references/mobile-design-100.md'
  CRITERIA = %w[reference_fidelity hierarchy_density typography colour_elevation spacing_shape icons_assets copy_annotations interaction_states responsive_keyboard accessibility_native].freeze
  QUALITY_DIMENSIONS = %w[task_usability accessibility performance runtime_resilience].freeze
  REVIEW_ROLES = %w[implementer independent_visual owner].freeze
  ARTIFACTS = {
    'android' => {
      'apk' => 'build/app/outputs/flutter-apk/app-production-release.apk',
      'aab' => 'build/app/outputs/bundle/productionRelease/app-production-release.aab'
    },
    'ios' => { 'ipa' => 'build/ios/ipa/Collect.ipa' }
  }.freeze
  SOURCE_PATTERNS = %w[lib/app/**/*.dart lib/core/**/*.dart lib/features/**/*.dart lib/shared/**/*.dart lib/l10n/**/*.dart lib/main.dart lib/bootstrap.dart assets/**/* android/app/src/**/* android/app/build.gradle.kts ios/Runner/**/* pubspec.yaml pubspec.lock AGENTS.md integration_test/mobile_route_matrix_device_uat_test.dart integration_test/mobile_material_state_matrix_device_uat_test.dart test/fixtures/collect_repository_fixture.dart test/fixtures/mobile_matrix_capture.dart scripts/qa/*.rb scripts/android_play_store_build.sh scripts/ios_app_store_build.sh].freeze

  def initialize(root, skill_root: nil)
    @root = File.realpath(root)
    @skill_root = skill_root || ENV['REVOLUT_DESIGN_SKILL_ROOT'] ||
      File.join(ENV.fetch('CODEX_HOME', File.expand_path('~/.codex')), 'skills', AUTHORITY)
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

  def authority_file
    path = File.expand_path(contract.fetch('authority_rule'), @skill_root)
    return nil unless path.start_with?("#{File.expand_path(@skill_root)}/") && File.file?(path)

    File.realpath(path)
  rescue Errno::ENOENT
    nil
  end

  def authority_digest
    file = authority_file
    file && Digest::SHA256.file(file).hexdigest
  end

  def source_digest
    patterns = SOURCE_PATTERNS + %w[route_inventory material_state_inventory].map { |key| contract.fetch(key) }
    paths = patterns.flat_map { |p| Dir.glob(File.join(@root, p)) }
      .select { |p| File.file?(p) }.map { |p| p.delete_prefix("#{@root}/") }
      .reject { |p| p.include?('/GeneratedPluginRegistrant.') }.uniq.sort
    raise 'Mobile source inventory is empty' unless paths.include?('lib/main.dart')
    Digest::SHA256.hexdigest(paths.map { |p| "#{p}\0#{digest(p)}\n" }.join)
  end

  def fingerprints
    original_manifest = contract.fetch('original_reference_manifest')
    raise 'Original reference manifest is missing' unless digest(original_manifest)
    registry = contract.fetch('reference_registry')
    raise 'Reference registry is missing' unless digest(registry)
    reference_inputs = [original_manifest, registry].sort
    {
      'source_sha256' => source_digest,
      'contract_sha256' => digest(CONTRACT),
      'references_sha256' => Digest::SHA256.hexdigest(reference_inputs.map { |p| "#{p}\0#{digest(p)}\n" }.join),
      'authority_sha256' => contract.fetch('authority_sha256'),
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

  def inventory_specs(key, kind)
    path = contract.fetch(key)
    file = local_file(path) || raise("Missing #{key}")
    source = File.read(file)
    # Preserve string literals and line positions while excluding comments.
    # These harnesses deliberately declare literal constructor lists; dynamic
    # or malformed entries must fail instead of disappearing from coverage.
    tokens = /r?'''[\s\S]*?'''|r?"""[\s\S]*?"""|r?'(?:\\.|[^'\\])*'|r?"(?:\\.|[^"\\])*"|\/\/[^\n]*|\/\*[\s\S]*?\*\//
    clean = source.gsub(tokens) do |token|
      token.start_with?('//', '/*') ? token.gsub(/[^\n]/, ' ') : token
    end
    constructor = "_#{kind}Spec"
    variable = kind == 'Route' ? '_routeSpecs' : '_stateSpecs'
    declaration = clean.match(/\b(?:const|final)\s+#{variable}\s*=\s*<#{constructor}>\s*\[(.*?)^\];/m)
    body = declaration ? declaration[1] : clean
    offset = declaration ? declaration.begin(1) : 0
    entries = []
    body.to_enum(:scan, /\b#{constructor}\s*\(\s*'([^']+)'\s*,\s*'([^']+)'/).each do
      match = Regexp.last_match
      id, route = match.captures
      raise "Invalid #{key} case" unless id.match?(/\A[a-z0-9][a-z0-9-]*\z/) && route.start_with?('/')
      entries << { 'id' => id, 'route' => route, 'source' => path,
                   'line' => source[0...(offset + match.begin(0))].count("\n") + 1 }
    end
    raise "Empty or unparseable #{key}" unless !entries.empty? &&
      entries.length == body.scan(/\b#{constructor}\s*\(/).length
    ids = entries.map { |entry| entry['id'] }
    raise "Duplicate #{key} case IDs" unless ids.uniq == ids
    entries
  end

  def base_case_ids
    routes = inventory_specs('route_inventory', 'Route').map { |entry| entry['id'] }
    states = inventory_specs('material_state_inventory', 'State').map { |entry| entry['id'] }
    (routes + states + contract.fetch('additional_states')).uniq.sort
  end

  def required_cases
    raise 'All base cases must retain the declared variants' unless contract['variant_scope'] == 'all_base_cases'
    ids = base_case_ids
    base = ids.map { |id| "#{id}@default" }
    # Retain every older explicitly selected variant as well as every current
    # route/material state. Adding a harness case cannot silently omit variants.
    variants = (ids + contract.fetch('variant_cases')).uniq.product(contract.fetch('variants')).map { |id, variant| "#{id}@#{variant}" }
    (base + variants + contract.fetch('keyboard_cases').map { |id| "#{id}@keyboard" }).uniq.sort
  end

  def registered_reference_ids
    registry = read_json(contract.fetch('reference_registry'))
    raise 'Invalid reference registry' unless registry['schema_version'] == 1 && registry['source_cohorts'].is_a?(Hash)

    cohort_ids = registry['source_cohorts'].flat_map do |key, entry|
      [key, entry.is_a?(Hash) ? entry['reference_id'] : nil]
    end.compact
    (original_references.map { |entry| entry['id'] } + cohort_ids).uniq
  end

  def validate_contract(require_authority: false)
    failures = []
    failures << 'Wrong rule or schema' unless contract['schema_version'] == 1 && contract['rule'] == 'MOBILE-DESIGN-100'
    failures << 'revolut-design must be the sole design authority' unless
      contract['authority'] == AUTHORITY && contract['authority_rule'] == AUTHORITY_RULE
    failures << 'Invalid authority SHA-256' unless contract['authority_sha256'].to_s.match?(/\A[0-9a-f]{64}\z/)
    if authority_file
      failures << 'Installed revolut-design authority differs from the product contract' unless
        authority_digest == contract['authority_sha256']
    elsif require_authority
      failures << 'Installed revolut-design authority is unavailable'
    end
    failures << 'All ten fixed criteria are mandatory' unless contract['criteria'] == CRITERIA
    failures << 'All base cases must retain the declared variants' unless contract['variant_scope'] == 'all_base_cases'
    %w[additional_states variant_cases variants keyboard_cases annotations].each do |key|
      values = contract[key]
      failures << "Invalid or duplicate #{key}" unless values.is_a?(Array) && !values.empty? && values.all? { |v| v.is_a?(String) && !v.strip.empty? } && values.uniq == values
    end
    # CI can inspect the manifest without exposing private reference pixels.
    # Distribution additionally requires the actual originals below.
    original_references
    registered_reference_ids
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

  def evidence_file_valid?(entry)
    return false unless entry.is_a?(Hash)
    file = local_file(entry['path'])
    file && File.size(file).positive? && entry['sha256'] == digest(entry['path'])
  end

  def review_valid?(review, built_at)
    return false unless review.is_a?(Hash) && built_at
    timestamp = Time.iso8601(review['at'].to_s) rescue nil
    !review['reviewer'].to_s.strip.empty? && timestamp &&
      timestamp >= built_at && timestamp <= Time.now.utc &&
      review['notes'].to_s.strip.length >= 20
  end

  def binding_valid?(record, platform, artifacts)
    record.is_a?(Hash) && record['platform'] == platform &&
      fingerprints.all? { |key, value| value && record[key] == value } &&
      record['artifacts'] == artifacts
  end

  def case_scope_valid?(cases)
    cases.is_a?(Array) && !cases.empty? && cases.uniq == cases &&
      (cases - required_cases).empty?
  end

  def validate_quality_evidence(evidence, platform, artifacts, built_at, failures)
    records = evidence['quality_evidence']
    unless records.is_a?(Array)
      failures << 'Independent quality evidence is missing'
      return {}
    end
    by_id = {}
    records.each do |record|
      unless record.is_a?(Hash) && ARTIFACTS.key?(record['platform'])
        failures << 'Invalid quality evidence record or platform'
        next
      end
      next unless record['platform'] == platform

      id = record['id']
      unless id.is_a?(String) && !id.strip.empty? && !by_id.key?(id)
        failures << 'Invalid or duplicate quality evidence ID'
        next
      end
      by_id[id] = record
      failures << "#{id}: incomplete quality result" unless
        QUALITY_DIMENSIONS.include?(record['dimension']) && record['status'] == 'pass' &&
        record['open_findings'] == [] && !record['environment'].to_s.strip.empty? &&
        binding_valid?(record, platform, artifacts) && case_scope_valid?(record['cases']) &&
        review_valid?(record['review'], built_at) && evidence_file_valid?(record['evidence'])
    end
    by_id
  end

  def validate_platform_reviews(evidence, platform, artifacts, built_at, failures)
    reviews = evidence.dig('platform_reviews', platform)
    unless reviews.is_a?(Hash) && reviews.keys.sort == REVIEW_ROLES.sort
      failures << "#{platform}: distinct implementer, independent visual and owner reviews are required"
      return
    end
    REVIEW_ROLES.each do |role|
      review = reviews[role]
      failures << "#{platform}: #{role} review is missing, stale or incomplete" unless
        review.is_a?(Hash) && review['decision'] == 'approved' &&
        binding_valid?(review, platform, artifacts) &&
        case_scope_valid?(review['cases']) && review['cases'].sort == required_cases &&
        review_valid?(review, built_at) && evidence_file_valid?(review['evidence'])
    end
    return unless REVIEW_ROLES.all? { |role| reviews[role].is_a?(Hash) }

    identities = REVIEW_ROLES.to_h { |role| [role, reviews[role]['reviewer'].to_s.strip.downcase.gsub(/\s+/, ' ')] }
    failures << "#{platform}: visual reviewer must be independent of implementer and owner" if
      [identities['implementer'], identities['owner']].include?(identities['independent_visual'])
    proofs = REVIEW_ROLES.map { |role| reviews[role].dig('evidence', 'sha256') }
    failures << "#{platform}: each review requires its own decision evidence" unless proofs.uniq.length == REVIEW_ROLES.length
    times = REVIEW_ROLES.to_h do |role|
      [role, (Time.iso8601(reviews[role]['at'].to_s) rescue nil)]
    end
    if times.values.all? && times['owner'] < [times['implementer'], times['independent_visual']].max
      failures << "#{platform}: owner acceptance predates the completed reviews"
    end
  end

  def release_result(platform = 'android')
    failures = validate_contract(require_authority: true)
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
    quality_evidence = validate_quality_evidence(evidence, platform, artifact_digests, built_at, failures)
    validate_platform_reviews(evidence, platform, artifact_digests, built_at, failures)
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
      failures << "#{id}: comparison is not linked to registered references" unless
        reference_ids.is_a?(Array) && !reference_ids.empty? &&
        reference_ids.uniq == reference_ids &&
        (reference_ids - registered_reference_ids).empty?
      failures << "#{id}: missing actual review after this build" unless review_valid?(row['review'], built_at)
      failures << "#{id}: interaction/accessibility checks incomplete" unless row['interaction_checks'] == 'pass' && row['accessibility_checks'] == 'pass'
      quality_results = row['quality_results']
      unless quality_results.is_a?(Hash) && quality_results.keys.sort == QUALITY_DIMENSIONS.sort
        failures << "#{id}: four separate quality results are required"
        next
      end
      QUALITY_DIMENSIONS.each do |dimension|
        record = quality_evidence[quality_results[dimension]]
        failures << "#{id}: #{dimension} evidence is missing or outside this case" unless
          record && record['dimension'] == dimension && Array(record['cases']).include?(id)
      end
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
