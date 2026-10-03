# frozen_string_literal: true

require 'minitest/autorun'

class PublicLegalRenderingTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  BUILDER = File.join(ROOT, 'scripts/public_static_site_build.rb')
  SOURCE = File.read(BUILDER)
  STOP = SOURCE.index("\nallowed_build_roots = [") or raise 'Missing build execution boundary'
  RENDERER = Module.new
  RENDERER.module_eval(SOURCE[0...STOP], BUILDER)

  def setup
    @renderer = Object.new.extend(RENDERER)
  end

  def page(key)
    RENDERER.const_get(:PAGES).find { |candidate| candidate[:legal_key] == key }
  end

  def html(key)
    @renderer.legal_page_html(page(key))
  end

  def test_account_deletion_uses_real_app_actions_and_supported_contact
    rendered = html(:account_deletion)
    assert_includes rendered, 'Settings → Security → Delete data'
    assert_includes rendered, 'Select a reason for your request.'
    assert_includes rendered, 'Review the confirmation and select Submit.'
    assert_match(/href="mailto:info@ikanisa\.com/, rendered)
    refute_includes rendered, 'Complete the form below'
    refute_match(/<form\b/, rendered)
    refute_match(/<dt>(?:Heading|Path|Copy|Submit Label)<\/dt>/, rendered)
    assert_includes rendered, '<h3>Delete in the app</h3>'
    assert_includes rendered, '<h3>Delete without the app</h3>'
  end

  def test_account_request_definitions_and_retention_are_preserved
    authored = RENDERER.const_get(:LEGAL_DELETE_ACCOUNT)
    rendered = html(:account_deletion)
    authored.fetch('support_information').fetch('fields').each do |field|
      assert_includes rendered, @renderer.esc(field.fetch('label'))
      Array(field['options']).each { |option| assert_includes rendered, @renderer.esc(option) }
    end
    %w[what_happens_next before_we_can_complete_deletion data_we_may_retain partner_products].each do |key|
      authored.fetch(key).each do |name, value|
        next if name == 'heading'
        Array(value).each { |text| assert_includes rendered, @renderer.esc(text) }
      end
    end
    refute_includes rendered, 'Optional field.'
  end

  def test_unspecified_required_flag_does_not_invent_a_requirement
    rendered = @renderer.legal_form_fields_html([
      { 'label' => 'Unknown requirement', 'required' => nil },
      { 'label' => 'Required information', 'required' => true },
      { 'label' => 'Optional information', 'required' => false }
    ])
    assert_equal 1, rendered.scan('Required field.').length
    assert_equal 1, rendered.scan('Optional field.').length
  end

  def test_shared_deletion_instructions_match_existing_app_paths
    [:privacy, :data_deletion].each do |key|
      rendered = html(key)
      assert_includes rendered, 'Settings → Security → Delete data'
      refute_includes rendered, 'Select Privacy and Security'
      refute_includes rendered, 'Select Delete Account'
      assert_match(/href="mailto:info@ikanisa\.com/, rendered)
    end
    settings = File.read(File.join(ROOT, 'lib/features/settings/settings_screen.dart'))
    security = File.read(File.join(ROOT, 'lib/features/settings/settings_subscreens.dart'))
    deletion = File.read(File.join(ROOT, 'lib/features/status/account_legal_screens.dart'))
    assert_match(/title: 'Security'.*?context\.go\('\/settings\/security'\)/m, settings)
    assert_match(/title: 'Delete data'.*?context\.go\('\/settings\/account\/delete'\)/m, security)
    assert_includes deletion, "title: 'Submit delete request?'"
    assert_includes deletion, "confirmLabel: 'Submit'"
  end

  def test_authored_bundle_mirrors_and_request_sources_are_consistent
    bundle = RENDERER.const_get(:LEGAL_BUNDLE)
    privacy = RENDERER.const_get(:LEGAL_PRIVACY)
    terms = RENDERER.const_get(:LEGAL_TERMS)
    deletion = RENDERER.const_get(:LEGAL_DELETE_ACCOUNT)
    { 'privacy' => privacy, 'terms' => terms, 'delete_account' => deletion }.each do |key, page_content|
      assert_equal page_content, bundle.fetch('pages').fetch(key), key
    end
    canonical = deletion.fetch('delete_in_app')
    authored_section = privacy.fetch('sections').find { |section| section['id'] == 'account-and-data-deletion' }
    app = authored_section.fetch('subsections').first
    assert_equal canonical.fetch('path'), app.fetch('path')
    assert_equal canonical.fetch('steps'), app.fetch('steps')
    terms_section = terms.fetch('sections').find { |section| section['id'] == 'closing-or-deleting' }
    assert_equal "In the app under #{canonical.fetch('path')}", terms_section.fetch('request_channels').first
    support = authored_section.fetch('subsections')[1]
    assert_equal deletion.fetch('delete_without_app').fetch('copy'), support.fetch('body')
    assert_equal deletion.fetch('delete_without_app').fetch('email'), support.fetch('email')
    refute deletion.key?('form')
    %w[collect_delete_account collect_privacy_policy collect_terms_of_use collect_legal_pages_bundle].each do |name|
      source = File.read(File.join(ROOT, "content/legal/#{name}.yaml"))
      refute_match(/Privacy and Security|Complete the form below|Cookie Settings|separate Cookie Policy|(?:form:|submit_label:)/, source)
      refute_match(%r{:\s+/(?:privacy-request|cookies|subprocessors)(?:\s|$)}, source)
    end
  end

  def test_generated_legal_link_and_anchor_graph_has_existing_destinations
    pages = RENDERER.const_get(:PAGES)
    legal_pages = pages.select { |candidate| candidate[:legal_key] }
    fragments = legal_pages.to_h { |candidate| [candidate.fetch(:path), @renderer.legal_page_html(candidate)] }
    known_routes = pages.flat_map { |candidate| [candidate.fetch(:path)] + Array(candidate[:aliases]) }
    fragments.each do |route, rendered|
      ids = rendered.scan(/\bid="([^"]+)"/).flatten
      assert_equal ids.uniq, ids, "Duplicate anchors at #{route}"
      refute_match(/<(?:form|input|select|textarea)\b/, rendered)
      rendered.scan(/\bhref="([^"]+)"/).flatten.each do |encoded|
        href = CGI.unescapeHTML(encoded)
        if href.start_with?('mailto:')
          assert_match(/\Amailto:info@ikanisa\.com(?:\?subject=Collect\+privacy\+request)?\z/, href)
          next
        end
        target, anchor = href.split('#', 2)
        target = route if target.empty?
        assert_includes known_routes, target, "Missing route #{href} from #{route}"
        if anchor
          assert fragments.key?(target), "Unverified legal anchor target #{target}"
          assert_includes fragments.fetch(target).scan(/\bid="([^"]+)"/).flatten, anchor, "Missing anchor #{href}"
        end
      end
    end
    assert_includes fragments.fetch('/privacy/'), 'For questions about cookies and website technologies described in this notice, contact info@ikanisa.com.'
  end

  def test_dates_appear_once_and_policy_links_have_existing_destinations
    { privacy: :LEGAL_PRIVACY, terms: :LEGAL_TERMS }.each do |key, constant|
      content = RENDERER.const_get(constant)
      rendered = html(key)
      %w[last_updated effective_date].each do |date_key|
        next unless content[date_key]
        assert_equal 1, rendered.scan(content[date_key]).length, "#{key} #{date_key}"
      end
      refute_match(/href="\/(?:privacy-request|cookies|subprocessors)\//, rendered)
    end
    privacy = html(:privacy)
    assert_includes privacy, 'id="cookies"'
    assert_includes privacy, 'id="sharing"'
    assert_includes privacy, 'href="/privacy/#cookies"'
    assert_includes privacy, 'href="/privacy/#sharing"'
    assert_includes html(:terms), 'href="/privacy/#cookies"'
  end

  def test_unknown_substantive_policy_values_are_retained_and_escaped
    rendered = @renderer.legal_hash_html({ 'heading' => 'Policy heading', 'copy' => 'Exact policy <notice>', 'record_category' => 'Financial records' })
    assert_includes rendered, '<h3>Policy heading</h3>'
    assert_includes rendered, 'Exact policy &lt;notice&gt;'
    assert_includes rendered, 'Financial records'
    refute_includes rendered, '<dt>Heading</dt>'
  end

  def test_repeated_support_aliases_keep_one_usable_contact
    rendered = @renderer.legal_hash_html({ 'heading' => 'Need help?', 'privacy' => 'info@ikanisa.com', 'complaints' => 'info@ikanisa.com', 'partnerships' => 'info@ikanisa.com' })
    assert_equal 1, rendered.scan('href="mailto:info@ikanisa.com"').length
    assert_includes rendered, '<h3>Need help?</h3>'
  end
end
