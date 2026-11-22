# frozen_string_literal: true

require 'net/http'
require 'uri'

module PublicWebsiteHTTP
  private

  def fetch_page(url, redirects_left: 3)
    response, elapsed = fetch(url, redirects_left)
    {response: response, body: response.body.to_s, headers: response.each_header.to_h, elapsed: elapsed}
  end

  def fetch(url, redirects_left = 3)
    uri = URI(url)
    unless uri.is_a?(URI::HTTP) && uri.host && !uri.userinfo
      raise "Unsupported public website URL"
    end
    response = nil
    elapsed = nil
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
      request = Net::HTTP::Get.new(uri)
      response = http.request(request)
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    if response.is_a?(Net::HTTPRedirection) && redirects_left.positive?
      destination = URI.join(url, response.fetch("location"))
      unless destination.is_a?(URI::HTTP) && !destination.userinfo &&
             [destination.scheme, destination.host, destination.port] == [uri.scheme, uri.host, uri.port]
        raise "Cross-origin redirect rejected for #{url}"
      end
      followed_response, followed_elapsed = fetch(destination.to_s, redirects_left - 1)
      return [followed_response, elapsed + followed_elapsed]
    end
    [response, elapsed]
  end
end
