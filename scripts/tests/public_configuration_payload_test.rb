# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../cloudflare/prepare_public_configuration'

class PublicConfigurationPayloadTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  SOURCE = '931fe0726fc70de642920b859fa2a025018d2895c5bc9dd44e344f948e574a72'
  def setup
    @temporary = Dir.mktmpdir('collect-public-config-')
    @root = File.realpath(@temporary)
    paths = CollectPublicConfigurationPayload::MOBILE_SOURCES + CollectPublicConfigurationPayload::LEGAL_SOURCES.values +
      [CollectPublicConfigurationPayload::BUNDLE, CollectPublicConfigurationPayload::GENERATOR]
    paths.each do |name|
      target = File.join(@root, name)
      FileUtils.mkdir_p(File.dirname(target)); FileUtils.cp(File.join(ROOT, name), target)
    end
    @mobile = {
      'schema_version' => 1, 'kind' => 'collect_mobile_public_configuration_defaults',
      'source_inputs' => CollectPublicConfigurationPayload::MOBILE_SOURCES.to_h do |name|
        raw = File.binread(File.join(@root, name)); [name, { 'sha256' => Digest::SHA256.hexdigest(raw), 'bytes' => raw.bytesize }]
      end,
      # A declared unit fixture, not evidence of native default-value evaluation.
      'values' => {
        'get_public_runtime_config' => { 'brand' => { 'display_name' => 'Synthetic fixture Collect' }, 'support_channels' => [] },
        'get_collection_type_catalog' => { 'country_code' => 'RW', 'locale' => 'en', 'types' => [] },
        'list_account_request_reasons' => [{ 'key' => 'fixture', 'label' => 'Synthetic fixture reason' }]
      }
    }
  end
  def teardown
    FileUtils.remove_entry(@temporary)
  end
  def generator(raw = JSON.generate(@mobile), expected = nil)
    CollectPublicConfigurationPayload.new(root: @root, mobile_export_bytes: raw,
      mobile_export_sha256: expected || Digest::SHA256.hexdigest(raw), api_source_id: SOURCE)
  end
  def leaves(value)
    case value
    when String then [value]
    when Array then value.flat_map { |v| leaves(v) }
    when Hash then value.reject { |k, _| k == 'id' }.values.flat_map { |v| leaves(v) }
    else raise 'Unexpected legal source leaf'
    end
  end
  def test_complete_public_copy_and_safety_qualifiers_survive_conversion
    built = generator
    payload = built.payload
    assert_equal %w[get_collection_type_catalog get_public_runtime_config list_account_request_reasons policy:privacy policy:terms], payload.fetch('records').map { |r| r.fetch('key') }
    assert_equal false, payload.fetch('legal_release_approved')
    assert_equal false, payload.fetch('provider_approved')
    assert_equal false, payload.fetch('retention_policy_activation')
    values = payload.fetch('records').to_h { |r| [r.fetch('key'), JSON.parse(r.fetch('value_json'))] }
    @mobile.fetch('values').each { |key, expected| assert_equal expected, values.fetch(key) }
    CollectPublicConfigurationPayload::LEGAL_SOURCES.each do |kind, name|
      page = Psych.safe_load(File.read(File.join(@root, name)), permitted_classes: [], aliases: false).fetch('page')
      output = values.fetch('policy:' + kind)
      actual = output.fetch('sections').flat_map { |s| [s.fetch('title'), s.fetch('body')] }.join("\n")
      sources = [page.fetch('hero'), page.fetch(kind == 'privacy' ? 'privacy_at_a_glance' : 'important_summary'), page.fetch('sections')]
      leaves(sources).each { |text| assert_includes actual, text }
      assert_equal page.fetch('sections').length + 2, output.fetch('sections').length
      assert_equal 'draft_for_legal_review', output.fetch('content_status')
      assert_equal false, output.fetch('legal_release_approved')
      assert_equal kind, output.fetch('kind')
      assert_equal 'en', output.fetch('locale')
      assert_equal page.fetch(kind == 'privacy' ? 'last_updated' : 'effective_date') + ' (draft)', output.fetch('version')
    end
  end
  def test_changed_qualified_export_bytes_fail_before_publication
    raw = JSON.generate(@mobile)
    assert_raises(RuntimeError) { generator(raw + "\n", Digest::SHA256.hexdigest(raw)) }
  end
  def test_changed_mobile_source_is_rejected
    File.open(File.join(@root, 'lib/shared/models/collect_models.dart'), 'ab') { |f| f.write("\n// changed fixture\n") }
    assert_raises(RuntimeError) { generator }
  end
  def test_aliased_source_is_rejected_without_following_it
    path = File.join(@root, 'content/legal/collect_privacy_policy.yaml')
    File.unlink(path); File.symlink(File.join(ROOT, 'content/legal/collect_privacy_policy.yaml'), path)
    assert_raises(RuntimeError) { generator.payload }
  end
  def test_unknown_operation_or_source_cannot_expand_seed_scope
    @mobile.fetch('values')['privacy_retention_policy'] = { 'approved' => true }
    assert_raises(RuntimeError) { generator }
    @mobile.fetch('values').delete('privacy_retention_policy')
    @mobile.fetch('source_inputs')['../private.env'] = { 'sha256' => 'a' * 64, 'bytes' => 1 }
    assert_raises(RuntimeError) { generator }
  end
  def test_duplicate_json_and_yaml_keys_are_rejected
    raw = JSON.generate(@mobile).sub('"schema_version":1', '"schema_version":1,"schema_version":1')
    assert_raises(RuntimeError) { generator(raw) }
    file = File.join(@root, CollectPublicConfigurationPayload::BUNDLE)
    File.write(file, "site:\n  content_status: draft_for_legal_review\n  content_status: approved\npages: {}\n")
    assert_raises(RuntimeError) { generator.payload }
  end
  def test_individual_and_bundled_legal_sources_cannot_drift
    file = File.join(@root, 'content/legal/collect_privacy_policy.yaml')
    File.write(file, File.read(file).sub('Privacy Policy', 'Different fixture notice'))
    assert_raises(RuntimeError) { generator.payload }
  end
  def test_new_unresolved_legal_values_are_not_silently_omitted
    file = File.join(@root, 'content/legal/collect_privacy_policy.yaml')
    page = Psych.safe_load(File.read(file), permitted_classes: [], aliases: false)
    page.fetch('page').fetch('sections').first['body'] = nil
    File.write(file, Psych.dump(page))
    bundle = Psych.safe_load(File.read(File.join(@root, CollectPublicConfigurationPayload::BUNDLE)), permitted_classes: [], aliases: false)
    bundle.fetch('pages')['privacy'] = page.fetch('page')
    File.write(File.join(@root, CollectPublicConfigurationPayload::BUNDLE), Psych.dump(bundle))
    assert_raises(RuntimeError) { generator.payload }
  end
end
