# frozen_string_literal: true

require 'cgi'
require 'json'
require_relative '../product_capabilities'

# Capability-aware assertions for actual generated/rendered product content.
# This is product evidence, never availability or publication approval.
module PublicCapabilityContract
  ROUTES = %w[/ /group-savings/ /community-groups/ /insurance/ /protection/ /craas/ /credit-readiness/ /our-partners/ /partners/ /trust/ /security/ /privacy/ /terms/ /account-deletion/ /data-deletion/].freeze
  SERVICE_ROUTES = {
    '/insurance/' => 'insurance', '/protection/' => 'insurance',
    '/craas/' => 'credit_readiness', '/credit-readiness/' => 'credit_readiness',
    '/our-partners/' => 'loans', '/partners/' => 'loans'
  }.freeze

  def self.actions(registry, route)
    raise 'Unknown public capability route' unless ROUTES.include?(route)
    id = SERVICE_ROUTES.fetch(route, 'group_records')
    result = { 'cta-app' => registry.public_action(id), 'cta-touch' => registry.public_action('support') }
    result['cta-group'] = registry.source_action('private_group_creation', region: 'RW', platform: 'android') if id == 'group_records'
    result
  end

  def self.anchors(html)
    html.scan(%r{<a\b([^>]*)>(.*?)</a>}mi).map do |attrs, text|
      { 'classes' => attrs[/\bclass="([^"]*)"/, 1].to_s.split,
        'href' => CGI.unescapeHTML(attrs[/\bhref="([^"]*)"/, 1].to_s),
        'label' => CGI.unescapeHTML(text.gsub(/<[^>]*>/, '')).strip,
        'aria_label' => (attrs[/\baria-label="([^"]*)"/, 1] && CGI.unescapeHTML(attrs[/\baria-label="([^"]*)"/, 1])) }
    end
  end

  def self.action_failures(registry, route, html)
    expected = actions(registry, route)
    links = anchors(html)
    failures = []
    %w[cta-app cta-group cta-touch].each do |role|
      actual = links.select { |link| link['classes'].include?(role) }
      if !expected.key?(role)
        failures << { 'role' => role, 'reason' => 'Unavailable service exposes enrollment/group action' } unless actual.empty?
        next
      end
      failures << { 'role' => role, 'reason' => 'Missing repeated page action' } if actual.length < 2
      actual.each do |link|
        failures << { 'role' => role, 'reason' => 'Wrong capability label or destination', 'actual' => link, 'expected' => expected[role] } unless
          link['label'] == expected[role]['label'] && link['href'] == expected[role]['href'] &&
          (link['aria_label'].nil? || link['aria_label'] == expected[role]['label'])
      end
    end
    failures
  end

  def self.visible_text(html)
    CGI.unescapeHTML(html.gsub(/<script\b.*?<\/script>/mi, ' ').gsub(/<style\b.*?<\/style>/mi, ' ').gsub(/<[^>]+>/, ' ')).gsub(/\s+/, ' ').strip
  end

  def self.claim_failures(registry, html)
    # Permit only these exact source-qualified limitations, not a generic
    # sentence containing "not" elsewhere on the page. Mutations lose exemption.
    text = visible_text(html)
    exemptions = [registry.copy('regulatory_footer'), registry.copy('creation'),
                  'No custody', 'Collect’s existing role is group record keeping, without deposit custody.']
    exemptions.each { |phrase| text = text.gsub(phrase, ' ') }
    patterns = {
      'consent' => /consent/i,
      'restricted_financial_claims' => /host[- ]bank|custody|wallet|collateral lock|collateralized|underwrit|Stripe fallback|backup payment|Android\/iOS live/i,
      'unqualified_customer_funds' => /\bCollect\s+(?:holds?|keeps?|accepts?|mobilises?|mobilizes?)\s+(?:customer\s+funds|group\s+capital|deposits)\b/i,
      'unqualified_provider_service' => /\bCollect\s+(?:works?|partners?)\s+with\s+(?:licensed\s+)?(?:insurers?|banks?|lenders?)\b/i,
      'unqualified_active_service' => /\b(?:Collect\s+(?:offers?|provides?)\s+(?:insurance|loans?|credit|premium\s+financ(?:e|ing))|(?:insurance|loans?|credit[- ]readiness\s+intake|claims\s+support)\s+(?:is|are)\s+(?:currently\s+)?(?:available|active|live)\s+(?:in|through)\s+Collect)\b/i,
      'unqualified_platform_handoff' => /\b(?:iOS|web|basic[- ]phones?)\s+(?:supports?|provides?|offers?)\s+(?:Collect\s+)?(?:USSD|receipt[- ]SMS|private[- ]group\s+creation)\b/i
    }
    patterns.map { |id, pattern| { 'pattern' => id, 'match' => text[pattern] } if text.match?(pattern) }.compact
  end
end

if $PROGRAM_NAME == __FILE__
  registry = CollectProductCapabilities.new(File.expand_path('../..', __dir__))
  puts JSON.generate('registry_sha256' => registry.sha256, 'approval' => registry.data.fetch('approval'),
                     'routes' => PublicCapabilityContract::ROUTES.to_h { |route| [route, PublicCapabilityContract.actions(registry, route)] })
end
