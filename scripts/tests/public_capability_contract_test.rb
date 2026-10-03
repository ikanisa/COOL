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

  def test_actual_source_actions_for_all_fifteen_routes
    PublicCapabilityContract::ROUTES.each do |route|
      assert_empty PublicCapabilityContract.action_failures(@registry, route, ctas(route)), route
    end
    assert_equal false, @registry.data.dig('approval', 'publication_approved')
  end

  def test_wrong_destination_and_lookalike_store_are_rejected
    %w[https://unverified.example/enroll https://play.google.com.evil.example/app mailto:other@example.com].each do |target|
      html = ctas('/').sub('https://play.google.com/store/apps/details?id=app.cool.mobile', target)
      refute_empty PublicCapabilityContract.action_failures(@registry, '/', html), target
    end
  end

  def test_wrong_platform_label_and_missing_action_are_rejected
    refute_empty PublicCapabilityContract.action_failures(@registry, '/', ctas('/').sub('Create a group on Android', 'Create a group on iOS'))
    refute_empty PublicCapabilityContract.action_failures(@registry, '/', ctas('/').sub('class="', 'aria-label="Get a loan now" class="'))
    refute_empty PublicCapabilityContract.action_failures(@registry, '/', ctas('/').sub(/<a[^>]+cta-touch[^>]*>.*?<\/a>/, ''))
  end

  def test_future_service_cannot_switch_contact_to_enrollment_or_add_group_creation
    PublicCapabilityContract::SERVICE_ROUTES.each_key do |route|
      html = ctas(route).sub('mailto:info@ikanisa.com', 'https://play.google.com/store/apps/details?id=app.cool.mobile')
      refute_empty PublicCapabilityContract.action_failures(@registry, route, html), route
      html = ctas(route) + '<a class="cta-group" href="https://play.google.com/store/apps/details?id=app.cool.mobile">Create a group on Android</a>'
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
    claims = [@registry.copy('regulatory_footer').sub('not a bank or wallet', 'a bank and wallet'),
              'Collect’s existing role is group record keeping, with deposit custody.',
              @registry.copy('creation').sub('eligible Android', 'eligible iOS'),
              'Consent is optional for SMS access.']
    claims.each { |claim| refute_empty PublicCapabilityContract.claim_failures(@registry, claim), claim }
  end

  def test_unknown_routes_cannot_gain_default_supported_actions
    assert_raises(RuntimeError) { PublicCapabilityContract.actions(@registry, '/new-provider/') }
  end
end
