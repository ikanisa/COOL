# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../product_capabilities'
require_relative '../generate_product_capability_content'
require_relative '../qa/public_static_routes'

class ProductCapabilityContentTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  BUILDER = File.join(ROOT, 'scripts/public_static_site_build.rb')
  SOURCE = File.read(BUILDER)
  STOP = SOURCE.index("\nallowed_build_roots = [") or raise 'Missing build execution boundary'
  RENDERER = Module.new
  RENDERER.module_eval(SOURCE[0...STOP], BUILDER)

  def setup
    @registry = CollectProductCapabilities.new(ROOT)
    @renderer = Object.new.extend(RENDERER)
    @data = JSON.parse(File.read(File.join(ROOT, CollectProductCapabilities::SOURCE)))
  end

  def changed
    yield @data
    CollectProductCapabilities.new(ROOT, bytes: JSON.generate(@data))
  end

  def page(path)
    RENDERER.const_get(:PAGES).find { |candidate| candidate[:path] == path }
  end

  def test_observed_region_platforms_and_approval_limits
    assert_equal 'RW', @registry.data['region']
    assert_equal 'RWF', @registry.data['currency']
    assert_equal CollectProductCapabilities::IDS.sort, @registry.data['capabilities'].map { |row| row['id'] }.sort
    %w[owner_approved publication_approved legal_release_approved provider_approved].each { |key| assert_equal false, @registry.data['approval'][key] }
    assert @registry.data.frozen?
    assert @registry.data['capabilities'].all?(&:frozen?)
    assert_equal 'assisted', @registry.state('support', region: 'RW', platform: 'android')
    assert_equal 'planned', @registry.state('basic_phone', region: 'RW', platform: 'basic_phone')
    assert_equal 'provider_dependent', @registry.state('insurance', region: 'RW', platform: 'ios')
  end

  def test_android_source_actions_keep_real_collect_store_and_contact_links
    %w[group_records private_group_creation momo_ussd receipt_sms].each do |id|
      assert_equal 'https://play.google.com/store/apps/details?id=app.cool.mobile',
        @registry.source_action(id, region: 'RW', platform: 'android')['href']
    end
    assert_equal 'mailto:info@ikanisa.com', @registry.source_action('support', region: 'RW', platform: 'ios')['href']
  end

  def test_ios_web_and_basic_phone_cannot_advertise_android_actions
    %w[momo_ussd receipt_sms].product(%w[ios web basic_phone]).each do |id, platform|
      assert_raises(RuntimeError) { @registry.source_action(id, region: 'RW', platform: platform) }
      assert_equal 'mailto:info@ikanisa.com', @registry.public_action(id, platform: platform)['href']
    end
  end

  def test_metadata_creation_source_is_available_across_app_platforms_without_approval
    %w[android ios web].each do |platform|
      assert_equal 'supported', @registry.state('private_group_creation', region: 'RW', platform: platform)
      assert_equal false, @registry.capability('private_group_creation')['owner_approved']
      assert_raises(RuntimeError) do
        @registry.source_action('private_group_creation', region: 'RW', platform: platform, require_approved: true)
      end
    end
    assert_raises(RuntimeError) do
      @registry.source_action('private_group_creation', region: 'RW', platform: 'basic_phone')
    end
  end

  def test_source_path_does_not_supply_owner_approved_availability
    assert_raises(RuntimeError) { @registry.source_action('momo_ussd', region: 'RW', platform: 'android', require_approved: true) }
  end

  def test_foreign_region_unknown_platform_and_unknown_capability_deny
    assert_raises(RuntimeError) { @registry.source_action('group_records', region: 'MT', platform: 'android') }
    assert_raises(RuntimeError) { @registry.public_action('group_records', region: 'KE') }
    assert_raises(RuntimeError) { @registry.source_action('group_records', region: 'RW', platform: 'desktop') }
    assert_raises(RuntimeError) { @registry.public_action('bank_transfer') }
  end

  def test_unavailable_provider_and_planned_services_have_no_enrollment_action
    %w[basic_phone credit_readiness loans insurance].each do |id|
      assert_raises(RuntimeError) { @registry.source_action(id, region: 'RW', platform: 'android') }
      assert_equal 'mailto:info@ikanisa.com', @registry.public_action(id)['href']
    end
  end

  def test_fabricated_owner_or_provider_approval_is_rejected
    %w[owner_approved provider_approved publication_approved].each do |key|
      @data = JSON.parse(File.read(File.join(ROOT, CollectProductCapabilities::SOURCE)))
      assert_raises(RuntimeError) { changed { |data| data['approval'][key] = true } }
    end
  end

  def test_unapproved_provider_state_cannot_be_promoted_to_supported
    assert_raises(RuntimeError) { changed { |data| data['capabilities'].find { |row| row['id'] == 'insurance' }['availability']['android'] = 'supported' } }
  end

  def test_android_only_capability_cannot_be_promoted_to_ios
    assert_raises(RuntimeError) { changed { |data| data['capabilities'].find { |row| row['id'] == 'momo_ussd' }['availability']['ios'] = 'supported' } }
  end

  def test_unknown_platform_and_duplicate_capability_state_are_rejected
    assert_raises(RuntimeError) { changed { |data| data['capabilities'].first['availability']['unknown'] = 'supported' } }
    @data = JSON.parse(File.read(File.join(ROOT, CollectProductCapabilities::SOURCE)))
    assert_raises(RuntimeError) { changed { |data| data['capabilities'] << data['capabilities'].first } }
  end

  def test_duplicate_json_field_cannot_hide_a_fabricated_fact
    original = File.read(File.join(ROOT, CollectProductCapabilities::SOURCE))
    duplicated = original.sub('"schema_version": 1,', '"schema_version": 1, "schema_version": 1,')
    assert_raises(RuntimeError) { CollectProductCapabilities.new(ROOT, bytes: duplicated) }
  end

  def test_changed_source_evidence_and_missing_capability_evidence_deny
    assert_raises(RuntimeError) { changed { |data| data['source_inputs']['docs/PRODUCT.md'] = '0' * 64 } }
    @data = JSON.parse(File.read(File.join(ROOT, CollectProductCapabilities::SOURCE)))
    assert_raises(RuntimeError) { changed { |data| data['capabilities'].first['evidence'] = ['unreviewed/availability.json'] } }
  end

  def test_aliased_evidence_cannot_bind_a_different_source
    Dir.mktmpdir('collect-capability-evidence-') do |root|
      @data.fetch('source_inputs').each_key do |path|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        FileUtils.cp(File.join(ROOT, path), File.join(root, path))
      end
      product = File.join(root, 'docs/PRODUCT.md')
      FileUtils.mv(product, product + '.other')
      File.symlink(product + '.other', product)
      assert_raises(RuntimeError) { CollectProductCapabilities.new(root, bytes: JSON.generate(@data)) }
    end
  end

  def test_fabricated_hosted_conversion_and_unknown_url_are_rejected
    assert_raises(RuntimeError) { changed { |data| data['capabilities'].first['hosted_conversion_verified'] = true } }
    @data = JSON.parse(File.read(File.join(ROOT, CollectProductCapabilities::SOURCE)))
    assert_raises(RuntimeError) { changed { |data| data['capabilities'].last['fallback_action']['href'] = 'https://unverified.example/enroll' } }
  end

  def test_obsolete_payment_rail_cannot_reappear_in_public_store_metadata
    assert_raises(RuntimeError) { changed { |data| data['store_metadata']['fastlane/metadata/en-GB/promotional_text.txt'] = 'Use SEPA bank transfers.' } }
  end

  def test_every_generated_flutter_and_store_consumer_is_exactly_current
    CollectCapabilityContentGenerator.outputs(@registry).each do |path, bytes|
      assert_equal bytes.b, File.binread(File.join(ROOT, path)), path
    end
  end

  def test_a_changed_generated_consumer_is_rejected_in_an_actual_isolated_copy
    outputs = CollectCapabilityContentGenerator.outputs(@registry)
    Dir.mktmpdir('collect-capability-consumers-') do |root|
      @data.fetch('source_inputs').each_key do |path|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        FileUtils.cp(File.join(ROOT, path), File.join(root, path))
      end
      outputs.each do |path, bytes|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.binwrite(File.join(root, path), bytes)
      end
      registry = CollectProductCapabilities.new(root, bytes: JSON.generate(@data))
      assert CollectCapabilityContentGenerator.verify_outputs!(registry, outputs: outputs)
      File.binwrite(File.join(root, 'fastlane/metadata/en-GB/description.txt'), 'Use SEPA transfers')
      assert_raises(RuntimeError) { CollectCapabilityContentGenerator.verify_outputs!(registry, outputs: outputs) }
      File.binwrite(File.join(root, 'fastlane/metadata/en-GB/description.txt'), outputs.fetch('fastlane/metadata/en-GB/description.txt'))
      generated = File.join(root, CollectCapabilityContentGenerator::DART_PAGES)
      File.binwrite(generated, File.binread(generated).sub('Rwanda MoMo', 'International SEPA'))
      assert_raises(RuntimeError) { CollectCapabilityContentGenerator.verify_outputs!(registry, outputs: outputs) }
    end
  end

  def test_current_static_page_claims_and_faqs_are_consumed_from_registry
    assert_equal @registry.faqs, RENDERER.const_get(:PUBLIC_FAQS)
    @registry.data.fetch('static_pages').each do |path, fields|
      fields.each do |key, value|
        assert_equal @registry.symbolize(value), page(path).fetch(key.to_sym), "#{path}: #{key}"
      end
    end
  end

  def test_current_service_pages_and_aliases_render_planned_direction_and_real_contacts
    %w[/insurance/ /craas/ /our-partners/].each do |path|
      record = page(path)
      ([path] + Array(record[:aliases])).each do |route|
        html = @renderer.page_html(record.merge(path: route, canonical_path: path), current_path: route)
        assert_includes html, @renderer.esc(record.fetch(:intro))
        assert_match(/href="mailto:info@ikanisa\.com"/, html)
        refute_match(/class="[^"]*cta-group/, html)
        refute_match(/class="[^"]*cta-app[^\"]*" href="https:\/\/play\.google/, html)
        refute_match(/Collect works with licensed insurers|receive confirmation instantly|Use group savings as collateral|daily loan micro-repayment/i, html)
      end
    end
  end

  def test_real_home_and_group_copy_do_not_promote_future_services_or_instant_finality
    home = @renderer.page_html(page('/'))
    assert_includes home, @renderer.esc(@registry.copy('insurance'))
    assert_includes home, @renderer.esc(@registry.copy('credit_readiness'))
    assert_match(/href="https:\/\/play\.google\.com\/store\/apps\/details\?id=app\.cool\.mobile"/, home)
    group = @renderer.group_savings_page_html
    assert_includes group, @renderer.esc(@registry.copy('basic_phone'))
    assert_includes group, @renderer.esc(@registry.copy('finality'))
    refute_match(/zero.fee|receive confirmation instantly|USSD journeys make participation possible beyond smartphone|can support shared goals, collateral arrangements/i, home + group)
  end

  def test_routes_and_legal_source_are_preserved
    routes = PublicStaticRoutes.extract(SOURCE)
    assert_equal 18, routes.count { |row| %w[page alias share_landing].include?(row[:kind]) }
    assert_equal %w[/ /group-savings/ /insurance/ /craas/ /community-groups/ /our-partners/ /trust/ /privacy/ /terms/ /account-deletion/ /data-deletion/].sort,
      RENDERER.const_get(:PAGES).map { |row| row[:path] }.sort
    # Exercise the real writer against current source. Historical content hashes
    # cannot prove that generation preserves today's authored legal material.
    legal_sources = %w[
      content/legal/collect_legal_pages_bundle.yaml content/legal/collect_terms_of_use.yaml
      content/legal/collect_delete_account.yaml content/legal/collect_privacy_policy.yaml
    ]
    outputs = CollectCapabilityContentGenerator.outputs(@registry)
    assert_empty outputs.keys & legal_sources
    sources = (@data.fetch('source_inputs').keys + legal_sources + [
      CollectProductCapabilities::SOURCE, 'scripts/product_capabilities.rb',
      'scripts/generate_product_capability_content.rb', 'scripts/public_static_site_build.rb'
    ]).uniq
    Dir.mktmpdir('collect-capability-preservation-') do |root|
      (sources + outputs.keys).uniq.each do |path|
        destination = File.join(root, path)
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(File.join(ROOT, path), destination)
      end
      before = sources.to_h { |path| [path, Digest::SHA256.file(File.join(root, path)).hexdigest] }
      File.write(File.join(root, CollectCapabilityContentGenerator::DART_CAPABILITIES), 'stale generated consumer')
      stdout, stderr, result = Open3.capture3(
        'ruby', File.join(root, 'scripts/generate_product_capability_content.rb'), chdir: root
      )
      assert result.success?, "Actual isolated capability generation failed: #{stdout}#{stderr}"
      outputs.each { |path, bytes| assert_equal bytes.b, File.binread(File.join(root, path)), path }
      after = sources.to_h { |path| [path, Digest::SHA256.file(File.join(root, path)).hexdigest] }
      assert_equal before, after, 'Generation changed authored legal, capability or route source'
    end
  end
end
