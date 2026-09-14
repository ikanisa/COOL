# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../qa/revolut_evidence_consistency'

class RevolutEvidenceConsistencyTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @root = Dir.mktmpdir('collect-consistency-fixture-')
    @skill = File.join(@root, 'skill')
    write('skill/references/mobile-design-100.md', 'Synthetic rule fixture')
    contract = JSON.parse(File.read(File.join(ROOT, MobileDesignGate::CONTRACT)))
    contract.merge!(
      'authority_sha256' => Digest::SHA256.file(File.join(@skill, MobileDesignGate::AUTHORITY_RULE)).hexdigest,
      'route_inventory' => 'integration_test/routes.dart',
      'reference_registry' => 'references/registry.json',
      'additional_states' => ['empty'], 'variant_cases' => ['home'],
      'variants' => ['light'], 'keyboard_cases' => ['home'], 'annotations' => ['home-cards']
    )
    write(MobileDesignGate::CONTRACT, JSON.generate(contract))
    write('lib/main.dart', 'void main() {}')
    write('pubspec.yaml', "version: 1.2.4+23\n")
    write('integration_test/routes.dart', "_RouteSpec('home', '/home', 'primary')")
    write('references/registry.json', JSON.generate(
      'schema_version' => 1, 'source_cohorts' => { 'fixture' => { 'reference_id' => 'fixture' } }
    ))
    write(contract['original_reference_manifest'], JSON.generate(
      'schema_version' => 1, 'capture_kind' => 'original_mobile_screenshot',
      'images' => [{ 'id' => 'fixture', 'path' => '.cache/references/fixture.png',
        'sha256' => 'a' * 64, 'width' => 390, 'height' => 844,
        'source_url' => 'https://drive.google.com/file/d/synthetic-fixture/view' }]
    ))
    @evidence = { 'schema_version' => 1, 'scope' => 'mobile', 'status' => 'blocked',
      'artifacts' => {}, 'cases' => [], 'annotations' => [], 'open_findings' => ['unverified'] }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write(path, content)
    target = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end

  def result
    write(MobileDesignGate::ACCEPTANCE, JSON.generate(@evidence))
    RevolutEvidenceConsistency.new(@root, skill_root: @skill).result
  end

  def row(platform = 'android')
    { 'id' => 'home@default', 'platform' => platform, 'reference_ids' => ['fixture'] }
  end

  def test_honest_blocked_record_is_consistent_without_being_accepted
    actual = result
    assert_equal 'consistent', actual['status']
    assert_equal 'blocked', actual['acceptance_status']
    assert_equal 'not_assessed_by_consistency_check', actual['release_status']
    assert_equal({}, actual['platform_acceptance_checks'])
  end

  def test_duplicate_platform_cases_are_rejected
    @evidence['cases'] = [row, row]
    assert_equal 'inconsistent', result['status']
  end

  def test_same_route_on_different_platforms_is_allowed
    @evidence['cases'] = [row, row('ios')]
    assert_equal 'consistent', result['status']
  end

  def test_unknown_route_and_reference_are_rejected
    @evidence['cases'] = [row.merge('id' => 'invented@default', 'reference_ids' => ['unregistered'])]
    actual = result
    assert_includes actual['failures'], 'Unknown case invented@default'
    assert_includes actual['failures'], 'Invalid references for invented@default'
  end

  def test_unknown_criteria_cannot_replace_required_criteria
    @evidence['cases'] = [row.merge('scores' => { 'looks_good' => 10 })]
    assert_equal 'inconsistent', result['status']
  end

  def test_unknown_annotation_case_is_rejected
    @evidence['annotations'] = [{ 'id' => 'home-cards', 'cases' => ['invented@default'] }]
    assert_equal 'inconsistent', result['status']
  end

  def test_claimed_approval_invokes_both_full_platform_gates
    @evidence['status'] = 'approved'
    @evidence['open_findings'] = []
    actual = result
    assert_equal 'inconsistent', actual['status']
    assert_equal %w[android ios], actual['platform_acceptance_checks'].keys.sort
    assert actual['platform_acceptance_checks'].values.all? { |value| value['status'] == 'blocked' }
  end

  def test_malformed_inventory_is_not_consistent
    @evidence['cases'] = 'not an array'
    assert_equal 'inconsistent', result['status']
  end
end
