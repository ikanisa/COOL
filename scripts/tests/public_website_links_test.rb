# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../qa/public_website_links'

class PublicWebsiteLinksTest < Minitest::Test
  def inspect_links(pages, responses)
    @calls = []
    PublicWebsiteLinks.check(base_url: 'https://collect.example/', pages: pages, fetcher: lambda { |url|
      @calls << url
      responses.fetch(url)
    })
  end

  def test_exposed_privacy_links_cannot_pass_with_404_destinations
    result = inspect_links({ '/privacy/' => '<a href="/privacy-request/">Request</a><a href="/cookies/">Cookies</a>' }, {
      'https://collect.example/privacy-request/' => { status: 404, body: '' },
      'https://collect.example/cookies/' => { status: 404, body: '' }
    })
    assert_equal 2, result[:failures].length
    assert result[:failures].all? { |failure| failure[:reason] == 'destination_not_http_200' && failure[:status] == 404 }
  end

  def test_relative_links_and_encoded_fragments_resolve_to_real_targets
    result = inspect_links({ '/privacy/' => '<a href="../trust/#data%2Brights">Trust</a>' }, {
      'https://collect.example/trust/' => { status: 200, body: '<section id="data+rights">Rights</section>' }
    })
    assert_empty result[:failures]
    assert_equal 1, result[:links_checked]
  end

  def test_missing_fragment_fails_even_when_the_page_returns_200
    result = inspect_links({ '/privacy/' => '<a href="#missing">Missing</a>' }, {
      'https://collect.example/privacy/' => { status: 200, body: '<main id="content"></main>' }
    })
    assert_equal 'missing_fragment_target', result[:failures].first[:reason]
  end

  def test_deduplicates_fetches_without_omitting_distinct_source_links
    result = inspect_links({ '/' => '<a href="/trust/">Trust</a><a href="/trust/">Trust again</a>', '/privacy/' => '<a href="/trust/#security">Security</a>' }, {
      'https://collect.example/trust/' => { status: 200, body: '<h2 id="security">Security</h2>' }
    })
    assert_empty result[:failures]
    assert_equal 2, result[:links_checked]
    assert_equal 1, result[:destinations_checked]
    assert_equal ['https://collect.example/trust/'], @calls
  end

  def test_external_links_and_non_http_actions_are_never_fetched
    html = '<a href="https://elsewhere.example/">Other</a><a href="//elsewhere.example/">Other</a><a href="mailto:info@example.com">Email</a><a href="tel:123">Call</a><a href="collect://group/test">App</a><a href="http://collect.example/">Different origin</a>'
    result = inspect_links({ '/' => html }, {})
    assert_empty result[:failures]
    assert_empty @calls
  end

  def test_query_entities_are_decoded_and_non_html_fragments_are_not_dom_ids
    result = inspect_links({ '/' => '<a href="/document.pdf?first=1&amp;second=2#page=3">Document</a>' }, {
      'https://collect.example/document.pdf?first=1&second=2' => { status: 200, content_type: 'application/pdf', body: '' }
    })
    assert_empty result[:failures]
    assert_equal 1, result[:destinations_checked]
  end

  def test_inert_markup_and_data_attributes_do_not_count_as_links_or_targets
    html = '<!-- <a href="/comment/">Comment</a> --><script>const template = `<a href="/script/">Script</a>`;</script><a data-href="/inactive/">Inactive</a><a href="#missing" data-href="/unused/">Missing</a>'
    result = inspect_links({ '/' => html }, {
      'https://collect.example/' => { status: 200, body: '<div data-id="missing"></div>' }
    })
    assert_equal ['https://collect.example/'], @calls
    assert_equal 1, result[:links_checked]
    assert_equal 'missing_fragment_target', result[:failures].first[:reason]
  end
end
