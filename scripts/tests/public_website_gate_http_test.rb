# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../qa/public_website/checks'
require_relative '../qa/public_website/http'

class PublicWebsiteGateHTTPTest < Minitest::Test
  include PublicWebsiteChecks
  include PublicWebsiteHTTP

  def test_same_origin_redirect_is_followed
    first = redirect('/group-savings/')
    final = Net::HTTPOK.new('1.1', '200', 'OK')
    requests = []
    stub = stub_responses(requests, first, final)
    Net::HTTP.stub(:start, stub) do
      response, duration = fetch('https://collect.example.test/groups')
      assert_equal final, response
      assert_operator duration, :>=, 0
    end
    assert_equal [
      ['collect.example.test', 443, '/groups'],
      ['collect.example.test', 443, '/group-savings/'],
    ], requests
  end

  def test_redirects_cannot_change_the_scheme_port_or_host
    [
      'http://collect.example.test/groups',
      'https://collect.example.test:8443/groups',
      '//elsewhere.example.test/groups',
    ].each do |destination|
      requests = []
      stub = stub_responses(requests, redirect(destination))
      Net::HTTP.stub(:start, stub) do
        error = assert_raises(RuntimeError) { fetch('https://collect.example.test/groups') }
        assert_match(/Cross-origin redirect rejected/, error.message)
      end
      assert_equal [['collect.example.test', 443, '/groups']], requests
    end
  end

  def test_retired_privacy_route_may_be_unavailable_or_redirect_to_its_replacement
    request = 'https://collect.example.test/subprocessors/'
    replacement = '/privacy/#sharing'
    assert retired_privacy_response?(request, Net::HTTPNotFound.new('1.1', '404', 'Not Found'), replacement)
    assert retired_privacy_response?(request, redirect(replacement), replacement)
    assert retired_privacy_response?(request, redirect('https://collect.example.test/privacy/#sharing'), replacement)
    refute retired_privacy_response?(request, Net::HTTPOK.new('1.1', '200', 'OK'), replacement)
    refute retired_privacy_response?(request, redirect('/privacy/'), replacement)
    refute retired_privacy_response?(request, redirect('privacy/#sharing'), replacement)
    refute retired_privacy_response?(request, redirect('https://elsewhere.example.test/privacy/#sharing'), replacement)
  end

  private

  def redirect(location)
    response = Net::HTTPFound.new('1.1', '302', 'Found')
    response['location'] = location
    response
  end

  def stub_responses(requests, *responses)
    lambda do |host, port, *_options, &work|
      http = Object.new
      http.define_singleton_method(:request) do |request|
        requests << [host, port, request.path]
        responses.shift
      end
      work.call(http)
    end
  end
end
