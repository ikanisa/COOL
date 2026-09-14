# frozen_string_literal: true

require_relative 'mobile_design_gate'

# Validate the current product evidence adapter, not the retired parity reports.
# A coherent blocked record can pass this CI check; only the platform release
# gates can establish acceptance. No evidence or approval is written here.
class RevolutEvidenceConsistency
  def initialize(root, skill_root: nil)
    @gate = MobileDesignGate.new(root, skill_root: skill_root)
  end

  def result
    failures = @gate.validate_contract
    evidence = @gate.read_json(MobileDesignGate::ACCEPTANCE)
    failures << 'Invalid mobile acceptance schema or scope' unless
      evidence['schema_version'] == 1 && evidence['scope'] == 'mobile'
    failures << 'Unknown acceptance status' unless
      %w[blocked pending unverified approved].include?(evidence['status'])
    %w[cases annotations open_findings].each do |key|
      failures << "#{key} must be an array" unless evidence[key].is_a?(Array)
    end
    failures << 'artifacts must be an object' unless evidence['artifacts'].is_a?(Hash)
    required_cases = @gate.required_cases
    reference_ids = @gate.registered_reference_ids
    case_keys = []
    Array(evidence['cases']).each do |row|
      unless row.is_a?(Hash)
        failures << 'Invalid case record'
        next
      end
      key = [row['platform'], row['id']]
      failures << "Duplicate case #{key.join(':')}" if case_keys.include?(key)
      case_keys << key
      failures << "Unknown platform #{row['platform']}" unless MobileDesignGate::ARTIFACTS.key?(row['platform'])
      failures << "Unknown case #{row['id']}" unless required_cases.include?(row['id'])
      if row.key?('reference_ids')
        ids = row['reference_ids']
        failures << "Invalid references for #{row['id']}" unless ids.is_a?(Array) &&
          ids.uniq == ids && (ids - reference_ids).empty?
      end
      next unless row.key?('scores')

      scores = row['scores']
      failures << "Invalid criteria for #{row['id']}" unless scores.is_a?(Hash) &&
        (scores.keys - MobileDesignGate::CRITERIA).empty? &&
        scores.values.all? { |score| score.is_a?(Integer) && score.between?(0, 10) }
    end
    annotation_ids = []
    Array(evidence['annotations']).each do |row|
      unless row.is_a?(Hash) && @gate.contract.fetch('annotations').include?(row['id'])
        failures << 'Unknown or invalid annotation'
        next
      end
      failures << "Duplicate annotation #{row['id']}" if annotation_ids.include?(row['id'])
      annotation_ids << row['id']
      if row.key?('cases') && (!row['cases'].is_a?(Array) || (row['cases'] - required_cases).any?)
        failures << "Unknown annotation case for #{row['id']}"
      end
    end
    platforms = {}
    if evidence['status'] == 'approved'
      MobileDesignGate::ARTIFACTS.each_key do |platform|
        platforms[platform] = @gate.release_result(platform)
        failures.concat(platforms[platform].fetch('failures').map { |message| "#{platform}: #{message}" })
      end
    end
    {
      'status' => failures.empty? ? 'consistent' : 'inconsistent',
      'scope' => 'product_evidence_consistency',
      'acceptance_status' => evidence['status'],
      'release_status' => 'not_assessed_by_consistency_check',
      'required_cases_per_platform' => required_cases.length,
      'recorded_cases' => case_keys.length,
      'platform_acceptance_checks' => platforms,
      'failures' => failures
    }
  rescue StandardError => error
    { 'status' => 'inconsistent', 'release_status' => 'not_assessed_by_consistency_check',
      'failures' => Array(failures) + [error.message] }
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'Usage: revolut_evidence_consistency.rb' unless ARGV.empty?
  result = RevolutEvidenceConsistency.new(File.expand_path('../..', __dir__)).result
  puts JSON.pretty_generate(result)
  exit(result['status'] == 'consistent' ? 0 : 1)
end
