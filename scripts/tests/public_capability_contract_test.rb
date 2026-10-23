# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../qa/public_capability_contract'

class PublicCapabilityContractTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  BUILDER = File.join(ROOT, 'scripts/public_static_site_build.rb')
  SOURCE = File.read(BUILDER)
  STOP = SOURCE.index("\nallowed_build_roots = [") or raise 'Missing build execution boundary'
  RENDERER = Module.new
  RENDERER.module_eval(SOURCE[0...STOP], BUILDER)

  def setup
    @registry = CollectProductCapabilities.new(ROOT)
    @renderer = Object.new.extend(RENDERER)
  end

  def ctas(route)
    canonical = { '/protection/' => '/insurance/', '/credit-readiness/' => '/craas/', '/partners/' => '/our-partners/', '/security/' => '/trust/' }.fetch(route, route)
    page = RENDERER.const_get(:PAGES).find { |row| row[:path] == canonical } or raise 'Missing actual source page'
    @renderer.cta_links_html(route, page, surface: :hero) + @renderer.cta_links_html(route, page, surface: :start)
  end

  def mutate(source, pattern, replacement)
    matches = pattern.is_a?(Regexp) ? pattern.match?(source) : source.include?(pattern)
    assert matches, 'Negative mutation must target the current fixture'
    changed = source.sub(pattern, replacement)
    refute_equal source, changed, 'Negative mutation must change the current fixture'
    changed
  end

  def test_actual_source_actions_for_all_fifteen_routes
    PublicCapabilityContract::ROUTES.each do |route|
      assert_empty PublicCapabilityContract.action_failures(@registry, route, ctas(route)), route
    end
    assert_equal false, @registry.data.dig('approval', 'publication_approved')
  end

  def test_identical_group_and_app_actions_share_one_link_per_cluster
    expected = PublicCapabilityContract.actions(@registry, '/')
    refute expected.key?('cta-group')
    [:hero, :start].each do |surface|
      page = RENDERER.const_get(:PAGES).find { |row| row[:path] == '/' }
      links = PublicCapabilityContract.anchors(@renderer.cta_links_html('/', page, surface: surface))
      assert_equal 1, links.count { |link| link['href'] == expected.fetch('cta-app').fetch('href') }
      assert_equal 1, links.count { |link| link['classes'].include?('cta-touch') }
    end
  end

  def test_distinct_group_action_remains_required_and_strictly_matched
    original = @registry
    distinct = Object.new
    distinct.define_singleton_method(:public_action) { |id| original.public_action(id) }
    distinct.define_singleton_method(:source_action) do |id, **options|
      original.source_action(id, **options).merge('label' => 'Create a private group')
    end
    actions = PublicCapabilityContract.actions(distinct, '/')
    assert actions.key?('cta-group')
    html = actions.map { |role, value| %(<a class="#{role}" href="#{CGI.escapeHTML(value.fetch('href'))}">#{CGI.escapeHTML(value.fetch('label'))}</a>) }.join * 2
    assert_empty PublicCapabilityContract.action_failures(distinct, '/', html)
    missing = html.gsub(/<a[^>]+cta-group[^>]*>.*?<\/a>/, '')
    refute_empty PublicCapabilityContract.action_failures(distinct, '/', missing)
    wrong = html.sub('Create a private group', 'Create a public group')
    refute_empty PublicCapabilityContract.action_failures(distinct, '/', wrong)
  end

  def test_wrong_destination_and_lookalike_store_are_rejected
    %w[https://unverified.example/enroll https://play.google.com.evil.example/app mailto:other@example.com].each do |target|
      html = mutate(ctas('/'), CGI.escapeHTML(@registry.public_action('group_records').fetch('href')), target)
      refute_empty PublicCapabilityContract.action_failures(@registry, '/', html), target
    end
  end

  def test_wrong_platform_label_and_missing_action_are_rejected
    refute_empty PublicCapabilityContract.action_failures(@registry, '/', mutate(ctas('/'), CGI.escapeHTML(@registry.public_action('group_records').fetch('label')), 'Use USSD on iOS'))
    refute_empty PublicCapabilityContract.action_failures(@registry, '/', mutate(ctas('/'), 'class="', 'aria-label="Get a loan now" class="'))
    refute_empty PublicCapabilityContract.action_failures(@registry, '/', mutate(ctas('/'), /<a[^>]+cta-touch[^>]*>.*?<\/a>/, ''))
  end

  def test_future_service_cannot_switch_contact_to_enrollment_or_add_group_creation
    PublicCapabilityContract::SERVICE_ROUTES.each_key do |route|
      html = mutate(ctas(route), 'mailto:info@ikanisa.com', 'https://play.google.com/store/apps/details?id=app.cool.mobile')
      refute_empty PublicCapabilityContract.action_failures(@registry, route, html), route
      original = ctas(route)
      html = original + '<a class="cta-group" href="https://play.google.com/store/apps/details?id=app.cool.mobile">Create a group on Android</a>'
      refute_equal original, html, 'Unavailable service mutation must add its forbidden action'
      refute_empty PublicCapabilityContract.action_failures(@registry, route, html), route
    end
  end

  def test_exact_truthful_limitations_and_future_descriptions_are_allowed
    copy = [@registry.copy('regulatory_footer'), @registry.copy('creation'), @registry.copy('insurance'),
            @registry.copy('credit_readiness'), @registry.copy('loans'), 'No custody',
            'Collect’s existing role is group record keeping, without deposit custody.'].join('</p><p>')
    assert_empty PublicCapabilityContract.claim_failures(@registry, '<p>' + copy + '</p>')
  end

  def test_unqualified_financial_provider_and_platform_claims_are_rejected_even_beside_a_disclaimer
    claims = [
      'Collect is a wallet.', 'Collect holds customer funds.', 'Collect accepts deposits.',
      'We offer custody of your contributions.', 'Collect works with licensed insurers.',
      'Collect partners with banks.', 'Collect offers insurance.', 'Collect provides loans.',
      'Insurance is available through Collect.', 'Credit-readiness intake is active in Collect.',
      'iOS supports Collect USSD.', 'Web provides receipt-SMS.',
      'Basic phones offer private-group creation.'
    ]
    claims.each do |claim|
      html = '<p>' + @registry.copy('regulatory_footer') + '</p><p>' + claim + '</p>'
      refute_empty PublicCapabilityContract.claim_failures(@registry, html), claim
    end
  end

  def test_mutated_negation_and_consent_qualification_are_rejected
    claims = [mutate(@registry.copy('regulatory_footer'), 'not a bank or wallet', 'a bank and wallet'),
              'Collect’s existing role is group record keeping, with deposit custody.',
              mutate(@registry.copy('platform_limits'), 'The Collect app’s USSD handoff and receipt-SMS access require Android.', 'iOS supports Collect USSD.'),
              'Consent is optional for SMS access.']
    claims.each { |claim| refute_empty PublicCapabilityContract.claim_failures(@registry, claim), claim }
  end

  def test_unknown_routes_cannot_gain_default_supported_actions
    assert_raises(RuntimeError) { PublicCapabilityContract.actions(@registry, '/new-provider/') }
  end
end
