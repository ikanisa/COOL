# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../cloudflare/prepare_policy_configuration'
class ExistingPolicyConfigurationPayloadTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  SOURCE = 'a' * 64
  def setup
    @temporary = Dir.mktmpdir('collect-policy-payload-'); @root = File.realpath(@temporary)
    paths = CollectPublicConfigurationPayload::LEGAL_SOURCES.values + [CollectPublicConfigurationPayload::BUNDLE,CollectPublicConfigurationPayload::GENERATOR,CollectExistingPolicyConfigurationPayload::GENERATOR]
    paths.each { |name| target=File.join(@root,name);FileUtils.mkdir_p(File.dirname(target));FileUtils.cp(File.join(ROOT,name),target) }
  end
  def teardown; FileUtils.remove_entry(@temporary); end
  def generator; CollectExistingPolicyConfigurationPayload.new(root:@root,api_source_id:SOURCE); end
  def leaves(value)
    case value
    when String then [value]
    when Array then value.flat_map { |v| leaves(v) }
    when Hash then value.reject { |k,_|k=='id' }.values.flat_map { |v| leaves(v) }
    else raise 'Unexpected policy source leaf'
    end
  end
  def test_only_policy_records_are_generated_without_mobile_defaults_or_compiler
    p=generator.payload
    assert_equal %w[policy:privacy policy:terms],p.fetch('records').map { |r|r.fetch('key') }
    assert_equal 'collect_existing_policy_configuration',p.fetch('kind')
    assert_equal 5,p.fetch('source_inputs').length
    assert_equal false,p.fetch('legal_release_approved');assert_equal false,p.fetch('provider_approved');assert_equal false,p.fetch('retention_policy_activation')
    refute File.exist?(File.join(@root,'pubspec.yaml'))
  end
  def test_current_legal_source_leaves_dates_and_draft_metadata_are_retained
    payload=generator.payload
    CollectPublicConfigurationPayload::LEGAL_SOURCES.each do |kind,path|
      page=Psych.safe_load(File.read(File.join(@root,path)),permitted_classes:[],aliases:false).fetch('page')
      row=payload.fetch('records').find { |r|r.fetch('key')=='policy:'+kind };value=JSON.parse(row.fetch('value_json'))
      prose=value.fetch('sections').flat_map { |s|[s.fetch('title'),s.fetch('body')] }.join("\n")
      [page.fetch('hero'),page.fetch(kind=='privacy'?'privacy_at_a_glance':'important_summary'),page.fetch('sections')].each { |node|leaves(node).each { |text|assert_includes prose,text } }
      assert_equal page.fetch(kind=='privacy'?'last_updated':'effective_date')+' (draft)',value.fetch('version')
      assert_equal 'draft_for_legal_review',value.fetch('content_status');assert_equal false,value.fetch('legal_release_approved')
      assert_equal Digest::SHA256.file(File.join(@root,path)).hexdigest,value.fetch('source_document_sha256')
    end
  end
  def test_unmatching_bundle_is_rejected
    f=File.join(@root,'content/legal/collect_privacy_policy.yaml');File.write(f,File.read(f).sub('Privacy Policy','Changed fixture notice'));assert_raises(RuntimeError) { generator.payload }
  end
  def test_alias_and_unapproved_bundle_cannot_enter_payload
    f=File.join(@root,'content/legal/collect_privacy_policy.yaml');File.unlink(f);File.symlink(File.join(ROOT,'content/legal/collect_privacy_policy.yaml'),f);assert_raises(RuntimeError) { generator.payload }
  end
  def test_invalid_source_identity_is_rejected
    assert_raises(RuntimeError) { CollectExistingPolicyConfigurationPayload.new(root:@root,api_source_id:'wrong') }
  end
end
